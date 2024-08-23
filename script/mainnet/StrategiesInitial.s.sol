// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/utils/math/SafeCast.sol";
import "@openzeppelin/utils/Strings.sol";
import "../../src/libraries/uint16a16Lib.sol";
import "../../src/strategies/convex/Convex3poolStrategy.sol";
import "../../src/strategies/convex/ConvexAlusdStrategy.sol";
import "../../src/strategies/convex/ConvexStFrxEthStrategy.sol";
import "../../src/strategies/curve/Curve3poolStrategy.sol";
import "../../src/strategies/AaveV2Strategy.sol";
import "../../src/strategies/CompoundV2Strategy.sol";
import "../../src/strategies/IdleStrategy.sol";
import "../../src/strategies/MorphoAaveV2Strategy.sol" as MorphoAaveV2;
import "../../src/strategies/MorphoCompoundV2Strategy.sol" as MorphoCompoundV2;
import "../../src/strategies/NotionalFinanceStrategy.sol";
import "../../src/strategies/REthHoldingStrategy.sol";
import "../../src/strategies/SfrxEthHoldingStrategy.sol";
import "../../src/strategies/StEthHoldingStrategy.sol";
import "../../src/strategies/YearnV2Strategy.sol";
import "../../src/strategies/OEthHoldingStrategy.sol";
import "../../src/strategies/GearboxV3Strategy.sol";
import "../../src/strategies/GearboxV3SwapStrategy.sol";
import "../../src/strategies/MetamorphoStrategy.sol";
import "../../src/strategies/YearnV3StrategyWithJuice.sol";
import "../../src/strategies/YearnV3StrategyWithGauge.sol";
import "../../src/strategies/EthenaStrategy.sol";
import "../helper/JsonHelper.sol";
import "./AssetsInitial.s.sol";

