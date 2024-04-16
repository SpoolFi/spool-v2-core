// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/utils/math/SafeCast.sol";
import "../../src/libraries/uint16a16Lib.sol";
import "../../src/strategies/arbitrum/AaveV3Strategy.sol";
import "../../src/strategies/arbitrum/AaveV3SwapStrategy.sol";
import "../../src/strategies/arbitrum/CompoundV3Strategy.sol";
import "../../src/strategies/arbitrum/CompoundV3SwapStrategy.sol";
import "../../src/strategies/arbitrum/GammaCamelotStrategy.sol";
import "../../src/strategies/arbitrum/helpers/GammaCamelotRewards.sol";
import "../helper/JsonHelper.sol";
import "../helper/ArraysHelper.sol";
import "./AssetsInitial.s.sol";

string constant AAVE_V3_KEY = "aave-v3";
string constant AAVE_V3_SWAP_KEY = "aave-v3-swap";
string constant COMPOUND_V3_KEY = "compound-v3";
string constant COMPOUND_V3_SWAP_KEY = "compound-v3-swap";
string constant GAMMA_CAMELOT_KEY = "gamma-camelot";

struct StandardContracts {
    ISpoolAccessControl accessControl;
    IAssetGroupRegistry assetGroupRegistry;
    ISwapper swapper;
    address proxyAdmin;
    IStrategyRegistry strategyRegistry;
}

struct GammaCamelotData {
    IHypervisor hypervisor;
    INitroPool nitroPool;
    bool extraRewards;
    uint256 assetGroupId;
    int256 apy;
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

        deployAaveV3Swap(contracts);

        deployCompoundV3(contracts);

        deployCompoundV3Swap(contracts);

