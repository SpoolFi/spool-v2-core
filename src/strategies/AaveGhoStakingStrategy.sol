// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../external/interfaces/strategies/aave/IStakedGho.sol";
import "../libraries/BytesUint256Lib.sol";
import "../libraries/PackedRange.sol";
import "./libraries/AaveGhoStakingStrategyLib.sol";
import "./helpers/SwapAdapter.sol";
import "./StrategyNonAtomic.sol";

/**
 * @notice Used when before deposit checks fail.
 */
error AaveGhoStakingBeforeDepositCheckFailed();

/**
 * @notice Used when before redeemal checks fail.
 */
error AaveGhoStakingBeforeRedeemalCheckFailed();

// about strategy
// - single asset
// - yield
//   - no base yield under normal conditions
//     - staked GHO can be slashed to cover losses in the aave protocol
//       - negative base yield
//     - after slashing, over-slashed funds can be returned to stakers
//       - positive base yield
//   - rewards
//     - AAVE token
// - atomic deposit
// - non-atomic withdrawal
//   - 20 days cooldown
//   - 2 days unstake window
//     - atomic withdrawal is possible during the unstake window

// slippages
// - mode selection: slippages[0]
// - DHW with deposit: slippages[0] == 0
//   - beforeDepositCheck: slippages[1]
//   - beforeRedeemalCheck: slippages[2]
//   - swap data: slippages[3...]
// - DHW with withdrawal: slippages[0] == 1
//   - beforeDepositCheck: slippages[1]
//   - beforeRedeemalCheck: slippages[2]
//   - swap data: slippages[3...]

// encoded swap data:
// - swap data: slippages[i...]
//   - slippages[i]: estimation flag: 1 - estimation, else - swap target
//   - slippages[i + 1]: swap info bytes length
//   - slippages[i + 2...]: swap info bytes

// deposit flow (atomic):
// - swap underlying asset into GHO
// - stake GHO
// withdrawal flow (non-atomic):
// - already in unstake window
//   - tx 1:
//     - redeem GHO
//     - swap GHO into underlying asset
// - not in unstake window
//   - tx 1:
//     - trigger cooldown of staked GHO
//   - wait for cooldown to end, but be careful of the unstake window
//   - tx 2:
//     - redeem GHO
//     - swap GHO into underlying asset
// compoud flow:
// - claim rewards from staking contract
// - swap rewards to underlying asset
// - include with deposit

