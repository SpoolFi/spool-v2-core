//// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../MainnetExtendedSetup.s.sol";
import "../StrategiesInitial.s.sol";
import {GearboxV3AirdropStrategy} from "../../../src/strategies/GearboxV3AirdropStrategy.sol";
import {EthenaAirdropStrategy} from "../../../src/strategies/EthenaAirdropStrategy.sol";

contract DeployForNonAtomicUpgradeP1 is MainnetExtendedSetup {
    // optimizer_runs = 99999

    // will also deploy libs:
    // - AaveGhoStakingStrategyLib
    // - ConvexAlUsdStrategyLib
    // - SmartVaultManagerLib
    // - StrategyRegistryLib

    // after running, add libraries to the foundry.toml

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        _contractsJson.reserializeKeyAddress("strategies");

        redeployAaveV2();
        redeployCompoundV2();
        redeployGearboxV3();
        redeployOEthHolding();
        redeployREthHolding();
        redeploySfrxEthHolding();
        redeployStEthHolding();
        redeployYearnV2();
    }

    function redeployAaveV2() internal {
        ILendingPoolAddressesProvider provider = ILendingPoolAddressesProvider(
            _constantsJson.getAddress(string.concat(".strategies.", AAVE_V2_KEY, ".lendingPoolAddressesProvider"))
        );

        vm.broadcast(_deployerPrivateKey);
        AaveV2Strategy implementation = new AaveV2Strategy(
            assetGroupRegistry,
            spoolAccessControl,
            provider
        );

        _contractsJson.addVariantStrategyImplementation(AAVE_V2_KEY, address(implementation));

        // upgrade strategies.aave-v2:
        // - aave-v2-dai
        // - aave-v2-usdc
        // - aave-v2-usdt
    }

    function redeployCompoundV2() internal {
        IComptroller comptroller =
            IComptroller(_constantsJson.getAddress(string.concat(".strategies.", COMPOUND_V2_KEY, ".comptroller")));

        vm.broadcast(_deployerPrivateKey);
        CompoundV2Strategy implementation = new CompoundV2Strategy(
            assetGroupRegistry,
            spoolAccessControl,
            swapper,
            comptroller
        );

        _contractsJson.addVariantStrategyImplementation(COMPOUND_V2_KEY, address(implementation));

        // upgrade strategies.compound-v2:
        // - compound-v2-dai
        // - compound-v2-usdc
        // - compound-v2-usdt
    }

    function redeployGearboxV3() internal {
        vm.broadcast(_deployerPrivateKey);
        GearboxV3Strategy implementation = new GearboxV3Strategy(
            assetGroupRegistry,
            spoolAccessControl,
            swapper
        );

        _contractsJson.addVariantStrategyImplementation(GEARBOX_V3_KEY, address(implementation));

        // upgrade strategies.gearbox-v3:
        // - gearbox-v3-dai
        // - gearbox-v3-usdc
        // - gearbox-v3-usdt
        // - gearbox-v3-wbtc
    }

    function redeployOEthHolding() internal {
        uint256 assetGroupId = assetGroups(WETH_KEY);
        IOEthToken oEthToken = IOEthToken(_constantsJson.getAddress(string.concat(".tokens.oEth")));
        IVaultCore oEthVault =
            IVaultCore(_constantsJson.getAddress(string.concat(".strategies.", OETH_HOLDING_KEY, ".vault")));
        ICurveEthPool curvePool =
            ICurveEthPool(_constantsJson.getAddress(string.concat(".strategies.", CURVE_OETH_KEY, ".pool")));

        vm.broadcast(_deployerPrivateKey);
        OEthHoldingStrategy implementation = new OEthHoldingStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            assetGroupId,
            oEthToken,
            oEthVault,
            curvePool,
            assets(WETH_KEY)
        );

        _contractsJson.addVariantStrategyImplementation(OETH_HOLDING_KEY, address(implementation));

        // upgrade strategies.oeth-holding:
        // - proxy
    }

    function redeployREthHolding() internal {
        uint256 assetGroupId = assetGroups(WETH_KEY);
        IRocketSwapRouter rocketSwapRouter = IRocketSwapRouter(
            _constantsJson.getAddress(string.concat(".strategies.", RETH_HOLDING_KEY, ".rocketSwapRouter"))
        );

        vm.broadcast(_deployerPrivateKey);
        REthHoldingStrategy implementation = new REthHoldingStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            assetGroupId,
            rocketSwapRouter,
            assets(WETH_KEY)
        );

        _contractsJson.addVariantStrategyImplementation(RETH_HOLDING_KEY, address(implementation));

        // upgrade strategies.reth-holding:
        // - proxy
    }

    function redeploySfrxEthHolding() internal {
        uint256 assetGroupId = assetGroups(WETH_KEY);
        IERC20 frxEthToken = IERC20(_constantsJson.getAddress(string.concat(".tokens.frxEth")));
        ISfrxEthToken sfrxEthToken = ISfrxEthToken(_constantsJson.getAddress(string.concat(".tokens.sfrxEth")));
        IFrxEthMinter frxEthMinter = IFrxEthMinter(
            _constantsJson.getAddress(string.concat(".strategies.", SFRXETH_HOLDING_KEY, ".frxEthMinter"))
        );
        ICurveEthPool curvePool =
            ICurveEthPool(_constantsJson.getAddress(string.concat(".strategies.", CURVE_FRXETH_KEY, ".pool")));

        vm.broadcast(_deployerPrivateKey);
        SfrxEthHoldingStrategy implementation = new SfrxEthHoldingStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            assetGroupId,
            frxEthToken,
            sfrxEthToken,
            frxEthMinter,
            curvePool,
            assets(WETH_KEY)
        );

        _contractsJson.addVariantStrategyImplementation(SFRXETH_HOLDING_KEY, address(implementation));

        // upgrade strategies.sfrxeth-holding:
        // - proxy
    }

    function redeployStEthHolding() internal {
        uint256 assetGroupId = assetGroups(WETH_KEY);
        ILido lido = ILido(_constantsJson.getAddress(string.concat(".strategies.", STETH_HOLDING_KEY, ".lido")));
        ICurveEthPool curvePool =
            ICurveEthPool(_constantsJson.getAddress(string.concat(".strategies.", CURVE_STETH_KEY, ".pool")));

        vm.broadcast(_deployerPrivateKey);
        StEthHoldingStrategy implementation = new StEthHoldingStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            assetGroupId,
            lido,
            curvePool,
            assets(WETH_KEY)
        );

        _contractsJson.addVariantStrategyImplementation(STETH_HOLDING_KEY, address(implementation));

        // upgrade strategies.steth-holding:
        // - proxy
    }

    function redeployYearnV2() internal {
        vm.broadcast(_deployerPrivateKey);
        YearnV2Strategy implementation = new YearnV2Strategy(
            assetGroupRegistry,
            spoolAccessControl
        );

        _contractsJson.addVariantStrategyImplementation(YEARN_V2_KEY, address(implementation));

        // upgrade strategies.yearn-v2:
        // - yearn-v2-dai
        // - yearn-v2-usdc
        // - yearn-v2-usdt
    }
}

