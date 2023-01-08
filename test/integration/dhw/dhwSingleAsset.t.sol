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

contract DhwSingleAssetTest is Test {
    address private alice;
    address private bob;

    MockToken tokenA;

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
        bob = address(0xb);

        address riskProvider = address(0x1);

        tokenA = new MockToken("Token A", "TA");

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
        IRiskManager riskManager = new RiskManager(accessControl);

        smartVaultManager = new SmartVaultManager(
            accessControl,
            strategyRegistry,
            priceFeedManager,
            assetGroupRegistry,
            masterWallet,
            new ActionManager(accessControl),
            guardManager,
            riskManager
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

            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(600, 300, 100))
            );

            mySmartVault = smartVaultFactory.deploySmartVault(
                SmartVaultSpecification({
                    smartVaultName: "MySmartVault",
                    assetGroupId: assetGroupId,
                    actions: new IAction[](0),
                    actionRequestTypes: new RequestType[](0),
                    guards: new GuardDefinition[][](0),
                    guardRequestTypes: new RequestType[](0),
                    strategies: mySmartVaultStrategies,
                    riskAppetite: 4,
                    riskProvider: riskProvider
                })
            );
        }

        priceFeedManager.setExchangeRate(address(tokenA), 1200 * 10 ** 26);
    }

    function test_dhw_twoDepositors() public {
        uint256 tokenAInitialBalanceAlice = 100 ether;

        // set initial state
        deal(address(tokenA), alice, tokenAInitialBalanceAlice, true);

        // Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmountsAlice = Arrays.toArray(tokenAInitialBalanceAlice);

        tokenA.approve(address(smartVaultManager), depositAmountsAlice[0]);

        uint256 aliceDepositNftId =
            smartVaultManager.deposit(address(mySmartVault), depositAmountsAlice, alice, address(0));

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
        vm.startPrank(alice);
        smartVaultManager.claimSmartVaultTokens(
            address(mySmartVault), Arrays.toArray(aliceDepositNftId), Arrays.toArray(NFT_MINTED_SHARES)
        );
        vm.stopPrank();

        // ======================

        uint256 tokenAInitialBalanceBob = 10 ether;

        // set initial state
        deal(address(tokenA), bob, tokenAInitialBalanceBob, true);

        // Bob deposits
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
        vm.startPrank(bob);
        smartVaultManager.claimSmartVaultTokens(
            address(mySmartVault), Arrays.toArray(bobDepositNftId), Arrays.toArray(NFT_MINTED_SHARES)
        );
        vm.stopPrank();

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

        vm.startPrank(alice);
        console2.log("claimWithdrawal");
        smartVaultManager.claimWithdrawal(
            address(mySmartVault), Arrays.toArray(aliceWithdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
        );
        vm.stopPrank();
        vm.startPrank(bob);
        smartVaultManager.claimWithdrawal(
            address(mySmartVault), Arrays.toArray(bobWithdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), bob
        );
        vm.stopPrank();

        console2.log("tokenA alice  After:", tokenA.balanceOf(alice));
        console2.log("tokenA bob    After:", tokenA.balanceOf(bob));

        assertApproxEqAbs(tokenA.balanceOf(alice), tokenAInitialBalanceAlice, 10);
        assertApproxEqAbs(tokenA.balanceOf(bob), tokenAInitialBalanceBob, 10);
    }
}
