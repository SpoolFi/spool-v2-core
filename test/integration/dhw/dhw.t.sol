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
import "../../mocks/MockStrategy.sol";
import "../../mocks/MockToken.sol";
import "../../mocks/MockPriceFeedManager.sol";

contract DhwTest is Test, SpoolAccessRoles {
    address private alice;

    MockToken tokenA;
    MockToken tokenB;
    MockToken tokenC;

    MockStrategy strategyA;
    MockStrategy strategyB;
    MockStrategy strategyC;
    address[] mySmartVaultStrategies;

    ISmartVault private mySmartVault;
    SmartVaultManager private smartVaultManager;
    StrategyRegistry private strategyRegistry;
    MasterWallet private masterWallet;
    AssetGroupRegistry private assetGroupRegistry;
    SpoolAccessControl accessControl;

    function setUp() public {
        alice = address(0xa);

        address riskProvider = address(0x1);

        tokenA = new MockToken("Token A", "TA");
        tokenB = new MockToken("Token B", "TB");
        tokenC = new MockToken("Token C", "TC");

        accessControl = new SpoolAccessControl();
        accessControl.initialize();
        masterWallet = new MasterWallet(accessControl);

        address[] memory assetGroup = new address[](3);
        assetGroup[0] = address(tokenA);
        assetGroup[1] = address(tokenB);
        assetGroup[2] = address(tokenC);
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

        strategyA = new MockStrategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, new Swapper());
        uint256[] memory strategyRatios = new uint256[](3);
        strategyRatios[0] = 1000;
        strategyRatios[1] = 71;
        strategyRatios[2] = 4300;
        strategyA.initialize(assetGroupId, strategyRatios);
        strategyRegistry.registerStrategy(address(strategyA));

        strategyRatios[1] = 74;
        strategyRatios[2] = 4500;
        strategyB = new MockStrategy("StratB", strategyRegistry, assetGroupRegistry, accessControl, new Swapper());
        strategyB.initialize(assetGroupId, strategyRatios);
        strategyRegistry.registerStrategy(address(strategyB));

        strategyRatios[1] = 76;
        strategyRatios[2] = 4600;
        strategyC = new MockStrategy("StratC", strategyRegistry, assetGroupRegistry, accessControl, new Swapper());
        strategyC.initialize(assetGroupId, strategyRatios);
        strategyRegistry.registerStrategy(address(strategyC));

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

            mySmartVaultStrategies = Arrays.toArray(address(strategyA), address(strategyB), address(strategyC));

            mySmartVault = smartVaultFactory.deploySmartVault(
                SmartVaultSpecification({
                    smartVaultName: "MySmartVault",
                    assetGroupId: assetGroupId,
                    actions: new IAction[](0),
                    actionRequestTypes: new RequestType[](0),
                    guards: new GuardDefinition[][](0),
                    guardRequestTypes: new RequestType[](0),
                    strategies: mySmartVaultStrategies,
                    strategyAllocations: Arrays.toArray(600, 300, 100),
                    riskProvider: riskProvider
                })
            );
        }

        priceFeedManager.setExchangeRate(address(tokenA), 1200 * 10 ** 26);
        priceFeedManager.setExchangeRate(address(tokenB), 16400 * 10 ** 26);
        priceFeedManager.setExchangeRate(address(tokenC), 270 * 10 ** 26);
    }

    function test_dhwSimple() public {
        uint256 tokenAInitialBalance = 100 ether;
        uint256 tokenBInitialBalance = 10 ether;
        uint256 tokenCInitialBalance = 500 ether;
        
        // set initial state
        deal(address(tokenA), alice, tokenAInitialBalance, true);
        deal(address(tokenB), alice, tokenBInitialBalance, true);
        deal(address(tokenC), alice, tokenCInitialBalance, true);

        // Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        uint256 aliceDepositNftId = smartVaultManager.deposit(address(mySmartVault), depositAmounts, alice, address(0));

        vm.stopPrank();

        // flush
        smartVaultManager.flushSmartVault(address(mySmartVault));

        // DHW - DEPOSIT
        SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](3);
        dhwSwapInfo[0] = new SwapInfo[](0);
        dhwSwapInfo[1] = new SwapInfo[](0);
        dhwSwapInfo[2] = new SwapInfo[](0);

        strategyRegistry.doHardWork(mySmartVaultStrategies, dhwSwapInfo);

        // sync vault
        smartVaultManager.syncSmartVault(address(mySmartVault));

        // claim deposit
        vm.prank(alice);
        smartVaultManager.claimSmartVaultTokens(address(mySmartVault), aliceDepositNftId);


        // WITHDRAW
        uint256 aliceShares = mySmartVault.balanceOf(alice);
        console2.log("aliceShares Before:", aliceShares);

        vm.prank(alice);
        mySmartVault.approve(address(smartVaultManager), aliceShares);
        uint256 aliceWithdrawalNftId = smartVaultManager.redeem(address(mySmartVault), aliceShares, alice, alice);

        console2.log("flushSmartVault");
        smartVaultManager.flushSmartVault(address(mySmartVault));

        // DHW - WITHDRAW
        SwapInfo[][] memory dhwSwapInfoWithdraw = new SwapInfo[][](3);
        dhwSwapInfoWithdraw[0] = new SwapInfo[](0);
        dhwSwapInfoWithdraw[1] = new SwapInfo[](0);
        dhwSwapInfoWithdraw[2] = new SwapInfo[](0);
        console2.log("doHardWork");
        strategyRegistry.doHardWork(mySmartVaultStrategies, dhwSwapInfo);

        // sync vault
        console2.log("syncSmartVault");
        smartVaultManager.syncSmartVault(address(mySmartVault));

        // claim withdrawal
        console2.log("tokenA Before:", tokenA.balanceOf(alice));
        console2.log("tokenB Before:", tokenB.balanceOf(alice));
        console2.log("tokenC Before:", tokenC.balanceOf(alice));

        vm.prank(alice);
        console2.log("claimWithdrawal");
        smartVaultManager.claimWithdrawal(address(mySmartVault), aliceWithdrawalNftId, alice);

        console2.log("tokenA After:", tokenA.balanceOf(alice));
        console2.log("tokenB After:", tokenB.balanceOf(alice));
        console2.log("tokenC After:", tokenC.balanceOf(alice));
        
        assertEq(tokenA.balanceOf(alice), tokenAInitialBalance);
        assertEq(tokenB.balanceOf(alice), tokenBInitialBalance);
        assertEq(tokenC.balanceOf(alice), tokenCInitialBalance);
    }
}
