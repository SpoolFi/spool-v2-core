// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Vm.sol";
import "../../src/interfaces/IAssetGroupRegistry.sol";
import "../../src/interfaces/ISmartVault.sol";
import "../../src/interfaces/ISmartVaultManager.sol";
import "../../src/interfaces/IStrategy.sol";
import "../../src/interfaces/IUsdPriceFeedManager.sol";
import "../../src/libraries/SpoolUtils.sol";

library VaultValueHelpers {
    function getVaultTotalUsdValue(
        Vm vm,
        ISmartVault smartVault,
        IAssetGroupRegistry assetGroupRegistry,
        IUsdPriceFeedManager priceFeedManager,
        ISmartVaultManager smartVaultManager
    ) public returns (uint256 totalUsdValue) {
        uint256 assetGroupId = smartVault.assetGroupId();
        address[] memory assets = assetGroupRegistry.listAssetGroup(assetGroupId);
        uint256[] memory exchangeRates = SpoolUtils.getExchangeRates(assets, priceFeedManager);

        address[] memory strategies = smartVaultManager.strategies(address(smartVault));

        for (uint256 i; i < strategies.length; ++i) {
            IStrategy strategy = IStrategy(strategies[i]);

            uint256 totalSupply = strategy.totalSupply();
            if (totalSupply == 0) {
                continue;
            }

            vm.startPrank(address(smartVaultManager));
            totalUsdValue += strategy.getUsdWorth(exchangeRates, priceFeedManager)
                * strategy.balanceOf(address(smartVault)) / totalSupply;
            vm.stopPrank();
        }
    }

    function getVaultStrategyUsdValue(
        Vm vm,
        ISmartVault smartVault,
        IAssetGroupRegistry assetGroupRegistry,
        IUsdPriceFeedManager priceFeedManager,
        ISmartVaultManager smartVaultManager,
        IStrategy strategy
    ) public returns (uint256 vaultStrategyUsdValue) {
        uint256 assetGroupId = smartVault.assetGroupId();
        address[] memory assets = assetGroupRegistry.listAssetGroup(assetGroupId);
        uint256[] memory exchangeRates = SpoolUtils.getExchangeRates(assets, priceFeedManager);

        uint256 totalSupply = strategy.totalSupply();
        if (totalSupply == 0) {
            return vaultStrategyUsdValue;
        }

        vm.startPrank(address(smartVaultManager));
        vaultStrategyUsdValue = strategy.getUsdWorth(exchangeRates, priceFeedManager)
            * strategy.balanceOf(address(smartVault)) / totalSupply;
        vm.stopPrank();
    }
}
