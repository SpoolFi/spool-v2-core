// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../MainnetExtendedSetup.s.sol";
import "../StrategiesInitial.s.sol";

contract DeployStrategiesDepositedEventP1 is MainnetExtendedSetup {
    // optimizer_runs = 99999

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        // reselialize strategies
        _contractsJson.reserializeKeyAddress("strategies");

        // deploy new implementations for strategies
        redeployAaveV2();
        redeployCompoundV2();
        redeployGearboxV3();
        redeployMorphoAaveV2();
        redeployMorphoCompoundV2();
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

        // upgrade aave-v2:
        // - aave-v2-dai
        // - aave-v2-usdc
        // - aave-v2-usdt
    }

    function redeployCompoundV2() internal {
        IComptroller comptroller =
            IComptroller(_constantsJson.getAddress(string.concat(".strategies.", COMPOUND_V2_KEY, ".comptroller")));

        vm.broadcast(_deployerPrivateKey);
        CompoundV2Strategy implementation = new CompoundV2Strategy(
            assetGroupRegistry, spoolAccessControl, swapper, comptroller
        );

        _contractsJson.addVariantStrategyImplementation(COMPOUND_V2_KEY, address(implementation));

        // upgrade compound-v2:
        // - compound-v2-dai
        // - compound-v2-usdc
        // - compound-v2-usdt
    }

    function redeployGearboxV3() internal {
        vm.broadcast(_deployerPrivateKey);
        GearboxV3Strategy implementation = new GearboxV3Strategy(assetGroupRegistry, spoolAccessControl, swapper);

        _contractsJson.addVariantStrategyImplementation(GEARBOX_V3_KEY, address(implementation));

        // upgrade gearbox-v3:
        // - gearbox-v3-usdc
    }

    function redeployMorphoAaveV2() internal {
        MorphoAaveV2.IMorpho morpho = MorphoAaveV2.IMorpho(
            _constantsJson.getAddress(string.concat(".strategies.", MORPHO_AAVE_V2_KEY, ".morpho"))
        );
        IERC20 poolRewardToken = IERC20(_constantsJson.getAddress(string.concat(".tokens.stkAave")));
        MorphoAaveV2.ILens lens =
            MorphoAaveV2.ILens(_constantsJson.getAddress(string.concat(".strategies.", MORPHO_AAVE_V2_KEY, ".lens")));

        vm.broadcast(_deployerPrivateKey);
        MorphoAaveV2.MorphoAaveV2Strategy implementation = new MorphoAaveV2.MorphoAaveV2Strategy(
            assetGroupRegistry,
            spoolAccessControl,
            morpho,
            poolRewardToken,
            swapper,
            lens
        );

        _contractsJson.addVariantStrategyImplementation(MORPHO_AAVE_V2_KEY, address(implementation));

        // upgrade morpho-aave-v2:
        // - morpho-aave-v2-dai
        // - morpho-aave-v2-usdc
        // - morpho-aave-v2-usdt
    }

    function redeployMorphoCompoundV2() internal {
        MorphoCompoundV2.IMorpho morpho = MorphoCompoundV2.IMorpho(
            _constantsJson.getAddress(string.concat(".strategies.", MORPHO_COMPOUND_V2_KEY, ".morpho"))
        );
        IERC20 poolRewardToken = IERC20(_constantsJson.getAddress(string.concat(".tokens.comp")));
        MorphoCompoundV2.ILens lens = MorphoCompoundV2.ILens(
            _constantsJson.getAddress(string.concat(".strategies.", MORPHO_COMPOUND_V2_KEY, ".lens"))
        );

        vm.broadcast(_deployerPrivateKey);
        MorphoCompoundV2.MorphoCompoundV2Strategy implementation = new MorphoCompoundV2.MorphoCompoundV2Strategy(
            assetGroupRegistry,
            spoolAccessControl,
            morpho,
            poolRewardToken,
            swapper,
            lens
        );

        _contractsJson.addVariantStrategyImplementation(MORPHO_COMPOUND_V2_KEY, address(implementation));

        // upgrade morpho-compound-v2:
        // - morpho-compound-v2-dai
        // - morpho-compound-v2-usdc
        // - morpho-compound-v2-usdt
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

        // upgrade oeth-holding:
        // - proxy
    }

    function redeployREthHolding() internal {
        uint256 assetGroupId = assetGroups(WETH_KEY);

        IRocketSwapRouter rocketSwapRouter = IRocketSwapRouter(
            _constantsJson.getAddress(string.concat(".strategies.", RETH_HOLDING_KEY, ".rocketSwapRouter"))
        );

        vm.broadcast(_deployerPrivateKey);
        REthHoldingStrategy implementation = new REthHoldingStrategy(
            assetGroupRegistry, spoolAccessControl, assetGroupId, rocketSwapRouter, assets(WETH_KEY)
        );

        _contractsJson.addVariantStrategyImplementation(RETH_HOLDING_KEY, address(implementation));

        // upgrade reth-holding:
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

        // upgrade sfrxeth-holding:
        // - proxy
    }

    function redeployStEthHolding() internal {
        uint256 assetGroupId = assetGroups(WETH_KEY);

        ILido lido = ILido(_constantsJson.getAddress(string.concat(".strategies.", STETH_HOLDING_KEY, ".lido")));
        ICurveEthPool curvePool =
            ICurveEthPool(_constantsJson.getAddress(string.concat(".strategies.", CURVE_STETH_KEY, ".pool")));

        vm.broadcast(_deployerPrivateKey);
        StEthHoldingStrategy implementation = new StEthHoldingStrategy(
            assetGroupRegistry, spoolAccessControl, assetGroupId, lido, curvePool, assets(WETH_KEY)
        );

        _contractsJson.addVariantStrategyImplementation(STETH_HOLDING_KEY, address(implementation));

        // upgrade steth-holding:
        // - proxy
    }

    function redeployYearnV2() internal {
        vm.broadcast(_deployerPrivateKey);
        YearnV2Strategy implementation = new YearnV2Strategy(assetGroupRegistry, spoolAccessControl);

        _contractsJson.addVariantStrategyImplementation(YEARN_V2_KEY, address(implementation));

        // upgrade yearn-v2:
        // - yearn-v2-dai
        // - yearn-v2-usdc
        // - yearn-v2-usdt
    }
}