contract DeployForNonAtomicUpgradeP2 is MainnetExtendedSetup {
    // optimizer runs: 10000

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        _contractsJson.reserializeKeyAddress("strategies");

        redeployApxEthHolding();
        redeployEthena();
        redeployEthenaAirdrop();
        redeployGearboxV3Airdrop();
        redeployGearboxV3Swap();
        redeployYearnV3WithJuice();
    }

    function redeployApxEthHolding() internal {
        vm.broadcast(_deployerPrivateKey);
        ApxEthHoldingStrategy implementation = new ApxEthHoldingStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            swapper,
            assets(WETH_KEY)
        );

        _contractsJson.addVariantStrategyImplementation(APXETH_HOLDING_KEY, address(implementation));

        // upgrade strategies.apxeth-holding:
        // - proxy
    }

    function redeployEthena() internal {
        IsUSDe sUSDe = IsUSDe(constantsJson().getAddress(string.concat(".strategies.", ETHENA_KEY, ".sUSDe")));
        IERC20Metadata ENAToken =
            IERC20Metadata(constantsJson().getAddress(string.concat(".strategies.", ETHENA_KEY, ".ENA")));

        vm.broadcast(_deployerPrivateKey);
        EthenaStrategy implementation = new EthenaStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            IERC20Metadata(assets(USDE_KEY)),
            sUSDe,
            ENAToken,
            swapper,
            usdPriceFeedManager
        );

        _contractsJson.addVariantStrategyImplementation(ETHENA_KEY, address(implementation));

        // upgrade strategies.ethena:
        // - ethena-usde
    }

    function redeployEthenaAirdrop() internal {
        IsUSDe sUSDe = IsUSDe(constantsJson().getAddress(string.concat(".strategies.", ETHENA_KEY, ".sUSDe")));
        IERC20Metadata ENAToken =
            IERC20Metadata(constantsJson().getAddress(string.concat(".strategies.", ETHENA_KEY, ".ENA")));

        vm.broadcast(_deployerPrivateKey);
        EthenaAirdropStrategy implementation = new EthenaAirdropStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            IERC20Metadata(assets(USDE_KEY)),
            sUSDe,
            ENAToken,
            swapper,
            usdPriceFeedManager
        );

        _contractsJson.addVariantStrategyImplementation(ETHENA_KEY, "airdrop", address(implementation));

        // upgrade strategies.ethena:
        // - ethena-usdc
    }

    function redeployGearboxV3Airdrop() internal {
        vm.broadcast(_deployerPrivateKey);
        GearboxV3AirdropStrategy implementation = new GearboxV3AirdropStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            swapper
        );

        _contractsJson.addVariantStrategyImplementation(GEARBOX_V3_KEY, "airdrop", address(implementation));

        // upgrade strategies.gearbox-v3:
        // - gearbox-v3-weth
    }

    function redeployGearboxV3Swap() internal {
        vm.broadcast(_deployerPrivateKey);
        GearboxV3SwapStrategy implementation = new GearboxV3SwapStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            swapper,
            usdPriceFeedManager
        );

        _contractsJson.addVariantStrategyImplementation(GEARBOX_V3_SWAP_KEY, address(implementation));

        // upgrade strategies.gearbox-v3-swap:
        // - gearbox-v3-swap-crvusd
        // - gearbox-v3-swap-gho
    }

    function redeployYearnV3WithJuice() internal {
        vm.broadcast(_deployerPrivateKey);
        YearnV3StrategyWithJuice implementation = new YearnV3StrategyWithJuice(
            assetGroupRegistry,
            spoolAccessControl
        );

        _contractsJson.addVariantStrategyImplementation(YEARN_V3_JUICED_KEY, address(implementation));

        // upgrade strategies.yearn-v3-juiced:
        // - yearn-v3-juiced-dai
    }
}

