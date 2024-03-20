// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/utils/math/SafeCast.sol";
import "../../src/libraries/uint16a16Lib.sol";
import "../../src/strategies/arbitrum/AaveV3Strategy.sol";
import "../../src/strategies/arbitrum/CompoundV3Strategy.sol";
import "../../src/strategies/arbitrum/GammaCamelotStrategy.sol";
import "../helper/JsonHelper.sol";
import "./AssetsInitial.s.sol";

string constant AAVE_V3_AUSDC_KEY = "aave-v3-ausdc";
string constant AAVE_V3_AUSDCE_KEY = "aave-v3-ausdce";
string constant COMPOUND_V3_CUSDC_KEY = "compound-v3-cusdc";
string constant COMPOUND_V3_CUSDCE_KEY = "compound-v3-cusdce";
string constant GAMMA_CAMELOT_KEY = "gamma-camelot";

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

        deployAaveV3(contracts);

        deployCompoundV3(contracts);

        deployGammaCamelot(contracts);
    }

    function deployAaveV3(StandardContracts memory contracts) public {
        // create implementation contract
        IPoolAddressesProvider provider = IPoolAddressesProvider(
            constantsJson().getAddress(string.concat(".strategies.aave-v3.poolAddressesProvider"))
        );

        AaveV3Strategy implementation = new AaveV3Strategy(
            contracts.assetGroupRegistry,
            contracts.accessControl,
            contracts.swapper,
            provider
        );

        // create different strategies for USDC asset group
        string[] memory strategies_ = new string[](2);
        strategies_[0] = AAVE_V3_AUSDC_KEY;
        strategies_[1] = AAVE_V3_AUSDCE_KEY;

        uint256 assetGroupId = assetGroups(USDC_KEY);

        for (uint256 i; i < strategies_.length; ++i) {
            contractsJson().addVariantStrategyImplementation(strategies_[i], address(implementation));
            string memory variantName = _getVariantName(strategies_[i], USDC_KEY);

            IAToken aToken =
                IAToken(constantsJson().getAddress(string.concat(".strategies.", strategies_[i], ".", USDC_KEY, ".aToken")));

            address variant = _newProxy(address(implementation), contracts.proxyAdmin);
            AaveV3Strategy(variant).initialize(variantName, assetGroupId, aToken);
            _registerStrategyVariant(strategies_[i], USDC_KEY, variant, assetGroupId, contracts.strategyRegistry);
        }
    }

    function deployCompoundV3(StandardContracts memory contracts) public {
        // create implementation contract
        IERC20 comp = IERC20(constantsJson().getAddress(string.concat(".tokens.comp")));
        IRewards rewards = IRewards(constantsJson().getAddress(string.concat(".strategies.compound-v3.rewards")));

        CompoundV3Strategy implementation = new CompoundV3Strategy(
            contracts.assetGroupRegistry,
            contracts.accessControl,
            contracts.swapper,
            comp,
            rewards
        );

        // create different strategies for USDC asset group
        string[] memory strategies_ = new string[](2);
        strategies_[0] = COMPOUND_V3_CUSDC_KEY;
        strategies_[1] = COMPOUND_V3_CUSDCE_KEY;

        uint256 assetGroupId = assetGroups(USDC_KEY);

        for (uint256 i; i < strategies_.length; ++i) {
            contractsJson().addVariantStrategyImplementation(strategies_[i], address(implementation));
            string memory variantName = _getVariantName(strategies_[i], USDC_KEY);

            IComet cToken = IComet(constantsJson().getAddress(string.concat(".strategies.", strategies_[i], ".", USDC_KEY,  ".cToken")));

            address variant = _newProxy(address(implementation), contracts.proxyAdmin);
            CompoundV3Strategy(variant).initialize(variantName, assetGroupId, cToken);
            _registerStrategyVariant(strategies_[i], USDC_KEY, variant, assetGroupId, contracts.strategyRegistry);
        }
    }

    function deployGammaCamelot(StandardContracts memory contracts) public {
        GammaCamelotStrategy implementation = new GammaCamelotStrategy(
            contracts.assetGroupRegistry,
            contracts.accessControl,
            contracts.swapper
        );

        contractsJson().addVariantStrategyImplementation(GAMMA_CAMELOT_KEY, address(implementation));

        // create variant proxies
        string[] memory variants = new string[](1);
        variants[0] = WETH_USDC_KEY;

        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = _getVariantName(GAMMA_CAMELOT_KEY, variants[i]);

            IHypervisor hypervisor = IHypervisor(
                constantsJson().getAddress(
                    string.concat(".strategies.", GAMMA_CAMELOT_KEY, ".hypervisor")
                )
            );

            INitroPool nitroPool = INitroPool(
                constantsJson().getAddress(
                    string.concat(".strategies.", GAMMA_CAMELOT_KEY, ".nitroPool")
                )
            );

            address variant = _newProxy(address(implementation), contracts.proxyAdmin);
            uint256 assetGroupId = assetGroups(variants[i]);
            console.log("assetGroupId: %s", assetGroupId);
            GammaCamelotStrategy(variant).initialize(variantName, assetGroupId, hypervisor, nitroPool);
            console.log("register strategy..");
            _registerStrategyVariant(GAMMA_CAMELOT_KEY, variants[i], variant, assetGroupId, contracts.strategyRegistry);
        }
    }

    function _newProxy(address implementation, address proxyAdmin) private returns (address) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), proxyAdmin, "");

        return address(proxy);
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

    function _getVariantName(string memory strategyKey, string memory variantKey)
        private
        pure
        returns (string memory)
    {
        return string.concat(strategyKey, "-", variantKey);
    }

    function test_mock_StrategiesInitial() external pure {}
}