contract DeployStrategiesDepositedEventP2 is MainnetExtendedSetup {
    // optimizer_runs = 2500

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        // reselialize strategies
        _contractsJson.reserializeKeyAddress("strategies");

        // deploy new implementations for strategies
        redeployCurve3pool();
        redeployMetamorphoGauntlet();
    }

    function redeployCurve3pool() internal {
        uint256 assetGroupId = assetGroups(DAI_USDC_USDT_KEY);

        vm.broadcast(_deployerPrivateKey);
        Curve3poolStrategy implementation = new Curve3poolStrategy(
            assetGroupRegistry, spoolAccessControl, assetGroupId, swapper
        );

        _contractsJson.addVariantStrategyImplementation(CURVE_3POOL_KEY, address(implementation));

        // upgrade curve-3pool:
        // - proxy
    }

    function redeployMetamorphoGauntlet() internal {
        vm.broadcast(_deployerPrivateKey);
        MetamorphoStrategy implementation = new MetamorphoStrategy(assetGroupRegistry, spoolAccessControl, swapper);

        _contractsJson.addVariantStrategyImplementation(METAMORPHO_GAUNTLET, address(implementation));

        // upgrade metamorpho-gauntlet:
        // - metamorpho-gauntlet-dai-core
        // - metamorpho-gauntlet-lrt-core
        // - metamorpho-gauntlet-mkr-blended
        // - metamorpho-gauntlet-usdt-prime
    }
}

contract DeployStrategiesDepositedEventP3 is MainnetExtendedSetup {
    // optimizer_runs = 800

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        // reselialize strategies
        _contractsJson.reserializeKeyAddress("strategies");

        // deploy new implementations for strategies
        redeployConvex3pool();
        redeployConvexStFrxeth();
    }

    function redeployConvex3pool() internal {
        uint256 assetGroupId = assetGroups(DAI_USDC_USDT_KEY);

        IBooster booster =
            IBooster(_constantsJson.getAddress(string.concat(".strategies.", CONVEX_BASE_KEY, ".booster")));

        vm.broadcast(_deployerPrivateKey);
        Convex3poolStrategy implementation = new Convex3poolStrategy(
            assetGroupRegistry, spoolAccessControl, assetGroupId, swapper, booster
        );

        _contractsJson.addVariantStrategyImplementation(CONVEX_3POOL_KEY, address(implementation));

        // upgrade convex-3pool:
        // - proxy
    }

    function redeployConvexStFrxeth() internal {
        uint256 assetGroupId = assetGroups(WETH_KEY);

        vm.broadcast(_deployerPrivateKey);
        ConvexStFrxEthStrategy implementation = new ConvexStFrxEthStrategy(
            assetGroupRegistry, spoolAccessControl, assetGroupId, swapper
        );

        _contractsJson.addVariantStrategyImplementation(CONVEX_STFRXETH_KEY, address(implementation));

        // upgrade convex-stfrxeth:
        // - proxy
    }
}

contract DeployStrategiesDepositedEventP4 is MainnetExtendedSetup {
    // optimizer_runs = 250

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        // reselialize strategies
        _contractsJson.reserializeKeyAddress("strategies");

        // deploy new implementations for strategies
        redeployConvexAlusd();
    }

    function redeployConvexAlusd() internal {
        uint256 assetGroupId = assetGroups(DAI_USDC_USDT_KEY);

        IBooster booster =
            IBooster(_constantsJson.getAddress(string.concat(".strategies.", CONVEX_BASE_KEY, ".booster")));

        vm.broadcast(_deployerPrivateKey);
        ConvexAlusdStrategy implementation = new ConvexAlusdStrategy(
            assetGroupRegistry, spoolAccessControl, assetGroupId, swapper, booster, 1
        );

        _contractsJson.addVariantStrategyImplementation(CONVEX_ALUSD_KEY, address(implementation));

        // upgrade convex-alusd:
        // - proxy
    }
}