contract DeployForNonAtomicUpgradeP3 is MainnetExtendedSetup {
    // optimizer runs: 3000

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        redeploySmartVaultManager();
    }

    function redeploySmartVaultManager() internal {
        vm.broadcast(_deployerPrivateKey);
        SmartVaultManager implementation = new SmartVaultManager(
            spoolAccessControl,
            assetGroupRegistry,
            riskManager,
            depositManager,
            withdrawalManager,
            strategyRegistry,
            masterWallet,
            usdPriceFeedManager,
            address(ghostStrategy)
        );

        _contractsJson.addProxy("SmartVaultManager", address(implementation), address(smartVaultManager));

        // upgrade SmartVaultManager:
        // - proxy
    }
}

contract DeployForNonAtomicUpgradeP4 is MainnetExtendedSetup {
    // optimizer runs: 1500

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        _contractsJson.reserializeKeyAddress("strategies");

        redeployCurve3pool();
        redeployMetamorpho();
    }

    function redeployCurve3pool() internal {
        uint256 assetGroupId = assetGroups(DAI_USDC_USDT_KEY);

        vm.broadcast(_deployerPrivateKey);
        Curve3poolStrategy implementation = new Curve3poolStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            assetGroupId,
            swapper
        );

        _contractsJson.addVariantStrategyImplementation(CURVE_3POOL_KEY, address(implementation));

        // upgrade strategies.curve-3pool:
        // - proxy
    }

    function redeployMetamorpho() internal {
        vm.broadcast(_deployerPrivateKey);
        MetamorphoStrategy implementation = new MetamorphoStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            swapper
        );

        _contractsJson.addVariantStrategyImplementation(METAMORPHO_KEY, address(implementation));

        // upgrade strategies.metamorpho:
        // - metamorpho-bprotocol-flagship-eth
        // - metamorpho-bprotocol-flagship-usdt
        // - metamorpho-gauntlet-dai-core
        // - metamorpho-gauntlet-lrt-core
        // - metamorpho-gauntlet-usdc-core
        // - metamorpho-gauntlet-usdc-prime
        // - metamorpho-gauntlet-usdt-prime
        // - metamorpho-gauntlet-wbtc-core
        // - metamorpho-gauntlet-weth-prime
        // - metamorpho-mev-capital-wbtc
        // - metamorpho-mev-capital-weth
        // - metamorpho-re7-wbtc
        // - metamorpho-re7-weth
        // - metamorpho-relend-usdc
        // - metamorpho-steakhouse-pyusd
        // - metamorpho-steakhouse-usdc
        // - metamorpho-usual-boosted-usdc
    }
}

