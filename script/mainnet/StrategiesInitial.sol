// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/strategies/AaveV2Strategy.sol";
import "../../src/strategies/YearnV2Strategy.sol";
import "../helper/JsonHelper.sol";

contract StrategiesInitial {
    function assetGroups(string memory) public view virtual returns (uint256) {}
    function constantsJson() internal view virtual returns (JsonReader) {}
    function contractsJson() internal view virtual returns (JsonWriter) {}

    mapping(string => address) public strategies;

    function deployStrategies(
        ISpoolAccessControl accessControl,
        IAssetGroupRegistry assetGroupRegistry,
        address proxyAdmin,
        IStrategyRegistry strategyRegistry
    ) public {
        deployAaveV2(accessControl, assetGroupRegistry, proxyAdmin, strategyRegistry);

        deployYearnV2(accessControl, assetGroupRegistry, proxyAdmin, strategyRegistry);
    }

    function deployAaveV2(
        ISpoolAccessControl accessControl,
        IAssetGroupRegistry assetGroupRegistry,
        address proxyAdmin,
        IStrategyRegistry strategyRegistry
    ) public {
        string memory strategyKey = "aave-v2";

        // create implementation contract
        ILendingPoolAddressesProvider provider = ILendingPoolAddressesProvider(
            constantsJson().getAddress(string.concat(".strategies.", strategyKey, ".lendingPoolAddressesProvider"))
        );

        AaveV2Strategy implementation = new AaveV2Strategy(
            assetGroupRegistry,
            accessControl,
            provider
        );

        contractsJson().addVariantStrategyImplementation(strategyKey, address(implementation));

        // create variant proxies
        string[] memory variants = new string[](3);
        variants[0] = "dai";
        variants[1] = "usdc";
        variants[2] = "usdt";

        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = string.concat(strategyKey, "-", variants[i]);

            address variant = _newProxy(address(implementation), proxyAdmin);
            AaveV2Strategy(variant).initialize(variantName, assetGroups(variants[i]));
            _registerStrategyVariant(strategyKey, variants[i], variant, strategyRegistry);
        }
    }

    function deployYearnV2(
        ISpoolAccessControl accessControl,
        IAssetGroupRegistry assetGroupRegistry,
        address proxyAdmin,
        IStrategyRegistry strategyRegistry
    ) public {
        string memory strategyKey = "yearn-v2";

        // create implementation contract
        YearnV2Strategy implementation = new YearnV2Strategy(
            assetGroupRegistry,
            accessControl
        );

        contractsJson().addVariantStrategyImplementation(strategyKey, address(implementation));

        // create variant proxies
        string[] memory variants = new string[](3);
        variants[0] = "dai";
        variants[1] = "usdc";
        variants[2] = "usdt";

        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = _getVariantName(strategyKey, variants[i]);

            IYearnTokenVault yTokenVault = IYearnTokenVault(
                constantsJson().getAddress(string.concat(".strategies.", strategyKey, ".", variants[i], ".tokenVault"))
            );

            address variant = _newProxy(address(implementation), proxyAdmin);
            YearnV2Strategy(variant).initialize(variantName, assetGroups(variants[i]), yTokenVault);
            _registerStrategyVariant(strategyKey, variants[i], variant, strategyRegistry);
        }
    }

    function _newProxy(address implementation, address proxyAdmin) private returns (address) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), proxyAdmin, "");

        return address(proxy);
    }

    function _getVariantName(string memory strategyKey, string memory variantKey)
        private
        pure
        returns (string memory)
    {
        return string.concat(strategyKey, "-", variantKey);
    }

    function _registerStrategyVariant(
        string memory strategyKey,
        string memory variantKey,
        address variant,
        IStrategyRegistry strategyRegistry
    ) private {
        int256 apy = constantsJson().getInt256(string.concat(".strategies.", strategyKey, ".", variantKey, ".apy"));
        string memory variantName = _getVariantName(strategyKey, variantKey);

        strategyRegistry.registerStrategy(variant, apy);

        strategies[variantName] = variant;
        contractsJson().addVariantStrategyVariant(strategyKey, variantName, address(variant));
    }
}
