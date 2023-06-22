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
import {Swapper} from "../src/Swapper.sol";
import "../src/managers/DepositManager.sol";
import "../src/managers/WithdrawalManager.sol";
import "../src/strategies/GhostStrategy.sol";
import "./helper/JsonHelper.sol";
import {ExponentialAllocationProvider} from "../src/providers/ExponentialAllocationProvider.sol";
import {LinearAllocationProvider} from "../src/providers/LinearAllocationProvider.sol";
import {UniformAllocationProvider} from "../src/providers/UniformAllocationProvider.sol";

contract DeploySpool {
    function constantsJson() internal view virtual returns (JsonReader) {}
    function contractsJson() internal view virtual returns (JsonWriter) {}

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
    AllowlistGuard public allowlistGuard;
    DepositManager public depositManager;
    WithdrawalManager public withdrawalManager;
    IStrategy public ghostStrategy;
    ExponentialAllocationProvider public exponentialAllocationProvider;
    LinearAllocationProvider public linearAllocationProvider;
    UniformAllocationProvider public uniformAllocationProvider;

    function deploySpool() public {
        TransparentUpgradeableProxy proxy;

        {
            proxyAdmin = new ProxyAdmin();

            contractsJson().add("ProxyAdmin", address(proxyAdmin));
        }

        {
            ghostStrategy = new GhostStrategy();

            contractsJson().add("GhostStrategy", address(ghostStrategy));
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
            StrategyRegistry implementation = new StrategyRegistry(
                masterWallet,
                spoolAccessControl,
                usdPriceFeedManager,
                address(ghostStrategy)
            );
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
            DepositManager implementation =
            new DepositManager(strategyRegistry, usdPriceFeedManager, guardManager, actionManager, spoolAccessControl, masterWallet, address(ghostStrategy));
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
            rewardManager.initialize();

            contractsJson().addProxy("RewardManager", address(implementation), address(proxy));
        }

        {
            DepositSwap implementation = new DepositSwap(
                IWETH9(constantsJson().getAddress(".assets/weth")),
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

            spoolAccessControl.grantRole(ROLE_SMART_VAULT_INTEGRATOR, address(smartVaultFactory));
            spoolAccessControl.grantRole(ADMIN_ROLE_SMART_VAULT_ALLOW_REDEEM, address(smartVaultFactory));

            contractsJson().add("SmartVaultFactory", address(smartVaultFactory));
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
            allowlistGuard = new AllowlistGuard(spoolAccessControl);

            contractsJson().add("AllowlistGuard", address(allowlistGuard));
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

    function test_mock_DeploySpool() external pure {}
}