contract DeployForNonAtomicUpgradeP5 is MainnetExtendedSetup {
    // optimizer runs: 750

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        _contractsJson.reserializeKeyAddress("strategies");

        redeployYearnV3WithGauge();
        redeployStrategyRegistry();
    }

    function redeployYearnV3WithGauge() internal {
        vm.broadcast(_deployerPrivateKey);
        YearnV3StrategyWithGauge implementation = new YearnV3StrategyWithGauge(
            assetGroupRegistry,
            spoolAccessControl,
            swapper
        );

        _contractsJson.addVariantStrategyImplementation(YEARN_V3_GAUGED_KEY, address(implementation));

        // upgrade strategies.yearn-v3-gauged:
        // - yearn-v3-gauged-dai
        // - yearn-v3-gauged-usdc
        // - yearn-v3-gauged-weth
    }

    function redeployStrategyRegistry() internal {
        vm.broadcast(_deployerPrivateKey);
        StrategyRegistry implementation = new StrategyRegistry(
            masterWallet,
            spoolAccessControl,
            usdPriceFeedManager,
            address(ghostStrategy)
        );

        _contractsJson.addProxy("StrategyRegistry", address(implementation), address(strategyRegistry));

        // upgrade StrategyRegistry:
        // - proxy
    }
}

contract DeployForNonAtomicUpgradeP6 is MainnetExtendedSetup {
    // optimizer runs: 350

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        _contractsJson.reserializeKeyAddress("strategies");

        redeployConvex3pool();
        redeployConvexAlUsd();
        redeployConvexStFrxEth();
    }

    function redeployConvex3pool() internal {
        uint256 assetGroupId = assetGroups(DAI_USDC_USDT_KEY);
        IBooster booster =
            IBooster(_constantsJson.getAddress(string.concat(".strategies.", CONVEX_BASE_KEY, ".booster")));

        vm.broadcast(_deployerPrivateKey);
        Convex3poolStrategy implementation = new Convex3poolStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            assetGroupId,
            swapper,
            booster
        );

        _contractsJson.addVariantStrategyImplementation(CONVEX_3POOL_KEY, address(implementation));

        // upgrade strategies.convex-3pool:
        // - proxy
    }

    function redeployConvexAlUsd() internal {
        uint256 assetGroupId = assetGroups(DAI_USDC_USDT_KEY);
        IBooster booster =
            IBooster(_constantsJson.getAddress(string.concat(".strategies.", CONVEX_BASE_KEY, ".booster")));

        vm.broadcast(_deployerPrivateKey);
        ConvexAlusdStrategy implementation = new ConvexAlusdStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            assetGroupId,
            swapper,
            booster,
            1
        );

        _contractsJson.addVariantStrategyImplementation(CONVEX_ALUSD_KEY, address(implementation));

        // upgrade convex-alusd:
        // - proxy
    }

    function redeployConvexStFrxEth() internal {
        uint256 assetGroupId = assetGroups(WETH_KEY);

        vm.broadcast(_deployerPrivateKey);
        ConvexStFrxEthStrategy implementation = new ConvexStFrxEthStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            assetGroupId,
            swapper
        );

        _contractsJson.addVariantStrategyImplementation(CONVEX_STFRXETH_KEY, address(implementation));

        // upgrade strategies.convex-stfrxeth:
        // - proxy
    }
}

contract DeployForNonAtomicUpgradeP7 is MainnetExtendedSetup {
    // optimizer runs: 200

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        _contractsJson.reserializeKeyAddress("strategies");

        deployAaveGhoStaking();
    }

    function deployAaveGhoStaking() internal {
        // deploy implementation
        IERC20Metadata ghoToken = IERC20Metadata(_constantsJson.getAddress(".assets.gho.address"));
        IStakedGho stakedGhoToken = IStakedGho(_constantsJson.getAddress(string.concat(".tokens.stakedGho")));

        vm.broadcast(_deployerPrivateKey);
        AaveGhoStakingStrategy implementation = new AaveGhoStakingStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            ghoToken,
            stakedGhoToken,
            usdPriceFeedManager,
            swapper
        );

        _contractsJson.addVariantStrategyImplementation(AAVE_GHO_STAKING_KEY, address(implementation));

        // deploy variants
        string memory variantName = string.concat(AAVE_GHO_STAKING_KEY, "-", USDC_KEY);
        uint256 assetGroupId = assetGroups(USDC_KEY);

        vm.broadcast(_deployerPrivateKey);
        TransparentUpgradeableProxy variantProxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            ""
        );
        vm.broadcast(_deployerPrivateKey);
        AaveGhoStakingStrategy(address(variantProxy)).initialize(variantName, assetGroupId);

        _contractsJson.addVariantStrategyVariant(AAVE_GHO_STAKING_KEY, variantName, address(variantProxy));

        // register strategies.aave-gho-staking:
        // - aave-gho-staking-usdc
    }
}
