// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../../src/managers/ActionManager.sol";
import "../../../src/managers/AssetGroupRegistry.sol";
import "../../../src/managers/GuardManager.sol";
import "../../../src/managers/RiskManager.sol";
import "../../../src/managers/SmartVaultManager.sol";
import "../../../src/managers/StrategyRegistry.sol";
import "../../../src/managers/UsdPriceFeedManager.sol";
import "../../../src/MasterWallet.sol";
import "../../../src/SmartVault.sol";
import "../../../src/SmartVaultFactory.sol";
import "../../../src/Swapper.sol";
import "../../libraries/Arrays.sol";
import "../../mocks/MockMasterChef.sol";
import "../../mocks/MockMasterChefStrategy.sol";
import "../../mocks/MockToken.sol";
import "../../mocks/MockPriceFeedManager.sol";

contract DhwMasterChefTest is Test, SpoolAccessRoles {
    address private alice;
    address private bob;

    MockToken tokenA;

    MockMasterChefStrategy strategyA;
    address[] mySmartVaultStrategies;

    ISmartVault private mySmartVault;
    SmartVaultManager private smartVaultManager;
    StrategyRegistry private strategyRegistry;
    MasterWallet private masterWallet;
    AssetGroupRegistry private assetGroupRegistry;
    SpoolAccessControl accessControl;

    function setUp() public {
        tokenA = new MockToken("Token A", "TA");
        // rewardTokenA = new MockToken("Reward Token A", "RTA");
        MockMasterChef masterChef = new MockMasterChef(address(tokenA), 0);
        masterChef.add(100, tokenA, true);

        alice = address(0xa);
        bob = address(0xb);

        address riskProvider = address(0x1);

        accessControl = new SpoolAccessControl();
        accessControl.initialize();
        masterWallet = new MasterWallet(accessControl);

        address[] memory assetGroup = new address[](1);
        assetGroup[0] = address(tokenA);
        assetGroupRegistry = new AssetGroupRegistry();
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        MockPriceFeedManager priceFeedManager = new MockPriceFeedManager();
        strategyRegistry = new StrategyRegistry(masterWallet, accessControl, priceFeedManager);
        IActionManager actionManager = new ActionManager(accessControl);
        IGuardManager guardManager = new GuardManager(accessControl);

        smartVaultManager = new SmartVaultManager(
            accessControl,
            strategyRegistry,
            priceFeedManager,
            assetGroupRegistry,
            masterWallet,
            new ActionManager(accessControl),
            guardManager
        );

        strategyA = new MockMasterChefStrategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, masterChef, 0);
        strategyRegistry.registerStrategy(address(strategyA));

        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
        accessControl.grantRole(ROLE_STRATEGY_CLAIMER, address(smartVaultManager));
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(strategyRegistry));

        {
            address smartVaultImplementation = address(new SmartVault(accessControl, guardManager));
            SmartVaultFactory smartVaultFactory = new SmartVaultFactory(
                smartVaultImplementation,
                accessControl,
                actionManager,
                guardManager,
                smartVaultManager,
                assetGroupRegistry
            );
            accessControl.grantRole(ADMIN_ROLE_SMART_VAULT, address(smartVaultFactory));
            accessControl.grantRole(ROLE_SMART_VAULT_INTEGRATOR, address(smartVaultFactory));

            mySmartVaultStrategies = Arrays.toArray(address(strategyA));

            mySmartVault = smartVaultFactory.deploySmartVault(
                SmartVaultSpecification({
                    smartVaultName: "MySmartVault",
                    assetGroupId: assetGroupId,
                    actions: new IAction[](0),
                    actionRequestTypes: new RequestType[](0),
                    guards: new GuardDefinition[][](0),
                    guardRequestTypes: new RequestType[](0),
                    strategies: mySmartVaultStrategies,
                    strategyAllocations: Arrays.toArray(1000),
                    riskProvider: riskProvider
                })
            );
        }

        priceFeedManager.setExchangeRate(address(tokenA), 1200 * 10 ** 26);
    }

    function test_dhwGenerateYield() public {
        uint256 tokenAInitialBalanceAlice = 100 ether;
        
        // set initial state
        deal(address(tokenA), alice, tokenAInitialBalanceAlice, true);

        // Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmountsAlice = Arrays.toArray(tokenAInitialBalanceAlice);

        tokenA.approve(address(smartVaultManager), depositAmountsAlice[0]);

        uint256 aliceDepositNftId = smartVaultManager.deposit(address(mySmartVault), depositAmountsAlice, alice, address(0));

        vm.stopPrank();

        // flush
        smartVaultManager.flushSmartVault(address(mySmartVault));

        // DHW - DEPOSIT
        SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](1);
        dhwSwapInfo[0] = new SwapInfo[](0);

        strategyRegistry.doHardWork(mySmartVaultStrategies, dhwSwapInfo);

        // sync vault
        smartVaultManager.syncSmartVault(address(mySmartVault));

        // claim deposit
        vm.prank(alice);
        smartVaultManager.claimSmartVaultTokens(address(mySmartVault), aliceDepositNftId);

        // ======================

        uint256 tokenAInitialBalanceBob = 10 ether;
        
        // set initial state
        deal(address(tokenA), bob, tokenAInitialBalanceBob, true);

        // Alice deposits
        vm.startPrank(bob);

        uint256[] memory depositAmountsBob = Arrays.toArray(tokenAInitialBalanceBob);

        tokenA.approve(address(smartVaultManager), depositAmountsBob[0]);

        uint256 bobDepositNftId = smartVaultManager.deposit(address(mySmartVault), depositAmountsBob, bob, address(0));

        vm.stopPrank();

        // flush
        smartVaultManager.flushSmartVault(address(mySmartVault));

        // DHW - DEPOSIT

        strategyRegistry.doHardWork(mySmartVaultStrategies, dhwSwapInfo);

        // // sync vault
        smartVaultManager.syncSmartVault(address(mySmartVault));

        // claim deposit
        vm.prank(bob);
        smartVaultManager.claimSmartVaultTokens(address(mySmartVault), bobDepositNftId);

        // ======================

        // WITHDRAW
        uint256 aliceShares = mySmartVault.balanceOf(alice);
        uint256 bobShares = mySmartVault.balanceOf(bob);
        console2.log("aliceShares Before:", aliceShares);

        vm.prank(alice);
        mySmartVault.approve(address(smartVaultManager), aliceShares);
        vm.prank(bob);
        mySmartVault.approve(address(smartVaultManager), bobShares);
        uint256 aliceWithdrawalNftId = smartVaultManager.redeem(address(mySmartVault), aliceShares, alice, alice);
        uint256 bobWithdrawalNftId = smartVaultManager.redeem(address(mySmartVault), bobShares, bob, bob);

        console2.log("flushSmartVault");
        smartVaultManager.flushSmartVault(address(mySmartVault));

        // DHW - WITHDRAW
        SwapInfo[][] memory dhwSwapInfoWithdraw = new SwapInfo[][](1);
        dhwSwapInfoWithdraw[0] = new SwapInfo[](0);
        console2.log("doHardWork");
        strategyRegistry.doHardWork(mySmartVaultStrategies, dhwSwapInfo);

        // sync vault
        console2.log("syncSmartVault");
        smartVaultManager.syncSmartVault(address(mySmartVault));

        // claim withdrawal
        console2.log("tokenA Before:", tokenA.balanceOf(alice));

        vm.prank(alice);
        console2.log("claimWithdrawal");
        smartVaultManager.claimWithdrawal(address(mySmartVault), aliceWithdrawalNftId, alice);
        vm.prank(bob);
        smartVaultManager.claimWithdrawal(address(mySmartVault), bobWithdrawalNftId, bob);

        console2.log("tokenA alice  After:", tokenA.balanceOf(alice));
        console2.log("tokenA bob    After:", tokenA.balanceOf(bob));
        
        assertApproxEqAbs(tokenA.balanceOf(alice), tokenAInitialBalanceAlice, 10);
        assertApproxEqAbs(tokenA.balanceOf(bob), tokenAInitialBalanceBob, 10);
    }
}
