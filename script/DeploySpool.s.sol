// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/access/Roles.sol";
import {IWETH9} from "../src/external/interfaces/weth/IWETH9.sol";
import {SpoolAccessControl} from "../src/access/SpoolAccessControl.sol";
import {AllowlistGuard} from "../src/guards/AllowlistGuard.sol";
import {ActionManager} from "../src/managers/ActionManager.sol";
import {AssetGroupRegistry} from "../src/managers/AssetGroupRegistry.sol";
import {GuardManager} from "../src/managers/GuardManager.sol";
import {RewardManager} from "../src/rewards/RewardManager.sol";
import {RiskManager} from "../src/managers/RiskManager.sol";
import {SmartVaultManager} from "../src/managers/SmartVaultManager.sol";
import {StrategyRegistry} from "../src/managers/StrategyRegistry.sol";
import {UsdPriceFeedManager} from "../src/managers/UsdPriceFeedManager.sol";
import {DepositSwap} from "../src/DepositSwap.sol";
import {MasterWallet} from "../src/MasterWallet.sol";
import {SmartVault} from "../src/SmartVault.sol";
import {SmartVaultFactory} from "../src/SmartVaultFactory.sol";
import {SmartVaultFactoryHpf} from "../src/SmartVaultFactoryHpf.sol";
import {Swapper} from "../src/Swapper.sol";
import {SpoolLens} from "../src/SpoolLens.sol";
import {MetaVaultGuard} from "../src/MetaVaultGuard.sol";
import {MetaVaultFactory} from "../src/MetaVaultFactory.sol";
import {SpoolMulticall} from "../src/SpoolMulticall.sol";
import {MetaVault} from "../src/MetaVault.sol";
import "../src/managers/DepositManager.sol";
import "../src/managers/WithdrawalManager.sol";
import "../src/strategies/GhostStrategy.sol";
import "./helper/JsonHelper.sol";
import {ExponentialAllocationProvider} from "../src/providers/ExponentialAllocationProvider.sol";
import {LinearAllocationProvider} from "../src/providers/LinearAllocationProvider.sol";
import {UniformAllocationProvider} from "../src/providers/UniformAllocationProvider.sol";

