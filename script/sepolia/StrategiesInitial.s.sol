// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/utils/math/SafeCast.sol";
import "../../src/libraries/uint16a16Lib.sol";
import "../../src/strategies/mocks/MockProtocolStrategy.sol";
import "../helper/JsonHelper.sol";
import "./AssetsInitial.s.sol";

string constant MOCK_KEY = "mock2";

struct StandardContracts {
    ISpoolAccessControl accessControl;
    IAssetGroupRegistry assetGroupRegistry;
    ISwapper swapper;
    address proxyAdmin;
    IStrategyRegistry strategyRegistry;
}

contract StrategiesInitial {
    using uint16a16Lib for uint16a16;

    function assets(string memory) public view virtual returns (address) {}
    function assetGroups(string memory) public view virtual returns (uint256) {}
    function constantsJson() internal view virtual returns (JsonReader) {}
    function contractsJson() internal view virtual returns (JsonReadWriter) {}

    // strategy key => asset group id => strategy address
    mapping(string => mapping(uint256 => address)) public strategies;
    // strategy address => strategy key
    mapping(address => string) public addressToStrategyKey;

    function deployStrategies(
        ISpoolAccessControl accessControl,
        IAssetGroupRegistry assetGroupRegistry,
        ISwapper swapper,
        address proxyAdmin,
        IStrategyRegistry strategyRegistry
    ) public {
        StandardContracts memory contracts = StandardContracts({
            accessControl: accessControl,
            assetGroupRegistry: assetGroupRegistry,
            swapper: swapper,
            proxyAdmin: proxyAdmin,
            strategyRegistry: strategyRegistry
        });

        deployMock(contracts);
    }

    function _deployMockBeacon(StandardContracts memory contracts) internal returns (UpgradeableBeacon beacon) {
        // Deploy beacon proxy. upgrading this will upgrade for all strategies.
        MockProtocolStrategy implementation = new MockProtocolStrategy(
            contracts.assetGroupRegistry,
            contracts.accessControl
        );

        beacon = _newUpgradeableBeacon(address(implementation), contracts.proxyAdmin);

        contractsJson().addVariantStrategyBeacon(MOCK_KEY, address(beacon));
    }

    function deployClientMock(StandardContracts memory contracts, string memory name) public {
        UpgradeableBeacon beacon = UpgradeableBeacon(contractsJson().getAddress(".strategies.mock2.beacon"));
        // create variant proxies
        string[] memory variants = new string[](3);
        variants[0] = DAI_KEY;
        variants[1] = USDC_KEY;
        variants[2] = USDT_KEY;

        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = _getVariantName(name, variants[i]);

            MockProtocol protocol = MockProtocol(
                constantsJson().getAddress(string.concat(".protocols.", MOCK_KEY, ".", variants[i], ".address"))
            );

            address variant = _newBeaconProxy(address(beacon));
            uint256 assetGroupId = assetGroups(variants[i]);
            MockProtocolStrategy(variant).initialize(variantName, assetGroupId, protocol);
            _registerClientStrategyVariant(name, variants[i], variant, assetGroupId, contracts.strategyRegistry);
        }
    }

    function deployMock(StandardContracts memory contracts) public {
        // Deploy beacon proxy
        UpgradeableBeacon beacon = _deployMockBeacon(contracts);

        // create variant proxies
        string[] memory variants = new string[](3);
        variants[0] = DAI_KEY;
        variants[1] = USDC_KEY;
        variants[2] = USDT_KEY;

        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = _getVariantName(MOCK_KEY, variants[i]);

            MockProtocol protocol = MockProtocol(
                constantsJson().getAddress(string.concat(".strategies.", MOCK_KEY, ".", variants[i], ".address"))
            );

            address variant = _newBeaconProxy(address(beacon));
            uint256 assetGroupId = assetGroups(variants[i]);
            MockProtocolStrategy(variant).initialize(variantName, assetGroupId, protocol);
            _registerStrategyVariant(MOCK_KEY, variants[i], variant, assetGroupId, contracts.strategyRegistry);
        }
    }

    function _newProxy(address implementation, address proxyAdmin) private returns (address) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), proxyAdmin, "");

        return address(proxy);
    }

    function _newBeaconProxy(address upgradableBeacon) internal returns (address) {
        BeaconProxy proxy = new BeaconProxy(
            address(upgradableBeacon),
            ""
        );

        return address(proxy);
    }

    function _newUpgradeableBeacon(address implementation, address proxyAdmin) internal returns (UpgradeableBeacon) {
        UpgradeableBeacon beacon = new UpgradeableBeacon(
            address(implementation)
        );
        beacon.transferOwnership(proxyAdmin);
        return beacon;
    }

    function _registerStrategy(
        string memory strategyKey,
        address implementation,
        address proxy,
        uint256 assetGroupId,
        IStrategyRegistry strategyRegistry
    ) private {
        int256 apy = constantsJson().getInt256(string.concat(".strategies.", strategyKey, ".apy"));

        strategyRegistry.registerStrategy(proxy, apy);

        strategies[strategyKey][assetGroupId] = proxy;
        addressToStrategyKey[proxy] = strategyKey;
        contractsJson().addProxyStrategy(strategyKey, implementation, proxy);
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
        addressToStrategyKey[variant] = strategyKey;
        contractsJson().addVariantStrategyVariant(strategyKey, variantName, variant);
    }

    function _registerClientStrategyVariant(
        string memory strategyKey,
        string memory variantKey,
        address variant,
        uint256 assetGroupId,
        IStrategyRegistry strategyRegistry
    ) private {
        int256 apy = constantsJson().getInt256(string.concat(".strategies.", MOCK_KEY, ".", variantKey, ".apy"));
        string memory variantName = _getVariantName(strategyKey, variantKey);

        strategyRegistry.registerStrategy(variant, apy);

        strategies[strategyKey][assetGroupId] = variant;
        addressToStrategyKey[variant] = strategyKey;
        contractsJson().addVariantStrategyVariant(strategyKey, variantName, variant);
    }

    function _getVariantName(string memory strategyKey, string memory variantKey)
        private
        pure
        returns (string memory)
    {
        return string.concat(strategyKey, "-", variantKey);
    }

    function test_mock_StrategiesInitial() external pure {}
}