contract AaveGhoStakingStrategy is StrategyNonAtomic, SwapAdapter {
    using SafeERC20 for IERC20Metadata;

    IERC20Metadata public immutable gho;
    IStakedGho public immutable stakedGho;

    IUsdPriceFeedManager private immutable _priceFeedManager;
    ISwapper private immutable _swapper;
    uint256 private immutable _constantShareAmount;
    uint256 private _lastPreviewRedeem;
    uint256 private _toUnstake;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IERC20Metadata gho_,
        IStakedGho stakedGho_,
        IUsdPriceFeedManager priceFeedManager_,
        ISwapper swapper_
    ) StrategyNonAtomic(assetGroupRegistry_, accessControl_, NULL_ASSET_GROUP_ID) {
        if (
            address(gho_) == address(0) || address(stakedGho_) == address(0) || address(priceFeedManager_) == address(0)
                || address(swapper_) == address(0)
        ) {
            revert ConfigurationAddressZero();
        }

        gho = gho_;
        stakedGho = stakedGho_;

        _priceFeedManager = priceFeedManager_;
        _swapper = swapper_;
        _constantShareAmount = 10 ** (stakedGho.decimals() * 2);
    }

    function initialize(string memory strategyName_, uint256 assetGroupId_) external initializer {
        __Strategy_init(strategyName_, assetGroupId_);

        _lastPreviewRedeem = _previewConstantRedeem();
    }

    function assetRatio() external pure override returns (uint256[] memory) {
        uint256[] memory _assetRatio = new uint256[](1);
        _assetRatio[0] = 1;
        return _assetRatio;
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public override {
        if (_isViewExecution()) {
            uint256[] memory beforeDepositCheckSlippageAmounts = new uint256[](1);
            beforeDepositCheckSlippageAmounts[0] = amounts[0];

            emit BeforeDepositCheckSlippages(beforeDepositCheckSlippageAmounts);
            return;
        }

        if (slippages[0] > 2) {
            revert AaveGhoStakingBeforeDepositCheckFailed();
        }

        if (!PackedRange.isWithinRange(slippages[1], amounts[0])) {
            revert AaveGhoStakingBeforeDepositCheckFailed();
        }
    }

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public override {
        if (_isViewExecution()) {
            emit BeforeRedeemalCheckSlippages(ssts);
            return;
        }

        uint256 slippage;
        if (slippages[0] < 2) {
            slippage = slippages[2];
        } else if (slippages[0] == 2) {
            slippage = slippages[1];
        } else {
            revert AaveGhoStakingBeforeRedeemalCheckFailed();
        }

        if (!PackedRange.isWithinRange(slippage, ssts)) {
            revert AaveGhoStakingBeforeRedeemalCheckFailed();
        }
    }

    function getUnderlyingAssetAmounts() external view override returns (uint256[] memory amounts) {
        address underlying = assets()[0];

        amounts = new uint256[](1);
        amounts[1] =
            _priceFeedManager.usdToAsset(underlying, _priceFeedManager.assetToUsd(address(gho), _underlyingGhoAmount()));

        return amounts;
    }

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager_)
        internal
        view
        override
        returns (uint256 usdWorth)
    {
        uint256 ghoAmount = _underlyingGhoAmount();
        if (ghoAmount > 0) {
            // is this OK, the exchange rate will be for underlying asset, not GHO
            usdWorth = priceFeedManager_.assetToUsdCustomPrice(address(gho), ghoAmount, exchangeRates[0]);
        }
    }

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        uint256 currentRedeem = _previewConstantRedeem();
        baseYieldPercentage = _calculateYieldPercentage(_lastPreviewRedeem, currentRedeem);
        _lastPreviewRedeem = currentRedeem;
    }

    function _initializeDepositToProtocol(
        address[] calldata tokens,
        uint256[] memory assets,
        uint256[] calldata slippages
    ) internal override returns (bool) {
        uint256 ghoAmount = _swap(_swapper, tokens[0], address(gho), assets[0], slippages, 3);
        if (ghoAmount > 0) {
            gho.approve(address(stakedGho), ghoAmount);
            stakedGho.stake(address(this), ghoAmount);
        }

        return true;
    }

    function _initializeWithdrawalFromProtocol(address[] calldata tokens, uint256 shares, uint256[] calldata slippages)
        internal
        override
        returns (bool, bool)
    {
        uint256 toUnstake = stakedGho.balanceOf(address(this)) * shares / totalSupply();
        if (toUnstake == 0) {
            return (true, true);
        }

        try stakedGho.redeem(address(this), toUnstake) {
            uint256 ghoAmount = gho.balanceOf(address(this));
            _swap(_swapper, address(gho), tokens[0], ghoAmount, slippages, 3);

            return (true, true);
        } catch {
            stakedGho.cooldown();
            _toUnstake = toUnstake;

            return (false, false);
        }
    }

    function _continueDepositToProtocol(address[] calldata, bytes calldata)
        internal
        pure
        override
        returns (bool, uint256, uint256)
    {
        revert("NotImplemented");
    }

    function _continueWithdrawalFromProtocol(address[] calldata tokens, bytes calldata continuationData)
        internal
        override
        returns (bool finished)
    {
        return AaveGhoStakingStrategyLib.continueWithdrawalFromProtocol(
            tokens, continuationData, gho, stakedGho, _swapper, _toUnstake
        );
    }

    function _prepareCompoundImpl(address[] calldata tokens, SwapInfo[] calldata compoundSwapInfo)
        internal
        override
        returns (bool compoundNeeded, uint256[] memory assetsToCompound)
    {
        if (compoundSwapInfo.length > 0) {
            compoundNeeded = true;
            assetsToCompound = new uint256[](1);

            // claim rewards from staking contract
            stakedGho.claimRewards(address(_swapper), stakedGho.getTotalRewardsBalance(address(this)));

            assetsToCompound = _swapper.swap(_getRewardTokens(), compoundSwapInfo, tokens, address(this));
        }
    }

    function _swapAssets(address[] memory, uint256[] memory, SwapInfo[] calldata) internal override {}

    function _emergencyWithdrawImpl(uint256[] calldata, address recipient) internal override {
        try stakedGho.redeem(recipient, stakedGho.balanceOf(address(this))) {}
        catch {
            stakedGho.cooldown();
        }
    }

    function _getProtocolRewardsInternal()
        internal
        view
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        tokens = _getRewardTokens();
        amounts = new uint256[](tokens.length);

        amounts[0] = stakedGho.getTotalRewardsBalance(address(this));
    }

    function _underlyingGhoAmount() internal view returns (uint256) {
        return stakedGho.previewRedeem(stakedGho.balanceOf(address(this)));
    }

    function _previewConstantRedeem() internal view returns (uint256) {
        return stakedGho.previewRedeem(_constantShareAmount);
    }

    function _getRewardTokens() internal view returns (address[] memory rewardTokens) {
        rewardTokens = new address[](1);
        rewardTokens[0] = address(stakedGho.REWARD_TOKEN());
    }
}
