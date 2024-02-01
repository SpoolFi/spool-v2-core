// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/utils/math/Math.sol";
import "../external/interfaces/strategies/gearbox/v3/IFarmingPool.sol";
import "../external/interfaces/strategies/gearbox/v3/IPoolV3.sol";
import "../interfaces/ISwapper.sol";
import "../libraries/PackedRange.sol";
import "../strategies/Strategy.sol";

error GearboxV3DepositCheckFailed();
error GearboxV3RedeemalCheckFailed();
error GearboxV3DepositSlippagesFailed();
error GearboxV3RedeemalSlippagesFailed();
error GearboxV3DepositFailed();
error GearboxV3RedeemalFailed();

// One asset: WETH || USDC
//
// One reward: GEAR
//
// slippages:
// - mode selection: slippages[0]
//
// - DHW with deposit: slippages[0] == 0
//   - beforeDepositCheck: slippages[1]
//   - beforeRedeemalCheck: slippages[2]
//   - compound: slippages[3]
//   - _depositToProtocol: slippages[4]
//
// - DHW with withdrawal: slippages[0] == 1
//   - beforeDepositCheck: slippages[1]
//   - beforeRedeemalCheck: slippages[2]
//   - compound: slippages[3]
//   - _redeemFromProtocol: slippages[4]
//
// - reallocate: slippages[0] == 2
//   - beforeDepositCheck: depositSlippages[1]
//   - _depositToProtocol: depositSlippages[2]
//   - beforeRedeemalCheck: withdrawalSlippages[1]
//   - _redeemFromProtocol: withdrawalSlippages[2]

