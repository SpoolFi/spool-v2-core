// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "./MockGuard.sol";
import "./MockToken.sol";
import "../../src/managers/GuardManager.sol";
import "../../src/managers/SmartVaultManager.sol";
import "../../src/managers/ActionManager.sol";
import "../../src/managers/AssetGroupRegistry.sol";
import "../../src/MasterWallet.sol";
import "../../src/managers/StrategyRegistry.sol";
import "./MockPriceFeedManager.sol";
import "../../src/managers/RiskManager.sol";

contract BaseTestContracts {
    address internal riskProvider = address(0x1);

    MockGuard internal guard;
    MockToken internal token;
    GuardManager internal guardManager;
    ISmartVault internal smartVault;
    SmartVaultManager internal smartVaultManager;
    IDepositManager internal depositManager;
    SpoolAccessControl internal accessControl;
    IRiskManager internal riskManager;
    AssetGroupRegistry internal assetGroupRegistry;
    ActionManager internal actionManager;
    StrategyRegistry internal strategyRegistry;
    MockPriceFeedManager internal priceFeedManager;
    MasterWallet internal masterWallet;

    function setUpBase() public {
        token = new MockToken("Token", "T");
        guard = new MockGuard();

        accessControl = new SpoolAccessControl();
        accessControl.initialize();
        actionManager = new ActionManager(accessControl);
        assetGroupRegistry = new AssetGroupRegistry(accessControl);
        assetGroupRegistry.initialize(Arrays.toArray(address(token)));
        guardManager = new GuardManager(accessControl);
        masterWallet = new MasterWallet(accessControl);
        priceFeedManager = new MockPriceFeedManager();
        strategyRegistry = new StrategyRegistry(masterWallet, accessControl, priceFeedManager);
        riskManager = new RiskManager(accessControl);
        depositManager =
            new DepositManager(strategyRegistry, priceFeedManager, masterWallet, guardManager, actionManager);

        smartVaultManager = new SmartVaultManager(
            accessControl,
            strategyRegistry,
            assetGroupRegistry,
            masterWallet,
            actionManager,
            guardManager,
            riskManager,
            depositManager
        );

        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(depositManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(depositManager));
        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
    }
}
