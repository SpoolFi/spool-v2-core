// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../../src/strategies/Strategy.sol";

abstract contract StrategyHarness is Strategy {
    function exposed_depositToProtocol(
        address[] calldata tokens,
        uint256[] memory amounts,
        uint256[] calldata slippages
    ) external {
        return _depositToProtocol(tokens, amounts, slippages);
    }

    function exposed_redeemFromProtocol(address[] calldata tokens, uint256 ssts, uint256[] calldata slippages)
        external
    {
        return _redeemFromProtocol(tokens, ssts, slippages);
    }

    function exposed_emergencyWithdrawImpl(uint256[] calldata slippages, address recipient) external {
        return _emergencyWithdrawImpl(slippages, recipient);
    }

    function exposed_compound(
        address[] calldata tokens,
        SwapInfo[] calldata compoundSwapInfo,
        uint256[] calldata slippages
    ) external returns (int256 compoundYield) {
        return _compound(tokens, compoundSwapInfo, slippages);
    }

    function exposed_getYieldPercentage(int256 manualYield) external returns (int256) {
        return _getYieldPercentage(manualYield);
    }

    function exposed_swapAssets(address[] memory tokens, uint256[] memory toSwap, SwapInfo[] calldata swapInfo)
        external
    {
        return _swapAssets(tokens, toSwap, swapInfo);
    }

    function exposed_getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        external
        returns (uint256)
    {
        return _getUsdWorth(exchangeRates, priceFeedManager);
    }

    function exposed_mint(uint256 shares) external {
        return _mint(address(this), shares);
    }
}