// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/strategies/AaveV2Strategy.sol";
import "../../src/strategies/YearnV2Strategy.sol";
import "../helper/JsonHelper.sol";

string constant AAVE_V2_KEY = "aave-v2";
string constant YEARN_V2_KEY = "yearn-v2";

contract StrategiesInitial {
    function assetGroups(string memory) public view virtual returns (uint256) {}
    function constantsJson() internal view virtual returns (JsonReader) {}
    function contractsJson() internal view virtual returns (JsonWriter) {}

    // strategy key => asset group id => strategy address
    mapping(string => mapping(uint256 => address)) public strategies;

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
        // create implementation contract
        ILendingPoolAddressesProvider provider = ILendingPoolAddressesProvider(
            constantsJson().getAddress(string.concat(".strategies.", AAVE_V2_KEY, ".lendingPoolAddressesProvider"))
        );

        AaveV2Strategy implementation = new AaveV2Strategy(
            assetGroupRegistry,
            accessControl,
            provider
        );

        contractsJson().addVariantStrategyImplementation(AAVE_V2_KEY, address(implementation));

        // create variant proxies
        string[] memory variants = new string[](3);
        variants[0] = "dai";
        variants[1] = "usdc";
        variants[2] = "usdt";

        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = _getVariantName(AAVE_V2_KEY, variants[i]);

            address variant = _newProxy(address(implementation), proxyAdmin);
            uint256 assetGroupId = assetGroups(variants[i]);
            AaveV2Strategy(variant).initialize(variantName, assetGroupId);
            _registerStrategyVariant(AAVE_V2_KEY, variants[i], variant, assetGroupId, strategyRegistry);
        }
    }

    function deployYearnV2(
        ISpoolAccessControl accessControl,
        IAssetGroupRegistry assetGroupRegistry,
        address proxyAdmin,
        IStrategyRegistry strategyRegistry
    ) public {
        // create implementation contract
        YearnV2Strategy implementation = new YearnV2Strategy(
            assetGroupRegistry,
            accessControl
        );

        contractsJson().addVariantStrategyImplementation(YEARN_V2_KEY, address(implementation));

        // create variant proxies
        string[] memory variants = new string[](3);
        variants[0] = "dai";
        variants[1] = "usdc";
        variants[2] = "usdt";

        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = _getVariantName(YEARN_V2_KEY, variants[i]);

            IYearnTokenVault yTokenVault = IYearnTokenVault(
                constantsJson().getAddress(string.concat(".strategies.", YEARN_V2_KEY, ".", variants[i], ".tokenVault"))
            );

            address variant = _newProxy(address(implementation), proxyAdmin);
            uint256 assetGroupId = assetGroups(variants[i]);
            YearnV2Strategy(variant).initialize(variantName, assetGroupId, yTokenVault);
            _registerStrategyVariant(YEARN_V2_KEY, variants[i], variant, assetGroupId, strategyRegistry);
        }
    }

    function _newProxy(address implementation, address proxyAdmin) private returns (address) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), proxyAdmin, "");

        return address(proxy);
    }

    function _registerStrategyVariant(
        string memory strategyKey,
        string memory variantKey,
        address variant,
        uint256 assetGroupId,
        IStrategyRegistry strategyRegistry
    ) private {
        int256 apy = constantsJson().getInt256(string.concat(".strategies.", strategyKey, ".", variantKey, ".apy"));
        string memory variantName = _getVariantName(strategyKey, variantKey);

        strategyRegistry.registerStrategy(variant, apy);

        strategies[strategyKey][assetGroupId] = variant;
        contractsJson().addVariantStrategyVariant(strategyKey, variantName, address(variant));
    }

    function _getVariantName(string memory strategyKey, string memory variantKey)
        private
        pure
        returns (string memory)
    {
        return string.concat(strategyKey, "-", variantKey);
    }
}