        deployGammaCamelot(contracts);
    }

    function deployAaveV3(StandardContracts memory contracts) public {
        // create implementation contract
        IPoolAddressesProvider provider = IPoolAddressesProvider(
            constantsJson().getAddress(string.concat(".strategies.", AAVE_V3_KEY, ".poolAddressesProvider"))
        );

        IRewardsController incentive = IRewardsController(
            constantsJson().getAddress(string.concat(".strategies.", AAVE_V3_KEY, ".rewardsController"))
        );

        AaveV3Strategy implementation = new AaveV3Strategy(
            contracts.assetGroupRegistry,
            contracts.accessControl,
            contracts.swapper,
            provider,
            incentive
        );

        contractsJson().addVariantStrategyImplementation(AAVE_V3_KEY, address(implementation));

        string memory variantName = _getVariantName(AAVE_V3_KEY, USDC_KEY);

        address variant = _newProxy(address(implementation), contracts.proxyAdmin);
        uint256 assetGroupId = assetGroups(USDC_KEY);

        IAToken aToken =
            IAToken(constantsJson().getAddress(string.concat(".strategies.", AAVE_V3_KEY, ".", USDC_KEY, ".aToken")));
        AaveV3Strategy(variant).initialize(variantName, assetGroupId, aToken);
        _registerStrategyVariant(AAVE_V3_KEY, USDC_KEY, variant, assetGroupId, contracts.strategyRegistry);
    }

    function deployAaveV3Swap(StandardContracts memory contracts) public {
        // create implementation contract
        IPoolAddressesProvider provider = IPoolAddressesProvider(
            constantsJson().getAddress(string.concat(".strategies.", AAVE_V3_KEY, ".poolAddressesProvider"))
        );

        IRewardsController incentive = IRewardsController(
            constantsJson().getAddress(string.concat(".strategies.", AAVE_V3_KEY, ".rewardsController"))
        );

        AaveV3SwapStrategy implementation = new AaveV3SwapStrategy(
            contracts.assetGroupRegistry,
            contracts.accessControl,
            contracts.swapper,
            provider,
            incentive
        );

        contractsJson().addVariantStrategyImplementation(AAVE_V3_SWAP_KEY, address(implementation));

        string memory variantName = _getVariantName(AAVE_V3_SWAP_KEY, USDC_KEY);

        address variant = _newProxy(address(implementation), contracts.proxyAdmin);
        uint256 assetGroupId = assetGroups(USDC_KEY);

        IAToken aToken = IAToken(
            constantsJson().getAddress(string.concat(".strategies.", AAVE_V3_SWAP_KEY, ".", USDC_KEY, ".aToken"))
        );
        AaveV3SwapStrategy(variant).initialize(variantName, assetGroupId, aToken);
        _registerStrategyVariant(AAVE_V3_SWAP_KEY, USDC_KEY, variant, assetGroupId, contracts.strategyRegistry);
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

        contractsJson().addVariantStrategyImplementation(COMPOUND_V3_KEY, address(implementation));

        string memory variantName = _getVariantName(COMPOUND_V3_KEY, USDC_KEY);

        IComet cToken =
            IComet(constantsJson().getAddress(string.concat(".strategies.", COMPOUND_V3_KEY, ".", USDC_KEY, ".cToken")));

        address variant = _newProxy(address(implementation), contracts.proxyAdmin);
        uint256 assetGroupId = assetGroups(USDC_KEY);
        CompoundV3Strategy(variant).initialize(variantName, assetGroupId, cToken);
        _registerStrategyVariant(COMPOUND_V3_KEY, USDC_KEY, variant, assetGroupId, contracts.strategyRegistry);
    }

    function deployCompoundV3Swap(StandardContracts memory contracts) public {
        // create implementation contract
        IERC20 comp = IERC20(constantsJson().getAddress(string.concat(".tokens.comp")));
        IRewards rewards = IRewards(constantsJson().getAddress(string.concat(".strategies.compound-v3.rewards")));

        CompoundV3SwapStrategy implementation = new CompoundV3SwapStrategy(
            contracts.assetGroupRegistry,
            contracts.accessControl,
            contracts.swapper,
            comp,
            rewards
        );

        contractsJson().addVariantStrategyImplementation(COMPOUND_V3_SWAP_KEY, address(implementation));

        string memory variantName = _getVariantName(COMPOUND_V3_SWAP_KEY, USDC_KEY);

        IComet cToken = IComet(
            constantsJson().getAddress(string.concat(".strategies.", COMPOUND_V3_SWAP_KEY, ".", USDC_KEY, ".cToken"))
        );

        address variant = _newProxy(address(implementation), contracts.proxyAdmin);
        uint256 assetGroupId = assetGroups(USDC_KEY);
        CompoundV3SwapStrategy(variant).initialize(variantName, assetGroupId, cToken);
        _registerStrategyVariant(COMPOUND_V3_SWAP_KEY, USDC_KEY, variant, assetGroupId, contracts.strategyRegistry);
    }

    function deployGammaCamelot(StandardContracts memory contracts) public {
        _deployGammaCamelot(contracts, ArraysHelper.toArray(WETH_KEY, USDC_KEY, "narrow"));
    }

    function _deployGammaCamelot(StandardContracts memory contracts, string[] memory poolKeySplit) private {
        // get data
        string memory key = _getVariantName(poolKeySplit);
        string memory variantName = _getVariantName(GAMMA_CAMELOT_KEY, key);
        GammaCamelotData memory data = _getGammaCamelotData(poolKeySplit);

        // create rewards proxy
        address rewards_implementation = address(new GammaCamelotRewards(contracts.accessControl));
        GammaCamelotRewards rewards = GammaCamelotRewards(_newProxy(rewards_implementation, contracts.proxyAdmin));
        // add rewards to json
        string memory rewardsKey = string.concat(GAMMA_CAMELOT_KEY, "-rewards");
        contractsJson().addVariantStrategyHelpersImplementation(rewardsKey, address(rewards_implementation));
        contractsJson().addVariantStrategyHelpersVariant(rewardsKey, key, address(rewards));

        GammaCamelotStrategy implementation = new GammaCamelotStrategy(
            contracts.assetGroupRegistry,
            contracts.accessControl,
            contracts.swapper,
            rewards
        );

        // initialize
        address variant = _newProxy(address(implementation), contracts.proxyAdmin);
        rewards.initialize(data.hypervisor, data.nitroPool, IStrategy(variant), data.extraRewards);
        GammaCamelotStrategy(variant).initialize(variantName, data.assetGroupId, data.hypervisor, data.nitroPool);

        // add to json file and register
        contractsJson().addVariantStrategyImplementation(GAMMA_CAMELOT_KEY, address(implementation));
        _registerStrategyVariant(
            GAMMA_CAMELOT_KEY, key, variant, data.assetGroupId, data.apy, contracts.strategyRegistry
        );
    }

    function _getGammaCamelotData(string[] memory poolKeySplit) private view returns (GammaCamelotData memory data) {
        string memory poolKey = _getVariantName(poolKeySplit[0], poolKeySplit[1]);
        string memory rangeKey = poolKeySplit[2];

        data.hypervisor = IHypervisor(
            constantsJson().getAddress(string.concat(".strategies.", GAMMA_CAMELOT_KEY, ".", poolKey, ".hypervisor"))
        );

        data.nitroPool = INitroPool(
            constantsJson().getAddress(string.concat(".strategies.", GAMMA_CAMELOT_KEY, ".", poolKey, ".nitroPool"))
        );

        data.extraRewards = constantsJson().getBool(
            string.concat(".strategies.", GAMMA_CAMELOT_KEY, ".", poolKey, ".", rangeKey, ".extraRewards")
        );

        data.apy = constantsJson().getInt256(
            string.concat(".strategies.", GAMMA_CAMELOT_KEY, ".", poolKey, ".", rangeKey, ".apy")
        );
        data.assetGroupId = assetGroups(poolKey);
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

    function _registerStrategyVariant(
        string memory strategyKey,
        string memory variantKey,
        address variant,
        uint256 assetGroupId,
        int256 apy,
        IStrategyRegistry strategyRegistry
    ) private {
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

    function _getVariantName(string[] memory assetNames) private pure returns (string memory key) {
        key = assetNames[0];
        for (uint256 i = 1; i < assetNames.length; ++i) {
            key = string.concat(key, "-", assetNames[i]);
        }
    }

    function test_mock_StrategiesInitial() external pure {}
}
