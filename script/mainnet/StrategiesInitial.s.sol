// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/utils/math/SafeCast.sol";
import "../../src/libraries/uint16a16Lib.sol";
import "../../src/strategies/convex/Convex3poolStrategy.sol";
import "../../src/strategies/convex/ConvexAlusdStrategy.sol";
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
import "../helper/JsonHelper.sol";
import "./AssetsInitial.s.sol";

string constant AAVE_V2_KEY = "aave-v2";
string constant COMPOUND_V2_KEY = "compound-v2";
string constant CONVEX_BASE_KEY = "convex-base";
string constant CONVEX_3POOL_KEY = "convex-3pool";
string constant CONVEX_ALUSD_KEY = "convex-alusd";
string constant CURVE_3POOL_KEY = "curve-3pool";
string constant CURVE_ALUSD_KEY = "curve-alusd";
string constant CURVE_FRXETH_KEY = "curve-frxeth";
string constant CURVE_STETH_KEY = "curve-steth";
string constant CURVE_OETH_KEY = "curve-oeth";
string constant IDLE_BEST_YIELD_SENIOR_KEY = "idle-best-yield-senior";
string constant MORPHO_AAVE_V2_KEY = "morpho-aave-v2";
string constant MORPHO_COMPOUND_V2_KEY = "morpho-compound-v2";
string constant NOTIONAL_FINANCE_KEY = "notional-finance";
string constant RETH_HOLDING_KEY = "reth-holding";
string constant SFRXETH_HOLDING_KEY = "sfrxeth-holding";
string constant STETH_HOLDING_KEY = "steth-holding";
string constant OETH_HOLDING_KEY = "oeth-holding";
string constant YEARN_V2_KEY = "yearn-v2";

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

        deployAaveV2(contracts);

        deployCompoundV2(contracts);

        deployConvex(contracts);

        deployCurve(contracts);

        deployIdle(contracts);

        deployLsd(contracts);

        deployMorpho(contracts);

        deployNotionalFinance(contracts);

        deployYearnV2(contracts);

        deployOeth(contracts);
    }

    function deployAaveV2(StandardContracts memory contracts) public {
        // create implementation contract
        ILendingPoolAddressesProvider provider = ILendingPoolAddressesProvider(
            constantsJson().getAddress(string.concat(".strategies.", AAVE_V2_KEY, ".lendingPoolAddressesProvider"))
        );

        AaveV2Strategy implementation = new AaveV2Strategy(
            contracts.assetGroupRegistry,
            contracts.accessControl,
            provider
        );

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
            contracts.assetGroupRegistry,
            contracts.accessControl,
            contracts.swapper,
            comptroller
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
                contracts.assetGroupRegistry,
                contracts.accessControl,
                assetGroupId,
                contracts.swapper,
                booster
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
                contracts.assetGroupRegistry,
                contracts.accessControl,
                assetGroupId,
                contracts.swapper,
                booster,
                1
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
                contracts.assetGroupRegistry,
                contracts.accessControl,
                assetGroupId,
                contracts.swapper
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
        IdleStrategy implementation = new IdleStrategy(
            contracts.assetGroupRegistry,
            contracts.accessControl,
            contracts.swapper
        );

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
                contracts.assetGroupRegistry,
                contracts.accessControl,
                assetGroupId,
                rocketSwapRouter,
                assets(WETH_KEY)
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
                contracts.assetGroupRegistry,
                contracts.accessControl,
                assetGroupId,
                lido,
                curvePool,
                assets(WETH_KEY)
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
            contracts.assetGroupRegistry,
            contracts.accessControl,
            contracts.swapper,
            notional,
            note
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
        YearnV2Strategy implementation = new YearnV2Strategy(
            contracts.assetGroupRegistry,
            contracts.accessControl
        );

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

    function deployOeth(StandardContracts memory contracts) public {
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

        _registerStrategy(OETH_HOLDING_KEY, address(implementation), proxy, assetGroupId, contracts.strategyRegistry);
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