// - redeemFast or emergencyWithdraw: slippages[0] == 3
//   - _redeemFromProtocol: slippages[1]
//   - _emergencyWithdrawImpl: slippages[1]
//
// Description:
// This is a Convex strategy. ETH is swapped for stETH (Lido) and frxETH,
// and used to add proportional liquidity to the Curve st-frxETH Factory
// Plain Pool, with the outgoing LP token being staked on Convex for boosted
// rewards.
//
// The strategy supports two ways to obtain each of the stETH and frxETH tokens:
// either by acquiring it directly on their respective protocols, or by buying
// the token via their respective Curve ETH pools (See the adapter libraries
// for each token).
//
// The do-hard-worker can decide which way to use based on profitability by
// setting appropriate slippages (see slippages above).
//
// Since staked ETH on Lido and Frax is used to spin-up validators, it cannot
// be unstaked immediately. To exit the protocol, the strategy sells the
// tokens on their respective Curve ETH pools.
contract GearboxV3Strategy is Strategy {
    using SafeERC20 for IERC20;

    /// @notice Swapper implementation
    ISwapper public immutable swapper;

    /// @notice COMP token
    /// @dev Reward token when participating in the GearboxV3 protocol.
    IERC20 public immutable gear;

    /// @notice dToken implementation (staking token)
    IPoolV3 public immutable dToken;

    /// @notice sdToken implementation (lp token)
    IFarmingPool public immutable sdToken;

    /// @notice supplyRate at the last DHW.
    uint256 private _lastSupplyRate;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        IFarmingPool sdToken_
    ) Strategy(assetGroupRegistry_, accessControl_, NULL_ASSET_GROUP_ID) {
        if (address(swapper_) == address(0)) revert ConfigurationAddressZero();
        if (address(sdToken_) == address(0)) revert ConfigurationAddressZero();

        swapper = swapper_;
        sdToken = sdToken_;

        dToken = IPoolV3(sdToken_.stakingToken());
        gear = IERC20(sdToken_.rewardsToken());
    }

    function initialize(string memory strategyName_, uint256 assetGroupId_) external initializer {
        __Strategy_init(strategyName_, assetGroupId_);

        address[] memory tokens = assets();

        if (tokens.length != 1 || tokens[0] != dToken.underlyingToken()) {
            revert InvalidAssetGroup(assetGroupId());
        }

        _lastSupplyRate = dToken.supplyRate();
    }

    function assetRatio() external pure override returns (uint256[] memory) {
        uint256[] memory _assetRatio = new uint256[](1);
        _assetRatio[0] = 1;
        return _assetRatio;
    }

    function getUnderlyingAssetAmounts() external view returns (uint256[] memory amounts) {
        amounts = new uint256[](1);
        amounts[0] = _getdTokenValue(sdToken.balanceOf(address(this)));
    }

    /**
     * @notice Nothing to swap as it's only one asset.
     */
    function _swapAssets(address[] memory, uint256[] memory, SwapInfo[] calldata) internal override {}

    function _compound(address[] calldata tokens, SwapInfo[] calldata swapInfo, uint256[] calldata slippages)
        internal
        override
        returns (int256 compoundedYieldPercentage)
    {
        if (swapInfo.length > 0) {
            uint256 gearBalance = _getGearboxReward();

            if (gearBalance > 0) {
                gear.safeTransfer(address(swapper), gearBalance);
                address[] memory tokensIn = new address[](1);
                tokensIn[0] = address(gear);
                uint256 swappedAmount = swapper.swap(tokensIn, swapInfo, tokens, address(this))[0];

                if (swappedAmount > 0) {
                    uint256 sdTokenBalanceBefore = sdToken.balanceOf(address(this));
                    _depositToProtocolInternal(IERC20(tokens[0]), swappedAmount, slippages[1]);

                    compoundedYieldPercentage =
                        _calculateYieldPercentage(sdTokenBalanceBefore, sdToken.balanceOf(address(this)));
                }
            }
        }
    }

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        uint256 supplyRateCurrent = dToken.supplyRate();

        baseYieldPercentage = _calculateYieldPercentage(_lastSupplyRate, supplyRateCurrent);
        _lastSupplyRate = supplyRateCurrent;
    }

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata slippages)
        internal
        override
    {
        uint256 slippage;
        if (slippages[0] == 0) {
            slippage = slippages[4];
        } else if (slippages[0] == 2) {
            slippage = slippages[2];
        } else {
            revert GearboxV3DepositSlippagesFailed();
        }
        _depositToProtocolInternal(IERC20(tokens[0]), amounts[0], slippage);
    }

    /**
     * @notice Withdraw lp tokens from the GearboxV3 market
     */
    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata slippages) internal override {
        uint256 slippage;
        if (slippages[0] == 1) {
            slippage = slippages[4];
        } else if (slippages[0] == 2) {
            slippage = slippages[2];
        } else if (slippages[0] == 3) {
            slippage = slippages[1];
        } else if (slippages[0] == 0 && _isViewExecution()) {
            slippage = slippages[4];
        } else {
            revert GearboxV3RedeemalSlippagesFailed();
        }

        if (ssts == 0) {
            return;
        }

        uint256 dTokenWithdrawAmount = (sdToken.balanceOf(address(this)) * ssts) / totalSupply();

        _redeemFromProtocolInternal(dTokenWithdrawAmount, slippage);
    }

    function _emergencyWithdrawImpl(uint256[] calldata slippages, address recipient) internal override {
        if (slippages[0] != 3) {
            revert GearboxV3RedeemalSlippagesFailed();
        }

        uint256 sdTokenBalance = sdToken.balanceOf(address(this));

        _redeemFromProtocolInternal(sdTokenBalance, slippages[1]);
        address[] memory tokens = assets();
        IERC20(tokens[0]).safeTransfer(recipient, IERC20(tokens[0]).balanceOf(address(this)));
    }

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256 usdValue)
    {
        uint256 sdTokenBalance = sdToken.balanceOf(address(this));
        if (sdTokenBalance > 0) {
            uint256 tokenValue = _getdTokenValue(sdTokenBalance);

            address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupId());
            usdValue = priceFeedManager.assetToUsdCustomPrice(assetGroup[0], tokenValue, exchangeRates[0]);
        }
    }

    /**
     * @dev Get value of the desired dToken amount in the asset token amount
     * @param dTokenAmount dToken amount
     * @return tokenAmount value of `dTokenAmount` in asset tokens
     */
    function _getdTokenValue(uint256 dTokenAmount) private view returns (uint256) {
        if (dTokenAmount == 0) {
            return 0;
        }

        return dToken.previewRedeem(dTokenAmount);
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public override {
        unchecked {
            if (_isViewExecution()) {
                uint256[] memory beforeDepositCheckSlippageAmounts = new uint256[](1);
                beforeDepositCheckSlippageAmounts[0] = amounts[0];
                emit BeforeDepositCheckSlippages(beforeDepositCheckSlippageAmounts);
                return;
            }

            if (slippages[0] > 2) {
                revert GearboxV3DepositCheckFailed();
            }

            if (!PackedRange.isWithinRange(slippages[1], amounts[0])) {
                revert GearboxV3DepositCheckFailed();
            }
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
            revert GearboxV3RedeemalCheckFailed();
        }

        if (!PackedRange.isWithinRange(slippage, ssts)) {
            revert GearboxV3RedeemalCheckFailed();
        }
    }

    function _depositToProtocolInternal(IERC20 token, uint256 amount, uint256 slippage) internal {
        if (amount > 0) {
            _resetAndApprove(token, address(dToken), amount);

            uint256 shares = dToken.deposit(amount, address(this));

            if (shares < slippage) {
                revert GearboxV3DepositFailed();
            }

            _resetAndApprove(dToken, address(sdToken), shares);
            sdToken.deposit(shares);
        }
    }

    function _redeemFromProtocolInternal(uint256 amount, uint256 slippage) internal {
        if (amount > 0) {
            sdToken.withdraw(amount);
            uint256 shares = dToken.withdraw(amount, address(this), address(this));

            if (shares < slippage) {
                revert GearboxV3RedeemalFailed();
            }
        }
    }

    function _getProtocolRewardsInternal() internal virtual override returns (address[] memory, uint256[] memory) {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = address(gear);
        amounts[0] = _getGearboxReward();

        return (tokens, amounts);
    }

    function _getGearboxReward() internal returns (uint256) {
        sdToken.claim();

        return gear.balanceOf(address(this));
    }
}