contract DeploySpool {
    function constantsJson() internal view virtual returns (JsonReader) {}
    function contractsJson() internal view virtual returns (JsonReadWriter) {}

    ProxyAdmin public proxyAdmin;
    SpoolAccessControl public spoolAccessControl;
    Swapper public swapper;
    MasterWallet public masterWallet;
    ActionManager public actionManager;
    AssetGroupRegistry public assetGroupRegistry;
    GuardManager public guardManager;
    RewardManager public rewardManager;
    RiskManager public riskManager;
    UsdPriceFeedManager public usdPriceFeedManager;
    StrategyRegistry public strategyRegistry;
    SmartVaultManager public smartVaultManager;
    DepositSwap public depositSwap;
    SmartVaultFactory public smartVaultFactory;
    SmartVaultFactoryHpf public smartVaultFactoryHpf;
    AllowlistGuard public allowlistGuard;
    DepositManager public depositManager;
    WithdrawalManager public withdrawalManager;
    IStrategy public ghostStrategy;
    ExponentialAllocationProvider public exponentialAllocationProvider;
    LinearAllocationProvider public linearAllocationProvider;
    UniformAllocationProvider public uniformAllocationProvider;
    SpoolLens public spoolLens;
    MetaVaultGuard public metaVaultGuard;
    MetaVaultFactory public metaVaultFactory;

    function deploySpool() public {
        TransparentUpgradeableProxy proxy;

        {
            proxyAdmin = new ProxyAdmin();

            contractsJson().add("ProxyAdmin", address(proxyAdmin));
        }

        {
            GhostStrategy implementation = new GhostStrategy();
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            ghostStrategy = IStrategy(address(proxy));

            contractsJson().addProxy("GhostStrategy", address(implementation), address(proxy));
        }

        {
            SpoolAccessControl implementation = new SpoolAccessControl();
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            spoolAccessControl = SpoolAccessControl(address(proxy));
            spoolAccessControl.initialize();

            contractsJson().addProxy("SpoolAccessControl", address(implementation), address(proxy));
        }

        {
            Swapper implementation = new Swapper(spoolAccessControl);
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            swapper = Swapper(address(proxy));

            contractsJson().addProxy("Swapper", address(implementation), address(proxy));
        }

        {
            MasterWallet implementation = new MasterWallet(spoolAccessControl);
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            masterWallet = MasterWallet(address(proxy));

            contractsJson().addProxy("MasterWallet", address(implementation), address(proxy));
        }

        {
            ActionManager implementation = new ActionManager(spoolAccessControl);
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            actionManager = ActionManager(address(proxy));

            contractsJson().addProxy("ActionManager", address(implementation), address(proxy));
        }

        {
            GuardManager implementation = new GuardManager(spoolAccessControl);
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            guardManager = GuardManager(address(proxy));

            contractsJson().addProxy("GuardManager", address(implementation), address(proxy));
        }

        {
            AssetGroupRegistry implementation = new AssetGroupRegistry(spoolAccessControl);
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            assetGroupRegistry = AssetGroupRegistry(address(proxy));
            assetGroupRegistry.initialize(new address[](0));

            contractsJson().addProxy("AssetGroupRegistry", address(implementation), address(proxy));
        }

        {
            UsdPriceFeedManager implementation = new UsdPriceFeedManager(spoolAccessControl);
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            usdPriceFeedManager = UsdPriceFeedManager(address(proxy));

            contractsJson().addProxy("UsdPriceFeedManager", address(implementation), address(proxy));
        }

        {
            StrategyRegistry implementation =
                new StrategyRegistry(masterWallet, spoolAccessControl, usdPriceFeedManager, address(ghostStrategy));
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            strategyRegistry = StrategyRegistry(address(proxy));
            strategyRegistry.initialize(
                uint96(constantsJson().getUint256(".fees.ecosystemFeePct")),
                uint96(constantsJson().getUint256(".fees.treasuryFeePct")),
                constantsJson().getAddress(".fees.ecosystemFeeReceiver"),
                constantsJson().getAddress(".fees.treasuryFeeReceiver"),
                constantsJson().getAddress(".emergencyWithdrawalWallet")
            );

            spoolAccessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(strategyRegistry));
            spoolAccessControl.grantRole(ADMIN_ROLE_STRATEGY, address(strategyRegistry));
            spoolAccessControl.grantRole(ROLE_STRATEGY_REGISTRY, address(strategyRegistry));

            contractsJson().addProxy("StrategyRegistry", address(implementation), address(proxy));
        }

        {
            RiskManager implementation = new RiskManager(spoolAccessControl, strategyRegistry, address(ghostStrategy));
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            riskManager = RiskManager(address(proxy));

            contractsJson().addProxy("RiskManager", address(implementation), address(proxy));
        }

        {
            DepositManager implementation = new DepositManager(
                strategyRegistry,
                usdPriceFeedManager,
                guardManager,
                actionManager,
                spoolAccessControl,
                masterWallet,
                address(ghostStrategy)
            );
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            depositManager = DepositManager(address(proxy));

            spoolAccessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(depositManager));
            spoolAccessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(depositManager));

            contractsJson().addProxy("DepositManager", address(implementation), address(proxy));
        }

        {
            WithdrawalManager implementation =
                new WithdrawalManager(strategyRegistry, masterWallet, guardManager, actionManager, spoolAccessControl);
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            withdrawalManager = WithdrawalManager(address(proxy));

            spoolAccessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(withdrawalManager));
            spoolAccessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(withdrawalManager));

            contractsJson().addProxy("WithdrawalManager", address(implementation), address(proxy));
        }

        {
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
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            smartVaultManager = SmartVaultManager(address(proxy));

            spoolAccessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(smartVaultManager));
            spoolAccessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(smartVaultManager));

            contractsJson().addProxy("SmartVaultManager", address(implementation), address(proxy));
        }

        {
            RewardManager implementation = new RewardManager(spoolAccessControl, assetGroupRegistry, false);
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            rewardManager = RewardManager(address(proxy));

            contractsJson().addProxy("RewardManager", address(implementation), address(proxy));
        }

        {
            DepositSwap implementation = new DepositSwap(
                IWETH9(constantsJson().getAddress(".assets.weth.address")),
                assetGroupRegistry,
                smartVaultManager,
                swapper
            );
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            depositSwap = DepositSwap(address(proxy));

            spoolAccessControl.grantRole(ROLE_SWAPPER, address(depositSwap));

            contractsJson().addProxy("DepositSwap", address(implementation), address(proxy));
        }

        {
            SmartVault smartVaultImplementation = new SmartVault(spoolAccessControl, guardManager);

            smartVaultFactory = new SmartVaultFactory(
                address(smartVaultImplementation),
                spoolAccessControl,
                actionManager,
                guardManager,
                smartVaultManager,
                assetGroupRegistry,
                riskManager
            );

            smartVaultFactoryHpf = new SmartVaultFactoryHpf(
                address(smartVaultImplementation),
                spoolAccessControl,
                actionManager,
                guardManager,
                smartVaultManager,
                assetGroupRegistry,
                riskManager
            );

            spoolAccessControl.grantRole(ROLE_SMART_VAULT_INTEGRATOR, address(smartVaultFactory));
            spoolAccessControl.grantRole(ROLE_SMART_VAULT_INTEGRATOR, address(smartVaultFactoryHpf));

            spoolAccessControl.grantRole(ADMIN_ROLE_SMART_VAULT_ALLOW_REDEEM, address(smartVaultFactory));
            spoolAccessControl.grantRole(ADMIN_ROLE_SMART_VAULT_ALLOW_REDEEM, address(smartVaultFactoryHpf));

            contractsJson().add("SmartVaultFactory", address(smartVaultFactory));
            contractsJson().add("SmartVaultFactoryHpf", address(smartVaultFactoryHpf));
        }

        {
            ExponentialAllocationProvider implementation = new ExponentialAllocationProvider();
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            exponentialAllocationProvider = ExponentialAllocationProvider(address(proxy));

            contractsJson().addProxy("ExponentialAllocationProvider", address(implementation), address(proxy));

            spoolAccessControl.grantRole(ROLE_ALLOCATION_PROVIDER, address(exponentialAllocationProvider));
        }

        {
            LinearAllocationProvider implementation = new LinearAllocationProvider();
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            linearAllocationProvider = LinearAllocationProvider(address(proxy));

            contractsJson().addProxy("LinearAllocationProvider", address(implementation), address(proxy));

            spoolAccessControl.grantRole(ROLE_ALLOCATION_PROVIDER, address(linearAllocationProvider));
        }

        {
            UniformAllocationProvider implementation = new UniformAllocationProvider();
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            uniformAllocationProvider = UniformAllocationProvider(address(proxy));

            contractsJson().addProxy("UniformAllocationProvider", address(implementation), address(proxy));

            spoolAccessControl.grantRole(ROLE_ALLOCATION_PROVIDER, address(uniformAllocationProvider));
        }

        {
            AllowlistGuard implementation = new AllowlistGuard(spoolAccessControl);
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            allowlistGuard = AllowlistGuard(address(proxy));

            contractsJson().addProxy("AllowlistGuard", address(implementation), address(proxy));
        }

        {
            SpoolLens implementation = new SpoolLens(
                spoolAccessControl,
                assetGroupRegistry,
                riskManager,
                depositManager,
                withdrawalManager,
                strategyRegistry,
                masterWallet,
                usdPriceFeedManager,
                smartVaultManager,
                address(ghostStrategy)
            );
            proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
            spoolLens = SpoolLens(address(proxy));

            contractsJson().addProxy("SpoolLens", address(implementation), address(spoolLens));
        }

        {
            address spoolMulticall = address(new SpoolMulticall(spoolAccessControl));
            contractsJson().add("SpoolMulticall", spoolMulticall);
        }

        {
            address implementation = address(new MetaVaultGuard(smartVaultManager, assetGroupRegistry, guardManager));
            proxy = new TransparentUpgradeableProxy(implementation, address(proxyAdmin), "");
            metaVaultGuard = MetaVaultGuard(address(proxy));
            contractsJson().addProxy("MetaVaultGuard", implementation, address(proxy));
        }

        {
            address implementation =
                address(new MetaVault(smartVaultManager, spoolAccessControl, metaVaultGuard, spoolLens));
            metaVaultFactory = new MetaVaultFactory(implementation, spoolAccessControl, assetGroupRegistry);

            contractsJson().add("MetaVaultImplementation", implementation);
            contractsJson().add("MetaVaultFactory", address(metaVaultFactory));
        }
    }

    function postDeploySpool(address deployerAddress) public virtual {
        {
            // transfer ownership of ProxyAdmin
            address proxyAdminOwner = constantsJson().getAddress(".proxyAdminOwner");
            proxyAdmin.transferOwnership(proxyAdminOwner);

            // transfer ROLE_SPOOL_ADMIN
            address spoolAdmin = constantsJson().getAddress(".spoolAdmin");
            spoolAccessControl.grantRole(ROLE_SPOOL_ADMIN, spoolAdmin);
        }

        spoolAccessControl.renounceRole(ROLE_SPOOL_ADMIN, deployerAddress);
    }

    function loadSpool() public {
        proxyAdmin = ProxyAdmin(contractsJson().getAddress(".ProxyAdmin"));
        spoolAccessControl = SpoolAccessControl(contractsJson().getAddress(".SpoolAccessControl.proxy"));
        swapper = Swapper(contractsJson().getAddress(".Swapper.proxy"));
        masterWallet = MasterWallet(contractsJson().getAddress(".MasterWallet.proxy"));
        actionManager = ActionManager(contractsJson().getAddress(".ActionManager.proxy"));
        assetGroupRegistry = AssetGroupRegistry(contractsJson().getAddress(".AssetGroupRegistry.proxy"));
        guardManager = GuardManager(contractsJson().getAddress(".GuardManager.proxy"));
        rewardManager = RewardManager(contractsJson().getAddress(".RewardManager.proxy"));
        riskManager = RiskManager(contractsJson().getAddress(".RiskManager.proxy"));
        usdPriceFeedManager = UsdPriceFeedManager(contractsJson().getAddress(".UsdPriceFeedManager.proxy"));
        strategyRegistry = StrategyRegistry(contractsJson().getAddress(".StrategyRegistry.proxy"));
        smartVaultManager = SmartVaultManager(contractsJson().getAddress(".SmartVaultManager.proxy"));
        depositSwap = DepositSwap(contractsJson().getAddress(".DepositSwap.proxy"));
        smartVaultFactory = SmartVaultFactory(contractsJson().getAddress(".SmartVaultFactory"));
        smartVaultFactoryHpf = SmartVaultFactoryHpf(contractsJson().getAddress(".SmartVaultFactoryHpf"));
        allowlistGuard = AllowlistGuard(contractsJson().getAddress(".AllowlistGuard.proxy"));
        depositManager = DepositManager(contractsJson().getAddress(".DepositManager.proxy"));
        withdrawalManager = WithdrawalManager(contractsJson().getAddress(".WithdrawalManager.proxy"));
        ghostStrategy = IStrategy(contractsJson().getAddress(".GhostStrategy.proxy"));
        exponentialAllocationProvider =
            ExponentialAllocationProvider(contractsJson().getAddress(".ExponentialAllocationProvider.proxy"));
        linearAllocationProvider =
            LinearAllocationProvider(contractsJson().getAddress(".LinearAllocationProvider.proxy"));
        uniformAllocationProvider =
            UniformAllocationProvider(contractsJson().getAddress(".UniformAllocationProvider.proxy"));
        spoolLens = SpoolLens(contractsJson().getAddress(".SpoolLens.proxy"));
        metaVaultGuard = MetaVaultGuard(contractsJson().getAddress(".MetaVaultGuard.proxy"));
        metaVaultFactory = MetaVaultFactory(contractsJson().getAddress(".MetaVaultFactory"));
    }

    function test_mock_DeploySpool() external pure {}
}
