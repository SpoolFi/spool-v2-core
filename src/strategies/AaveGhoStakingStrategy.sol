// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "forge-std/console.sol";

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../external/interfaces/strategies/aave/IStakedGho.sol";
import "../libraries/BytesUint256Lib.sol";
import "../libraries/PackedRange.sol";
import "./StrategyNonAtomic.sol";

error AaveGhoStakingBeforeDepositCheckFailed();
error AaveGhoStakingBeforeRedeemalCheckFailed();
error SwapSlippage();

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
// - already in cooldown period
//   - tx 1:
//     - redeem GHO
//     - swap GHO into underlying asset
// - not in cooldown period
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

contract AaveGhoStakingStrategy is StrategyNonAtomic {
    using SafeERC20 for IERC20Metadata;

    event SwapEstimation(address tokenIn, address tokenOut, uint256 tokenInAmount);

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
        uint256 ghoAmount = _swapFromSlippages(tokens[0], address(gho), assets[0], slippages);
        if (ghoAmount > 0) {
            gho.approve(address(stakedGho), ghoAmount);
            stakedGho.stake(address(this), ghoAmount);
        }

        return true;
    }

    function _initializeWithdrawalFromProtocol(address[] calldata tokens, uint256 shares, uint256[] calldata slippages)
        internal
        override
        returns (bool)
    {
        uint256 toUnstake = stakedGho.balanceOf(address(this)) * shares / totalSupply();
        if (toUnstake == 0) {
            return true;
        }

        try stakedGho.redeem(address(this), toUnstake) {
            uint256 ghoAmount = gho.balanceOf(address(this));
            _swapFromSlippages(address(gho), tokens[0], ghoAmount, slippages);

            return true;
        } catch {
            stakedGho.cooldown();
            _toUnstake = toUnstake;

            return false;
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
        stakedGho.redeem(address(this), _toUnstake);

        _swapWithdrawals(tokens[0], IERC20Metadata(gho).balanceOf(address(this)), continuationData);

        return true;
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
            // TODO: check if there are some other rewards to claim (merit program, etc.)

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

        // TODO: check if there are some other rewards to claim (merit program, etc.)
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
        // TODO: check if there are some other rewards to claim (merit program, etc.)
    }

    function _swapFromSlippages(address tokenIn, address tokenOut, uint256 tokenInAmount, uint256[] calldata slippages)
        internal
        returns (uint256)
    {
        if (_isViewExecution() && slippages[3] == 1) {
            emit SwapEstimation(tokenIn, tokenOut, tokenInAmount);
            return 0;
        }

        if (slippages.length < 5) {
            revert SwapSlippage();
        }

        address swapTarget = address(uint160(slippages[3]));
        uint256 bytesLength = slippages[4];
        uint256[] memory toDecode = new uint256[](slippages.length - 5);
        for (uint256 i; i < toDecode.length; ++i) {
            toDecode[i] = slippages[5 + i];
        }
        bytes memory payload = BytesUint256Lib.decode(toDecode, bytesLength);

        address[] memory tokensIn = new address[](1);
        tokensIn[0] = tokenIn;
        SwapInfo[] memory swapInfos = new SwapInfo[](1);
        swapInfos[0] = SwapInfo(swapTarget, tokenIn, payload);
        address[] memory tokensOut = new address[](1);
        tokensOut[0] = tokenOut;

        IERC20Metadata(tokenIn).safeTransfer(address(_swapper), tokenInAmount);
        return _swapper.swap(tokensIn, swapInfos, tokensOut, address(this))[0];
    }

    function _swapWithdrawals(address tokenOut, uint256 tokenInAmount, bytes calldata continuationData)
        internal
        returns (uint256)
    {
        (address swapTarget, bytes memory swapCallData) = abi.decode(continuationData, (address, bytes));

        if (_isViewExecution() && swapTarget == address(0)) {
            emit SwapEstimation(address(gho), tokenOut, tokenInAmount);
            return 0;
        }

        address[] memory tokensIn = new address[](1);
        tokensIn[0] = address(gho);
        SwapInfo[] memory swapInfos = new SwapInfo[](1);
        swapInfos[0] = SwapInfo(swapTarget, address(gho), swapCallData);
        address[] memory tokensOut = new address[](1);
        tokensOut[0] = tokenOut;

        IERC20Metadata(gho).safeTransfer(address(_swapper), tokenInAmount);
        return _swapper.swap(tokensIn, swapInfos, tokensOut, address(this))[0];
    }
}
