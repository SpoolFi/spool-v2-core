// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../../src/strategies/Strategy.sol";
import {StrategyNonAtomic} from "../../src/strategies/StrategyNonAtomic.sol";

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

abstract contract StrategyHarnessNonAtomic is StrategyNonAtomic {
    function exposed_getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager_)
        external
        returns (uint256)
    {
        return _getUsdWorth(exchangeRates, priceFeedManager_);
    }

    function exposed_getYieldPercentage(int256 manualYield) external returns (int256) {
        return _getYieldPercentage(manualYield);
    }

    function exposed_initializeDepositToProtocol(
        address[] calldata tokens,
        uint256[] memory assets,
        uint256[] calldata slippages
    ) external returns (bool) {
        return _initializeDepositToProtocol(tokens, assets, slippages);
    }

    function exposed_initializeWithdrawalFromProtocol(
        address[] calldata tokens,
        uint256 shares,
        uint256[] calldata slippages
    ) external returns (bool, bool) {
        return _initializeWithdrawalFromProtocol(tokens, shares, slippages);
    }

    function exposed_continueDepositToProtocol(address[] calldata tokens, bytes calldata continuationData)
        external
        returns (bool, uint256, uint256)
    {
        return _continueDepositToProtocol(tokens, continuationData);
    }

    function exposed_continueWithdrawalFromProtocol(address[] calldata tokens, bytes calldata continuationData)
        external
        returns (bool finished)
    {
        return _continueWithdrawalFromProtocol(tokens, continuationData);
    }

    function exposed_prepareCompoundImpl(address[] calldata tokens, SwapInfo[] calldata compoundSwapInfo)
        external
        returns (bool, uint256[] memory)
    {
        return _prepareCompoundImpl(tokens, compoundSwapInfo);
    }

    function exposed_swapAssets(address[] memory tokens, uint256[] memory toSwap, SwapInfo[] calldata swapInfo)
        external
    {
        return _swapAssets(tokens, toSwap, swapInfo);
    }

    function exposed_emergencyWithdrawImpl(uint256[] calldata slippages, address recipient) external {
        return _emergencyWithdrawImpl(slippages, recipient);
    }

    function exposed_getProtocolRewardsInternal() external returns (address[] memory, uint256[] memory) {
        return _getProtocolRewardsInternal();
    }

    function exposed_mint(uint256 shares) external {
        return _mint(address(this), shares);
    }

    function exposed_burn(uint256 shares) external {
        return _burn(address(this), shares);
    }
}