string constant AAVE_V2_KEY = "aave-v2";
string constant COMPOUND_V2_KEY = "compound-v2";
string constant CONVEX_BASE_KEY = "convex-base";
string constant CONVEX_3POOL_KEY = "convex-3pool";
string constant CONVEX_ALUSD_KEY = "convex-alusd";
string constant CONVEX_STFRXETH_KEY = "convex-stfrxeth";
string constant CURVE_3POOL_KEY = "curve-3pool";
string constant CURVE_ALUSD_KEY = "curve-alusd";
string constant CURVE_FRXETH_KEY = "curve-frxeth";
string constant CURVE_STETH_KEY = "curve-steth";
string constant CURVE_OETH_KEY = "curve-oeth";
string constant CURVE_STFRXETH_KEY = "curve-stfrxeth";
string constant GEARBOX_V3_KEY = "gearbox-v3";
string constant METAMORPHO_KEY = "metamorpho";
string constant IDLE_BEST_YIELD_SENIOR_KEY = "idle-best-yield-senior";
string constant MORPHO_AAVE_V2_KEY = "morpho-aave-v2";
string constant MORPHO_COMPOUND_V2_KEY = "morpho-compound-v2";
string constant NOTIONAL_FINANCE_KEY = "notional-finance";
string constant RETH_HOLDING_KEY = "reth-holding";
string constant SFRXETH_HOLDING_KEY = "sfrxeth-holding";
string constant STETH_HOLDING_KEY = "steth-holding";
string constant OETH_HOLDING_KEY = "oeth-holding";
string constant YEARN_V2_KEY = "yearn-v2";
string constant YEARN_V3_GAUGED_KEY = "yearn-v3-gauged";
string constant YEARN_V3_JUICED_KEY = "yearn-v3-juiced";
string constant ETHENA_KEY = "ethena";

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
        IStrategyRegistry strategyRegistry,
        UsdPriceFeedManager priceFeedManager,
        Extended extended
    ) public {
        StandardContracts memory contracts = StandardContracts({
            accessControl: accessControl,
            assetGroupRegistry: assetGroupRegistry,
            swapper: swapper,
            proxyAdmin: proxyAdmin,
            strategyRegistry: strategyRegistry
        });

        deployAaveV2(contracts);

        deployCompoundV2(contracts);

        deployConvex(contracts);

        deployCurve(contracts);

        deployIdle(contracts);

        deployLsd(contracts);

        deployMorpho(contracts);

        deployNotionalFinance(contracts);

        deployYearnV2(contracts);

        if (extended >= Extended.OETH) {
            deployOeth(contracts, true);
        }
        if (extended >= Extended.CONVEX_STETH_FRXETH) {
            deployConvexStFrxEth(contracts, true);
        }
        if (extended >= Extended.GEARBOX_V3) {
            deployGearboxV3(contracts, true);
        }
        if (extended >= Extended.METAMORPHO_YEARN_V3) {
            deployMetamorpho(contracts, true);

            deployYearnV3WithGauge(contracts, true);

            deployYearnV3WithJuice(contracts, true);
        }
        if (extended >= Extended.METAMORPHO_EXTRA) {
            deployMetamorphoExtra(contracts, true);
        }
        if (extended >= Extended.GEARBOX_V3_EXTRA) {
            deployGearboxV3Extra(contracts, true);
        }
        if (extended >= Extended.GEARBOX_V3_SWAP) {
            deployGearboxV3Swap(contracts, priceFeedManager, true);
        }
    }

    function deployAaveV2(StandardContracts memory contracts) public {
        // create implementation contract
        ILendingPoolAddressesProvider provider = ILendingPoolAddressesProvider(
            constantsJson().getAddress(string.concat(".strategies.", AAVE_V2_KEY, ".lendingPoolAddressesProvider"))
        );

        AaveV2Strategy implementation =
            new AaveV2Strategy(contracts.assetGroupRegistry, contracts.accessControl, provider);

        contractsJson().addVariantStrategyImplementation(AAVE_V2_KEY, address(implementation));

        // create variant proxies
        string[] memory variants = new string[](3);
        variants[0] = DAI_KEY;
        variants[1] = USDC_KEY;
        variants[2] = USDT_KEY;

        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = _getVariantName(AAVE_V2_KEY, variants[i]);

            address variant = _newProxy(address(implementation), contracts.proxyAdmin);
            uint256 assetGroupId = assetGroups(variants[i]);
            AaveV2Strategy(variant).initialize(variantName, assetGroupId);
            _registerStrategyVariant(AAVE_V2_KEY, variants[i], variant, assetGroupId, contracts.strategyRegistry);
        }
    }

    function deployCompoundV2(StandardContracts memory contracts) public {
        // create implementation contract
        IComptroller comptroller =
            IComptroller(constantsJson().getAddress(string.concat(".strategies.", COMPOUND_V2_KEY, ".comptroller")));

        CompoundV2Strategy implementation = new CompoundV2Strategy(
            contracts.assetGroupRegistry, contracts.accessControl, contracts.swapper, comptroller
        );

        contractsJson().addVariantStrategyImplementation(COMPOUND_V2_KEY, address(implementation));

        // create variant proxies
        string[] memory variants = new string[](3);
        variants[0] = DAI_KEY;
        variants[1] = USDC_KEY;
        variants[2] = USDT_KEY;

        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = _getVariantName(COMPOUND_V2_KEY, variants[i]);

            ICErc20 cToken = ICErc20(
                constantsJson().getAddress(string.concat(".strategies.", COMPOUND_V2_KEY, ".", variants[i], ".cToken"))
            );

            address variant = _newProxy(address(implementation), contracts.proxyAdmin);
            uint256 assetGroupId = assetGroups(variants[i]);
            CompoundV2Strategy(variant).initialize(variantName, assetGroupId, cToken);
            _registerStrategyVariant(COMPOUND_V2_KEY, variants[i], variant, assetGroupId, contracts.strategyRegistry);
        }
    }

    function deployConvex(StandardContracts memory contracts) public {
        // convex 3pool
        {
            // create implementation contract
            uint256 assetGroupId = assetGroups(DAI_USDC_USDT_KEY);

            IBooster booster =
                IBooster(constantsJson().getAddress(string.concat(".strategies.", CONVEX_BASE_KEY, ".booster")));

            Convex3poolStrategy implementation = new Convex3poolStrategy(
                contracts.assetGroupRegistry, contracts.accessControl, assetGroupId, contracts.swapper, booster
            );

            // create proxy
            address proxy;
            {
                ICurve3CoinPool pool =
                    ICurve3CoinPool(constantsJson().getAddress(string.concat(".strategies.", CURVE_3POOL_KEY, ".pool")));
                IERC20 lpToken =
                    IERC20(constantsJson().getAddress(string.concat(".strategies.", CURVE_3POOL_KEY, ".token")));
                uint96 pid = SafeCast.toUint96(
                    constantsJson().getUint256(string.concat(".strategies.", CONVEX_3POOL_KEY, ".pid"))
                );
                bool extraRewards =
                    constantsJson().getBool(string.concat(".strategies.", CONVEX_3POOL_KEY, ".extraRewards"));
                int128 positiveYieldLimit = SafeCast.toInt128(
                    constantsJson().getInt256(string.concat(".strategies.", CONVEX_3POOL_KEY, ".positiveYieldLimit"))
                );
                int128 negativeYieldLimit = SafeCast.toInt128(
                    constantsJson().getInt256(string.concat(".strategies.", CONVEX_3POOL_KEY, ".negativeYieldLimit"))
                );

                uint16a16 assetMapping;

                address[] memory assetGroup =
                    contracts.assetGroupRegistry.listAssetGroup(assetGroups(DAI_USDC_USDT_KEY));
                for (uint256 i; i < assetGroup.length; ++i) {
                    bool found = false;
                    for (uint256 j; j < 4; ++j) {
                        if (ICurvePoolUint256(address(pool)).coins(j) == assetGroup[i]) {
                            assetMapping = assetMapping.set(i, j);
                            found = true;
                            break;
                        }
                    }

                    if (!found) {
                        revert("Curve asset not found.");
                    }
                }

                proxy = _newProxy(address(implementation), contracts.proxyAdmin);
                Convex3poolStrategy(proxy).initialize(
                    CONVEX_3POOL_KEY,
                    pool,
                    lpToken,
                    assetMapping,
                    pid,
                    extraRewards,
                    positiveYieldLimit,
                    negativeYieldLimit
                );
            }

            _registerStrategy(
                CONVEX_3POOL_KEY, address(implementation), proxy, assetGroupId, contracts.strategyRegistry
            );
        }

        // convex Alusd
        {
            // create implementation contract
            uint256 assetGroupId = assetGroups(DAI_USDC_USDT_KEY);

            IBooster booster =
                IBooster(constantsJson().getAddress(string.concat(".strategies.", CONVEX_BASE_KEY, ".booster")));

            ConvexAlusdStrategy implementation = new ConvexAlusdStrategy(
                contracts.assetGroupRegistry, contracts.accessControl, assetGroupId, contracts.swapper, booster, 1
            );

            // create proxy
            address proxy;
            {
                address pool = constantsJson().getAddress(string.concat(".strategies.", CURVE_3POOL_KEY, ".pool"));
                address lpToken = constantsJson().getAddress(string.concat(".strategies.", CURVE_3POOL_KEY, ".token"));
                address poolMeta = constantsJson().getAddress(string.concat(".strategies.", CURVE_ALUSD_KEY, ".token"));
                uint96 pid = SafeCast.toUint96(
                    constantsJson().getUint256(string.concat(".strategies.", CONVEX_ALUSD_KEY, ".pid"))
                );
                bool extraRewards =
                    constantsJson().getBool(string.concat(".strategies.", CONVEX_ALUSD_KEY, ".extraRewards"));
                int128 positiveYieldLimit = SafeCast.toInt128(
                    constantsJson().getInt256(string.concat(".strategies.", CONVEX_ALUSD_KEY, ".positiveYieldLimit"))
                );
                int128 negativeYieldLimit = SafeCast.toInt128(
                    constantsJson().getInt256(string.concat(".strategies.", CONVEX_ALUSD_KEY, ".negativeYieldLimit"))
                );

                uint16a16 assetMapping;
                address[] memory assetGroup =
                    contracts.assetGroupRegistry.listAssetGroup(assetGroups(DAI_USDC_USDT_KEY));
                for (uint256 i; i < assetGroup.length; ++i) {
                    bool found = false;
                    for (uint256 j; j < 4; ++j) {
                        if (ICurvePoolUint256(pool).coins(j) == assetGroup[i]) {
                            assetMapping = assetMapping.set(i, j);
                            found = true;
                            break;
                        }
                    }

                    if (!found) {
                        revert("Curve asset not found.");
                    }
                }

                proxy = _newProxy(address(implementation), contracts.proxyAdmin);
                ConvexAlusdStrategy(proxy).initialize(
                    CONVEX_ALUSD_KEY,
                    pool,
                    lpToken,
                    assetMapping,
                    poolMeta,
                    pid,
                    extraRewards,
                    positiveYieldLimit,
                    negativeYieldLimit
                );
            }

            _registerStrategy(
                CONVEX_ALUSD_KEY, address(implementation), proxy, assetGroupId, contracts.strategyRegistry
            );
        }
    }

    function deployCurve(StandardContracts memory contracts) public {
        // curve 3pool
        {
            // create implementation contract
            uint256 assetGroupId = assetGroups(DAI_USDC_USDT_KEY);

            Curve3poolStrategy implementation = new Curve3poolStrategy(
                contracts.assetGroupRegistry, contracts.accessControl, assetGroupId, contracts.swapper
            );

            // create proxy
            ICurve3CoinPool pool =
                ICurve3CoinPool(constantsJson().getAddress(string.concat(".strategies.", CURVE_3POOL_KEY, ".pool")));
            ICurveGauge gauge =
                ICurveGauge(constantsJson().getAddress(string.concat(".strategies.", CURVE_3POOL_KEY, ".gauge")));
            int128 positiveYieldLimit = SafeCast.toInt128(
                constantsJson().getInt256(string.concat(".strategies.", CURVE_3POOL_KEY, ".positiveYieldLimit"))
            );
            int128 negativeYieldLimit = SafeCast.toInt128(
                constantsJson().getInt256(string.concat(".strategies.", CURVE_3POOL_KEY, ".negativeYieldLimit"))
            );

            uint16a16 assetMapping;
            address[] memory assetGroup = contracts.assetGroupRegistry.listAssetGroup(assetGroups(DAI_USDC_USDT_KEY));
            for (uint256 i; i < assetGroup.length; ++i) {
                bool found = false;
                for (uint256 j; j < 4; ++j) {
                    if (ICurvePoolUint256(address(pool)).coins(j) == assetGroup[i]) {
                        assetMapping = assetMapping.set(i, j);
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    revert("Curve asset not found.");
                }
            }

            address proxy = _newProxy(address(implementation), contracts.proxyAdmin);
            Curve3poolStrategy(proxy).initialize(
                CURVE_3POOL_KEY, pool, assetMapping, gauge, positiveYieldLimit, negativeYieldLimit
            );

            _registerStrategy(CURVE_3POOL_KEY, address(implementation), proxy, assetGroupId, contracts.strategyRegistry);
        }
    }

    function deployIdle(StandardContracts memory contracts) public {
        // create implementation contract
        IdleStrategy implementation =
            new IdleStrategy(contracts.assetGroupRegistry, contracts.accessControl, contracts.swapper);

        contractsJson().addVariantStrategyImplementation(IDLE_BEST_YIELD_SENIOR_KEY, address(implementation));

        // create variant proxies
        string[] memory variants = new string[](3);
        variants[0] = DAI_KEY;
        variants[1] = USDC_KEY;
        variants[2] = USDT_KEY;

        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = _getVariantName(IDLE_BEST_YIELD_SENIOR_KEY, variants[i]);

            IIdleToken idleToken = IIdleToken(
                constantsJson().getAddress(
                    string.concat(".strategies.", IDLE_BEST_YIELD_SENIOR_KEY, ".", variants[i], ".idleToken")
                )
            );

            address variant = _newProxy(address(implementation), contracts.proxyAdmin);
            uint256 assetGroupId = assetGroups(variants[i]);
            IdleStrategy(variant).initialize(variantName, assetGroupId, idleToken);
            _registerStrategyVariant(
                IDLE_BEST_YIELD_SENIOR_KEY, variants[i], variant, assetGroupId, contracts.strategyRegistry
            );
        }
    }

    function deployLsd(StandardContracts memory contracts) public {
        // reth holding
        {
            // create implementation contract
            uint256 assetGroupId = assetGroups(WETH_KEY);

            IRocketSwapRouter rocketSwapRouter = IRocketSwapRouter(
                constantsJson().getAddress(string.concat(".strategies.", RETH_HOLDING_KEY, ".rocketSwapRouter"))
            );

            REthHoldingStrategy implementation = new REthHoldingStrategy(
                contracts.assetGroupRegistry, contracts.accessControl, assetGroupId, rocketSwapRouter, assets(WETH_KEY)
            );

            // create proxy
            address proxy = _newProxy(address(implementation), contracts.proxyAdmin);
            REthHoldingStrategy(payable(proxy)).initialize(RETH_HOLDING_KEY);

            _registerStrategy(
                RETH_HOLDING_KEY, address(implementation), proxy, assetGroupId, contracts.strategyRegistry
            );
        }

        // sfrxeth holding
        {
            // create implementation contract
            uint256 assetGroupId = assetGroups(WETH_KEY);

            IERC20 frxEthToken = IERC20(constantsJson().getAddress(string.concat(".tokens.frxEth")));
            ISfrxEthToken sfrxEthToken = ISfrxEthToken(constantsJson().getAddress(string.concat(".tokens.sfrxEth")));
            IFrxEthMinter frxEthMinter = IFrxEthMinter(
                constantsJson().getAddress(string.concat(".strategies.", SFRXETH_HOLDING_KEY, ".frxEthMinter"))
            );
            ICurveEthPool curvePool =
                ICurveEthPool(constantsJson().getAddress(string.concat(".strategies.", CURVE_FRXETH_KEY, ".pool")));

            SfrxEthHoldingStrategy implementation = new SfrxEthHoldingStrategy(
                contracts.assetGroupRegistry,
                contracts.accessControl,
                assetGroupId,
                frxEthToken,
                sfrxEthToken,
                frxEthMinter,
                curvePool,
                assets(WETH_KEY)
            );

            // create proxy
            address proxy = _newProxy(address(implementation), contracts.proxyAdmin);
            SfrxEthHoldingStrategy(payable(proxy)).initialize(SFRXETH_HOLDING_KEY);

            _registerStrategy(
                SFRXETH_HOLDING_KEY, address(implementation), proxy, assetGroupId, contracts.strategyRegistry
            );
        }

        // steth holding
        {
            // create implementation contract
            uint256 assetGroupId = assetGroups(WETH_KEY);

            ILido lido = ILido(constantsJson().getAddress(string.concat(".strategies.", STETH_HOLDING_KEY, ".lido")));
            ICurveEthPool curvePool =
                ICurveEthPool(constantsJson().getAddress(string.concat(".strategies.", CURVE_STETH_KEY, ".pool")));

            StEthHoldingStrategy implementation = new StEthHoldingStrategy(
                contracts.assetGroupRegistry, contracts.accessControl, assetGroupId, lido, curvePool, assets(WETH_KEY)
            );

            // create proxy
            address proxy = _newProxy(address(implementation), contracts.proxyAdmin);
            StEthHoldingStrategy(payable(proxy)).initialize(STETH_HOLDING_KEY);

            _registerStrategy(
                STETH_HOLDING_KEY, address(implementation), proxy, assetGroupId, contracts.strategyRegistry
            );
        }
    }

    function deployMorpho(StandardContracts memory contracts) public {
        // morpho aave v2
        {
            // create implementation contract
            MorphoAaveV2.MorphoAaveV2Strategy implementation;
            {
                MorphoAaveV2.IMorpho morpho = MorphoAaveV2.IMorpho(
                    constantsJson().getAddress(string.concat(".strategies.", MORPHO_AAVE_V2_KEY, ".morpho"))
                );
                IERC20 poolRewardToken = IERC20(constantsJson().getAddress(string.concat(".tokens.stkAave")));
                MorphoAaveV2.ILens lens = MorphoAaveV2.ILens(
                    constantsJson().getAddress(string.concat(".strategies.", MORPHO_AAVE_V2_KEY, ".lens"))
                );

                implementation = new MorphoAaveV2.MorphoAaveV2Strategy(
                    contracts.assetGroupRegistry,
                    contracts.accessControl,
                    morpho,
                    poolRewardToken,
                    contracts.swapper,
                    lens
                );

                contractsJson().addVariantStrategyImplementation(MORPHO_AAVE_V2_KEY, address(implementation));
            }

            // create variant proxies
            string[] memory variants = new string[](3);
            variants[0] = DAI_KEY;
            variants[1] = USDC_KEY;
            variants[2] = USDT_KEY;

            for (uint256 i; i < variants.length; ++i) {
                string memory variantName = _getVariantName(MORPHO_AAVE_V2_KEY, variants[i]);

                address poolToken =
                    constantsJson().getAddress(string.concat(".strategies.", AAVE_V2_KEY, ".", variants[i], ".aToken"));
                int128 positiveYieldLimit = SafeCast.toInt128(
                    constantsJson().getInt256(
                        string.concat(".strategies.", MORPHO_AAVE_V2_KEY, ".", variants[i], ".positiveYieldLimit")
                    )
                );
                int128 negativeYieldLimit = SafeCast.toInt128(
                    constantsJson().getInt256(
                        string.concat(".strategies.", MORPHO_AAVE_V2_KEY, ".", variants[i], ".negativeYieldLimit")
                    )
                );

                address variant = _newProxy(address(implementation), contracts.proxyAdmin);
                uint256 assetGroupId = assetGroups(variants[i]);
                MorphoAaveV2.MorphoAaveV2Strategy(variant).initialize(
                    variantName, assetGroupId, poolToken, positiveYieldLimit, negativeYieldLimit
                );
                _registerStrategyVariant(
                    MORPHO_AAVE_V2_KEY, variants[i], variant, assetGroupId, contracts.strategyRegistry
                );
            }
        }

        // morpho compound v2
        {
            // create implementation contract
            MorphoCompoundV2.MorphoCompoundV2Strategy implementation;
            {
                MorphoCompoundV2.IMorpho morpho = MorphoCompoundV2.IMorpho(
                    constantsJson().getAddress(string.concat(".strategies.", MORPHO_COMPOUND_V2_KEY, ".morpho"))
                );
                IERC20 poolRewardToken = IERC20(constantsJson().getAddress(string.concat(".tokens.comp")));
                MorphoCompoundV2.ILens lens = MorphoCompoundV2.ILens(
                    constantsJson().getAddress(string.concat(".strategies.", MORPHO_COMPOUND_V2_KEY, ".lens"))
                );

                implementation = new MorphoCompoundV2.MorphoCompoundV2Strategy(
                    contracts.assetGroupRegistry,
                    contracts.accessControl,
                    morpho,
                    poolRewardToken,
                    contracts.swapper,
                    lens
                );

                contractsJson().addVariantStrategyImplementation(MORPHO_COMPOUND_V2_KEY, address(implementation));
            }

            // create variant proxies
            string[] memory variants = new string[](3);
            variants[0] = DAI_KEY;
            variants[1] = USDC_KEY;
            variants[2] = USDT_KEY;

            for (uint256 i; i < variants.length; ++i) {
                string memory variantName = _getVariantName(MORPHO_COMPOUND_V2_KEY, variants[i]);

                address poolToken = constantsJson().getAddress(
                    string.concat(".strategies.", COMPOUND_V2_KEY, ".", variants[i], ".cToken")
                );
                int128 positiveYieldLimit = SafeCast.toInt128(
                    constantsJson().getInt256(
                        string.concat(".strategies.", MORPHO_COMPOUND_V2_KEY, ".", variants[i], ".positiveYieldLimit")
                    )
                );
                int128 negativeYieldLimit = SafeCast.toInt128(
                    constantsJson().getInt256(
                        string.concat(".strategies.", MORPHO_COMPOUND_V2_KEY, ".", variants[i], ".negativeYieldLimit")
                    )
                );

                address variant = _newProxy(address(implementation), contracts.proxyAdmin);
                uint256 assetGroupId = assetGroups(variants[i]);
                MorphoCompoundV2.MorphoCompoundV2Strategy(variant).initialize(
                    variantName, assetGroupId, poolToken, positiveYieldLimit, negativeYieldLimit
                );
                _registerStrategyVariant(
                    MORPHO_COMPOUND_V2_KEY, variants[i], variant, assetGroupId, contracts.strategyRegistry
                );
            }
        }
    }

    function deployNotionalFinance(StandardContracts memory contracts) public {
        // create implementation contract
        INotional notional =
            INotional(constantsJson().getAddress(string.concat(".strategies.", NOTIONAL_FINANCE_KEY, ".notionalProxy")));
        IERC20 note = IERC20(constantsJson().getAddress(string.concat(".tokens.note")));

        NotionalFinanceStrategy implementation = new NotionalFinanceStrategy(
            contracts.assetGroupRegistry, contracts.accessControl, contracts.swapper, notional, note
        );

        contractsJson().addVariantStrategyImplementation(NOTIONAL_FINANCE_KEY, address(implementation));

        // create variant proxies
        string[] memory variants = new string[](2);
        variants[0] = DAI_KEY;
        variants[1] = USDC_KEY;

        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = _getVariantName(NOTIONAL_FINANCE_KEY, variants[i]);

            INToken nToken = INToken(
                constantsJson().getAddress(
                    string.concat(".strategies.", NOTIONAL_FINANCE_KEY, ".", variants[i], ".nToken")
                )
            );

            address variant = _newProxy(address(implementation), contracts.proxyAdmin);
            uint256 assetGroupId = assetGroups(variants[i]);
            NotionalFinanceStrategy(variant).initialize(variantName, assetGroupId, nToken);
            _registerStrategyVariant(
                NOTIONAL_FINANCE_KEY, variants[i], variant, assetGroupId, contracts.strategyRegistry
            );
        }
    }

    function deployYearnV2(StandardContracts memory contracts) public {
        // create implementation contract
        YearnV2Strategy implementation = new YearnV2Strategy(contracts.assetGroupRegistry, contracts.accessControl);

        contractsJson().addVariantStrategyImplementation(YEARN_V2_KEY, address(implementation));

        // create variant proxies
        string[] memory variants = new string[](3);
        variants[0] = DAI_KEY;
        variants[1] = USDC_KEY;
        variants[2] = USDT_KEY;

        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = _getVariantName(YEARN_V2_KEY, variants[i]);

            IYearnTokenVault yTokenVault = IYearnTokenVault(
                constantsJson().getAddress(string.concat(".strategies.", YEARN_V2_KEY, ".", variants[i], ".tokenVault"))
            );

            address variant = _newProxy(address(implementation), contracts.proxyAdmin);
            uint256 assetGroupId = assetGroups(variants[i]);
            YearnV2Strategy(variant).initialize(variantName, assetGroupId, yTokenVault);
            _registerStrategyVariant(YEARN_V2_KEY, variants[i], variant, assetGroupId, contracts.strategyRegistry);
        }
    }

    function deployOeth(StandardContracts memory contracts, bool register) public {
        // create implementation contract
        uint256 assetGroupId = assetGroups(WETH_KEY);

        IOEthToken oEthToken = IOEthToken(constantsJson().getAddress(string.concat(".tokens.oEth")));

        IVaultCore oEthVault =
            IVaultCore(constantsJson().getAddress(string.concat(".strategies.", OETH_HOLDING_KEY, ".vault")));

        ICurveEthPool curvePool =
            ICurveEthPool(constantsJson().getAddress(string.concat(".strategies.", CURVE_OETH_KEY, ".pool")));

        OEthHoldingStrategy implementation = new OEthHoldingStrategy(
            contracts.assetGroupRegistry,
            contracts.accessControl,
            assetGroupId,
            oEthToken,
            oEthVault,
            curvePool,
            assets(WETH_KEY)
        );

        // create proxy
        address proxy = _newProxy(address(implementation), contracts.proxyAdmin);
        OEthHoldingStrategy(payable(proxy)).initialize(OETH_HOLDING_KEY);

        if (register) {
            _registerStrategy(
                OETH_HOLDING_KEY, address(implementation), proxy, assetGroupId, contracts.strategyRegistry
            );
        }
    }

    function deployConvexStFrxEth(StandardContracts memory contracts, bool register) public {
        {
            // create implementation contract
            uint256 assetGroupId = assetGroups(WETH_KEY);

            ConvexStFrxEthStrategy implementation = new ConvexStFrxEthStrategy(
                contracts.assetGroupRegistry, contracts.accessControl, assetGroupId, contracts.swapper
            );

            // create proxy
            address payable proxy;
            {
                int128 positiveYieldLimit = SafeCast.toInt128(
                    constantsJson().getInt256(string.concat(".strategies.", CONVEX_STFRXETH_KEY, ".positiveYieldLimit"))
                );
                int128 negativeYieldLimit = SafeCast.toInt128(
                    constantsJson().getInt256(string.concat(".strategies.", CONVEX_STFRXETH_KEY, ".negativeYieldLimit"))
                );

                bool extraRewards =
                    constantsJson().getBool(string.concat(".strategies.", CONVEX_STFRXETH_KEY, ".extraRewards"));

                proxy = payable(_newProxy(address(implementation), contracts.proxyAdmin));
                ConvexStFrxEthStrategy(proxy).initialize(
                    CONVEX_STFRXETH_KEY, positiveYieldLimit, negativeYieldLimit, extraRewards
                );
            }

            if (register) {
                _registerStrategy(
                    CONVEX_STFRXETH_KEY, address(implementation), proxy, assetGroupId, contracts.strategyRegistry
                );
            }
        }
    }

    function deployGearboxV3(StandardContracts memory contracts, bool register) public {
        GearboxV3Strategy implementation = deployGearboxV3Implementation(contracts);
        deployGearboxV3(contracts, implementation, register, 0);
    }

    function deployMetamorpho(StandardContracts memory contracts, bool register) public {
        MetamorphoStrategy implementation = deployMetamorphoImplementation(contracts);
        deployMetamorpho(contracts, implementation, register, 0);
    }

    function deployYearnV3WithGauge(StandardContracts memory contracts, bool register) public {
        // create implementation contract
        YearnV3StrategyWithGauge implementation =
            new YearnV3StrategyWithGauge(contracts.assetGroupRegistry, contracts.accessControl, contracts.swapper);
        contractsJson().addVariantStrategyImplementation(YEARN_V3_GAUGED_KEY, address(implementation));

        // create variant proxies
        string[] memory variants = new string[](3);
        variants[0] = DAI_KEY;
        variants[1] = USDC_KEY;
        variants[2] = WETH_KEY;

        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = _getVariantName(YEARN_V3_GAUGED_KEY, variants[i]);

            IERC4626 vault = IERC4626(
                constantsJson().getAddress(
                    string.concat(".strategies.", YEARN_V3_GAUGED_KEY, ".", variants[i], ".tokenVault")
                )
            );
            IERC4626 gauge = IERC4626(
                constantsJson().getAddress(
                    string.concat(".strategies.", YEARN_V3_GAUGED_KEY, ".", variants[i], ".gauge")
                )
            );

            address variant = _newProxy(address(implementation), contracts.proxyAdmin);
            uint256 assetGroupId = assetGroups(variants[i]);
            YearnV3StrategyWithGauge(variant).initialize(
                variantName, assetGroupId, vault, gauge, 10 ** (gauge.decimals() * 2)
            );
            if (register) {
                _registerStrategyVariant(
                    YEARN_V3_GAUGED_KEY, variants[i], variant, assetGroupId, contracts.strategyRegistry
                );
            } else {
                contractsJson().addVariantStrategyVariant(YEARN_V3_GAUGED_KEY, variantName, variant);
            }
        }
    }

    function deployYearnV3WithJuice(StandardContracts memory contracts, bool register) public {
        // create implementation contract
        YearnV3StrategyWithJuice implementation =
            new YearnV3StrategyWithJuice(contracts.assetGroupRegistry, contracts.accessControl);
        contractsJson().addVariantStrategyImplementation(YEARN_V3_JUICED_KEY, address(implementation));

        // create variant proxies
        string[] memory variants = new string[](1);
        variants[0] = DAI_KEY;

        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = _getVariantName(YEARN_V3_JUICED_KEY, variants[i]);

            IERC4626 vault = IERC4626(
                constantsJson().getAddress(
                    string.concat(".strategies.", YEARN_V3_JUICED_KEY, ".", variants[i], ".tokenVault")
                )
            );
            IERC4626 harvester = IERC4626(
                constantsJson().getAddress(
                    string.concat(".strategies.", YEARN_V3_JUICED_KEY, ".", variants[i], ".harvester")
                )
            );

            address variant = _newProxy(address(implementation), contracts.proxyAdmin);
            uint256 assetGroupId = assetGroups(variants[i]);
            YearnV3StrategyWithJuice(variant).initialize(
                variantName, assetGroupId, vault, harvester, 10 ** (harvester.decimals() * 2)
            );
            if (register) {
                _registerStrategyVariant(
                    YEARN_V3_JUICED_KEY, variants[i], variant, assetGroupId, contracts.strategyRegistry
                );
            } else {
                contractsJson().addVariantStrategyVariant(YEARN_V3_JUICED_KEY, variantName, variant);
            }
        }
    }

    function deployMetamorphoExtra(StandardContracts memory contracts, bool register) public {
        MetamorphoStrategy implementation = getMetamorphoImplementation();
        deployMetamorpho(contracts, implementation, register, 1);
    }

    function deployGearboxV3Extra(StandardContracts memory contracts, bool register) public {
        GearboxV3Strategy implementation = getGearboxV3Implementation();
        deployGearboxV3(contracts, implementation, register, 1);
    }

    function deployGearboxV3Swap(
        StandardContracts memory contracts,
        UsdPriceFeedManager priceFeedManager,
        bool register
    ) public {
        GearboxV3SwapStrategy implementation = deployGearboxV3SwapImplementation(contracts, priceFeedManager);
        deployGearboxV3Swap(contracts, implementation, register, 1);
    }

    function deployEthena(StandardContracts memory contracts, string memory assetKey) public {
        string memory variant;
        if (Strings.equal(assetKey, USDT_KEY)) {
            variant = USDT_KEY;
        } else if (Strings.equal(assetKey, USDC_KEY)) {
            variant = USDC_KEY;
        } else if (Strings.equal(assetKey, DAI_KEY)) {
            variant = DAI_KEY;
        } else if (Strings.equal(assetKey, USDE_KEY)) {
            variant = USDE_KEY;
        }
        require(bytes(variant).length > 0, "Invalid asset group");

        address implementation =
            contractsJson().getAddress(string.concat(".strategies.", ETHENA_KEY, ".implementation"));

        string memory variantName = _getVariantName(ETHENA_KEY, variant);

        address proxy = _newProxy(implementation, contracts.proxyAdmin);
        EthenaStrategy(proxy).initialize(variantName, assetGroups(variant));
        contractsJson().addVariantStrategyVariant(ETHENA_KEY, variantName, proxy);
    }

    function deployMetamorphoImplementation(StandardContracts memory contracts)
        public
        returns (MetamorphoStrategy implementation)
    {
        // create implementation contract
        implementation =
            new MetamorphoStrategy(contracts.assetGroupRegistry, contracts.accessControl, contracts.swapper);
        contractsJson().addVariantStrategyImplementation(METAMORPHO_KEY, address(implementation));

        return implementation;
    }

    function getMetamorphoImplementation() public view returns (MetamorphoStrategy implementation) {
        return MetamorphoStrategy(
            contractsJson().getAddress(string.concat(".strategies.", METAMORPHO_KEY, ".implementation"))
        );
    }

    function deployMetamorpho(
        StandardContracts memory contracts,
        MetamorphoStrategy implementation,
        bool register,
        uint256 round
    ) public {
        // create variant proxies
        string[] memory variants;
        if (round == 0) {
            variants = new string[](4);
            variants[0] = "gauntlet-lrt-core";
            variants[1] = "gauntlet-mkr-blended";
            variants[2] = "gauntlet-usdt-prime";
            variants[3] = "gauntlet-dai-core";
        } else if (round == 1) {
            variants = new string[](7);
            variants[0] = "gauntlet-weth-prime";
            variants[1] = "gauntlet-usdc-prime";
            variants[2] = "steakhouse-usdc";
            variants[3] = "steakhouse-pyusd";
            variants[4] = "bprotocol-flagship-eth";
            variants[5] = "bprotocol-flagship-usdt";
            variants[6] = "re7-weth";
        }
        require(variants.length > 0, "Invalid round");

        _deployMetamorpho(implementation, variants, contracts, register);
    }

    function _deployMetamorpho(
        MetamorphoStrategy implementation,
        string[] memory variants,
        StandardContracts memory contracts,
        bool register
    ) private {
        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = _getVariantName(METAMORPHO_KEY, variants[i]);

            string memory assetKey = constantsJson().getString(
                string.concat(".strategies.", METAMORPHO_KEY, ".", variants[i], ".underlyingAsset")
            );
            uint256 assetGroupId = assetGroups(assetKey);

            IERC4626 vault = IERC4626(
                constantsJson().getAddress(string.concat(".strategies.", METAMORPHO_KEY, ".", variants[i], ".vault"))
            );
            address[] memory rewards = constantsJson().getAddressArray(
                string.concat(".strategies.", METAMORPHO_KEY, ".", variants[i], ".rewards")
            );
            address variant =
                _createAndInitializeMetamorpho(contracts, implementation, variantName, assetGroupId, vault, rewards);
            if (register) {
                _registerStrategyVariant(METAMORPHO_KEY, variants[i], variant, assetGroupId, contracts.strategyRegistry);
            } else {
                contractsJson().addVariantStrategyVariant(METAMORPHO_KEY, variantName, variant);
            }
        }
    }

    function _createAndInitializeMetamorpho(
        StandardContracts memory contracts,
        MetamorphoStrategy implementation,
        string memory variantName,
        uint256 assetGroupId,
        IERC4626 vault,
        address[] memory rewards
    ) internal virtual returns (address variant) {
        variant = _newProxy(address(implementation), contracts.proxyAdmin);
        MetamorphoStrategy(variant).initialize(variantName, assetGroupId, vault, 10 ** (vault.decimals() * 2), rewards);
    }

    function deployGearboxV3Implementation(StandardContracts memory contracts)
        public
        returns (GearboxV3Strategy implementation)
    {
        implementation = new GearboxV3Strategy(contracts.assetGroupRegistry, contracts.accessControl, contracts.swapper);
        contractsJson().addVariantStrategyImplementation(GEARBOX_V3_KEY, address(implementation));
    }

    function deployGearboxV3SwapImplementation(
        StandardContracts memory contracts,
        IUsdPriceFeedManager priceFeedManager
    ) public returns (GearboxV3SwapStrategy implementation) {
        implementation =
        new GearboxV3SwapStrategy(contracts.assetGroupRegistry, contracts.accessControl, contracts.swapper, priceFeedManager);
        contractsJson().addVariantStrategyImplementation(GEARBOX_V3_KEY, "swap", address(implementation));
    }

    function getGearboxV3Implementation() public view returns (GearboxV3Strategy) {
        return GearboxV3Strategy(
            contractsJson().getAddress(string.concat(".strategies.", GEARBOX_V3_KEY, ".implementation"))
        );
    }

    function deployGearboxV3(
        StandardContracts memory contracts,
        GearboxV3Strategy implementation,
        bool register,
        uint256 round
    ) public {
        // create variant proxies
        string[] memory variants;
        if (round == 0) {
            variants = new string[](2);
            variants[0] = "weth";
            variants[1] = "usdc";
        } else if (round == 1) {
            variants = new string[](2);
            variants[0] = "dai";
            variants[1] = "usdt";
        }
        require(variants.length > 0, "Invalid round");

        _deployGearboxV3(implementation, variants, contracts, register);
    }

    function _deployGearboxV3(
        GearboxV3Strategy implementation,
        string[] memory variants,
        StandardContracts memory contracts,
        bool register
    ) private {
        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = _getVariantName(GEARBOX_V3_KEY, variants[i]);

            IFarmingPool sdToken = IFarmingPool(
                constantsJson().getAddress(string.concat(".strategies.", GEARBOX_V3_KEY, ".", variants[i], ".sdToken"))
            );

            uint256 assetGroupId = assetGroups(variants[i]);
            address variant =
                _createAndInitializeGearboxV3(contracts, implementation, variantName, assetGroupId, sdToken);
            if (register) {
                _registerStrategyVariant(GEARBOX_V3_KEY, variants[i], variant, assetGroupId, contracts.strategyRegistry);
            } else {
                contractsJson().addVariantStrategyVariant(GEARBOX_V3_KEY, variantName, variant);
            }
        }
    }

    function deployGearboxV3Swap(
        StandardContracts memory contracts,
        GearboxV3SwapStrategy implementation,
        bool register,
        uint256 round
    ) public {
        // create variant proxies
        string[] memory variants;
        if (round == 0) {
            variants = new string[](2);
            variants[0] = "crvusd-usdc";
            variants[1] = "gho-usdc";
        }
        require(variants.length > 0, "Invalid round");

        _deployGearboxV3Swap(implementation, variants, contracts, register);
    }

    function _deployGearboxV3Swap(
        GearboxV3SwapStrategy implementation,
        string[] memory variants,
        StandardContracts memory contracts,
        bool register
    ) private {
        for (uint256 i; i < variants.length; ++i) {
            string memory variantName = _getVariantName(GEARBOX_V3_KEY, variants[i]);

            IFarmingPool sdToken = IFarmingPool(
                constantsJson().getAddress(string.concat(".strategies.", GEARBOX_V3_KEY, ".", variants[i], ".sdToken"))
            );

            uint256 assetGroupId = assetGroups(variants[i]);
            address variant =
                _createAndInitializeGearboxV3Swap(contracts, implementation, variantName, assetGroupId, sdToken);
            if (register) {
                _registerStrategyVariant(GEARBOX_V3_KEY, variants[i], variant, assetGroupId, contracts.strategyRegistry);
            } else {
                contractsJson().addVariantStrategyVariant(GEARBOX_V3_KEY, variantName, variant);
            }
        }
    }

    function _createAndInitializeGearboxV3Swap(
        StandardContracts memory contracts,
        GearboxV3SwapStrategy implementation,
        string memory variantName,
        uint256 assetGroupId,
        IFarmingPool sdToken
    ) internal virtual returns (address variant) {
        variant = _newProxy(address(implementation), contracts.proxyAdmin);
        GearboxV3SwapStrategy(variant).initialize(variantName, assetGroupId, sdToken);
    }

    function _createAndInitializeGearboxV3(
        StandardContracts memory contracts,
        GearboxV3Strategy implementation,
        string memory variantName,
        uint256 assetGroupId,
        IFarmingPool sdToken
    ) internal virtual returns (address variant) {
        variant = _newProxy(address(implementation), contracts.proxyAdmin);
        GearboxV3Strategy(variant).initialize(variantName, assetGroupId, sdToken);
    }

    function deployEthenaImpl(StandardContracts memory contracts, IUsdPriceFeedManager priceFeedManager) public {
        address USDe = constantsJson().getAddress(".assets.usde.address");
        address sUSDe = constantsJson().getAddress(string.concat(".strategies.", ETHENA_KEY, ".sUSDe"));
        address ENAToken = constantsJson().getAddress(string.concat(".strategies.", ETHENA_KEY, ".ENA"));
        address implementation = address(
            new EthenaStrategy(
                contracts.assetGroupRegistry,
                contracts.accessControl,
                IERC20Metadata(USDe),
                IsUSDe(sUSDe),
                IERC20Metadata(ENAToken),
                contracts.swapper,
                priceFeedManager
            )
        );
        contractsJson().addVariantStrategyImplementation(ETHENA_KEY, implementation);
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
        internal
        pure
        returns (string memory)
    {
        return string.concat(strategyKey, "-", variantKey);
    }

    function test_mock_StrategiesInitial() external pure {}
}
