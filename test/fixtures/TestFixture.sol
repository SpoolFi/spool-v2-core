// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../mocks/MockGuard.sol";
import "../mocks/MockToken.sol";
import "../mocks/MockPriceFeedManager.sol";
import "../../src/managers/GuardManager.sol";
import "../../src/managers/SmartVaultManager.sol";
import "../../src/managers/ActionManager.sol";
import "../../src/managers/AssetGroupRegistry.sol";
import "../../src/MasterWallet.sol";
import "../../src/managers/StrategyRegistry.sol";
import "../../src/managers/RiskManager.sol";
import "../../src/managers/DepositManager.sol";
import "../../src/managers/WithdrawalManager.sol";
import "../integration/withdrawal.t.sol";
import "../../src/providers/UniformAllocationProvider.sol";

contract TestFixture is Test {
    address internal riskProvider = address(0x1);

    MockGuard internal guard;
    MockToken internal token;
    Swapper internal swapper;
    GuardManager internal guardManager;
    ISmartVault internal smartVault;
    SmartVaultManager internal smartVaultManager;
    IDepositManager internal depositManager;
    IWithdrawalManager internal withdrawalManager;
    SpoolAccessControl internal accessControl;
    IRiskManager internal riskManager;
    AssetGroupRegistry internal assetGroupRegistry;
    ActionManager internal actionManager;
    StrategyRegistry internal strategyRegistry;
    MockPriceFeedManager internal priceFeedManager;
    MasterWallet internal masterWallet;
    IAllocationProvider internal allocationProvider;

    function setUpBase() public virtual {
        token = new MockToken("Token", "T");
        guard = new MockGuard();

        accessControl = new SpoolAccessControl();
        accessControl.initialize();
        swapper = new Swapper(accessControl);
        actionManager = new ActionManager(accessControl);
        assetGroupRegistry = new AssetGroupRegistry(accessControl);
        assetGroupRegistry.initialize(Arrays.toArray(address(token)));
        guardManager = new GuardManager(accessControl);
        masterWallet = new MasterWallet(accessControl);
        priceFeedManager = new MockPriceFeedManager();
        strategyRegistry = new StrategyRegistry(masterWallet, accessControl, priceFeedManager);
        riskManager = new RiskManager(accessControl);
        allocationProvider = new UniformAllocationProvider();
        depositManager =
            new DepositManager(strategyRegistry, priceFeedManager, guardManager, actionManager, accessControl);

        withdrawalManager =
        new WithdrawalManager(strategyRegistry, priceFeedManager, masterWallet, guardManager, actionManager, accessControl);
        smartVaultManager = new SmartVaultManager(
            accessControl,
            assetGroupRegistry,
            riskManager,
            depositManager,
            withdrawalManager,
            strategyRegistry,
            masterWallet,
            priceFeedManager
        );

        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(depositManager));
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(withdrawalManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(depositManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(withdrawalManager));
        accessControl.grantRole(ROLE_STRATEGY_CLAIMER, address(smartVaultManager));
        accessControl.grantRole(ROLE_STRATEGY_CLAIMER, address(withdrawalManager));
        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
        accessControl.grantRole(ROLE_ALLOCATION_PROVIDER, address(allocationProvider));
    }
}
