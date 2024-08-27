// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./GearboxV3Strategy.sol";
import "./helpers/SwapAdapter.sol";

// One asset
// One reward: GEAR
// slippages needed for swapping only
// Description:
// This is a Gearbox V3 "swap" strategy, whereby the asset group token is
// different from the Gearbox V3 pool token.
// The asset group token is first swapped to the Gearbox V3 pool token, which
// is then deposited into the Gearbox V3 pool.
// We receive "diesel" tokens (dTokens) following deposit. These tokens accrue
// value automatically.
//
// The dTokens are then deposited into a Gearbox farming pool to receive extra
// rewards, in the form of GEAR. this process mints sdTokens, 1:1 with dTokens.
// Therefore, we consider dTokens and sdTokens to be equivalent in value.
//
// Liquidity availability on redeem is subject to usual supply/borrow rules.
contract GearboxV3SwapStrategy is GearboxV3Strategy, SwapAdapter {
    using SafeERC20 for IERC20;

    // @notice underlying pool token
    address public underlying;

    IUsdPriceFeedManager public immutable priceFeedManager;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        IUsdPriceFeedManager priceFeedManager_
    ) GearboxV3Strategy(assetGroupRegistry_, accessControl_, swapper_) {
        priceFeedManager = priceFeedManager_;
    }

    function initialize(string memory strategyName_, uint256 assetGroupId_, IFarmingPool sdToken_)
        external
        override
        initializer
    {
        __Strategy_init(strategyName_, assetGroupId_);

        sdToken = sdToken_;
        dToken = IPoolV3(sdToken_.stakingToken());
        gear = IERC20(sdToken_.rewardsToken());
        underlying = dToken.underlyingToken();

        address[] memory tokens = assets();

        if (tokens.length != 1) {
            revert InvalidAssetGroup(assetGroupId());
        }

        _mantissa = 10 ** (dToken.decimals() * 2);
        _lastExchangeRate = (_mantissa * dToken.expectedLiquidity()) / dToken.totalSupply();
    }

    function _compound(address[] calldata, SwapInfo[] calldata swapInfo, uint256[] calldata slippages)
        internal
        override
        returns (int256 compoundedYieldPercentage)
    {
        address[] memory tokens = new address[](1);
        tokens[0] = address(underlying);
        compoundedYieldPercentage = _compoundInternal(tokens, swapInfo, slippages);
    }

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata slippages)
        internal
        override
    {
        amounts[0] = _swap(swapper, tokens[0], underlying, amounts[0], slippages, 0);
        if (amounts[0] > 0) {
            _depositToProtocolInternal(IERC20(underlying), amounts[0]);
        }
    }

    function _redeemFromProtocol(address[] calldata tokens, uint256 ssts, uint256[] calldata slippages)
        internal
        override
    {
        super._redeemFromProtocol(tokens, ssts, slippages);
        uint256 balance = IERC20(underlying).balanceOf(address(this));
        if (balance > 0) {
            _swap(swapper, underlying, tokens[0], balance, slippages, 0);
        }
    }

    function _emergencyWithdrawImpl(uint256[] calldata, address recipient) internal override {
        uint256 sdTokenBalance = sdToken.balanceOf(address(this));

        _redeemFromProtocolInternal(sdTokenBalance);
        IERC20(underlying).safeTransfer(recipient, IERC20(underlying).balanceOf(address(this)));
    }

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager_)
        internal
        view
        override
        returns (uint256 usdValue)
    {
        uint256 sdTokenBalance = sdToken.balanceOf(address(this));
        if (sdTokenBalance > 0) {
            uint256 tokenValue = _getdTokenValue(sdTokenBalance);

            usdValue = priceFeedManager_.assetToUsdCustomPrice(underlying, tokenValue, exchangeRates[0]);
        }
    }

    function getUnderlyingAssetAmounts() external view override returns (uint256[] memory amounts) {
        amounts = new uint256[](1);
        address underlyingAsset = assets()[0];
        uint256 dTokenValue = _getdTokenValue(sdToken.balanceOf(address(this)));
        uint256 usdValue = priceFeedManager.assetToUsd(address(underlying), dTokenValue);
        amounts[0] = priceFeedManager.usdToAsset(underlyingAsset, usdValue);
    }
}
