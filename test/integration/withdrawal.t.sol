// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/managers/ActionManager.sol";
import "../../src/managers/AssetGroupRegistry.sol";
import "../../src/managers/GuardManager.sol";
import "../../src/managers/RiskManager.sol";
import "../../src/managers/SmartVaultManager.sol";
import "../../src/managers/StrategyRegistry.sol";
import "../../src/managers/UsdPriceFeedManager.sol";
import "../../src/MasterWallet.sol";
import "../../src/SmartVault.sol";
import "../../src/Swapper.sol";
import "../mocks/MockStrategy.sol";
import "../mocks/MockToken.sol";
import "../mocks/MockPriceFeedManager.sol";

contract WithdrawalIntegrationTest is Test, SpoolAccessRoles {
    address private alice;
    address private bob;

    MockToken tokenA;
    MockToken tokenB;

    MockStrategy strategyA;
    MockStrategy strategyB;
    address[] mySmartVaultStrategies;

    SmartVault private mySmartVault;
    SmartVaultManager private smartVaultManager;
    StrategyRegistry private strategyRegistry;
    MasterWallet private masterWallet;
    AssetGroupRegistry private assetGroupRegistry;
    ISpoolAccessControl accessControl;

    function setUp() public {
        alice = address(0xa);
        bob = address(0xb);

        address riskProvider = address(0x1);

        tokenA = new MockToken("Token A", "TA");
        tokenB = new MockToken("Token B", "TB");

        accessControl = new SpoolAccessControl();
        masterWallet = new MasterWallet(accessControl);

        address[] memory assetGroup = new address[](2);
        assetGroup[0] = address(tokenA);
        assetGroup[1] = address(tokenB);
        assetGroupRegistry = new AssetGroupRegistry();
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        IUsdPriceFeedManager priceFeedManager = new MockPriceFeedManager();
        strategyRegistry = new StrategyRegistry(masterWallet, accessControl, priceFeedManager);

        smartVaultManager = new SmartVaultManager(
            accessControl,
            strategyRegistry,
            priceFeedManager,
            assetGroupRegistry,
            masterWallet,
            new ActionManager(accessControl),
            new GuardManager(accessControl),
            new Swapper()
        );

        strategyA = new MockStrategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, new Swapper());
        uint256[] memory strategyRatios = new uint256[](2);
        strategyRatios[0] = 1_000;
        strategyRatios[1] = 68;
        strategyA.initialize(assetGroupId, strategyRatios);
        strategyRegistry.registerStrategy(address(strategyA));

        strategyRatios[1] = 67;
        strategyB = new MockStrategy("StratB", strategyRegistry, assetGroupRegistry, accessControl, new Swapper());
        strategyB.initialize(assetGroupId, strategyRatios);
        strategyRegistry.registerStrategy(address(strategyB));

        mySmartVault = new SmartVault("MySmartVault", accessControl);
        mySmartVault.initialize();
        accessControl.grantRole(ROLE_SMART_VAULT, address(mySmartVault));

        mySmartVaultStrategies = new address[](2);
        mySmartVaultStrategies[0] = address(strategyA);
        mySmartVaultStrategies[1] = address(strategyB);

        uint256[] memory mySmartVaultStrategyAllocations = new uint256[](2);
        mySmartVaultStrategyAllocations[0] = 400;
        mySmartVaultStrategyAllocations[1] = 600;

        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
        accessControl.grantRole(ROLE_STRATEGY_CLAIMER, address(smartVaultManager));
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(strategyRegistry));

        SmartVaultRegistrationForm memory registrationForm = SmartVaultRegistrationForm({
            assetGroupId: assetGroupId,
            strategies: mySmartVaultStrategies,
            strategyAllocations: mySmartVaultStrategyAllocations,
            riskProvider: riskProvider
        });

        smartVaultManager.registerSmartVault(address(mySmartVault), registrationForm);
    }

    function test_shouldBeAbleToWithdraw() public {
        // set initial state
        deal(address(mySmartVault), alice, 4_000_000, true);
        deal(address(mySmartVault), bob, 1_000_000, true);
        deal(address(strategyA), address(mySmartVault), 40_000_000, true);
        deal(address(strategyB), address(mySmartVault), 10_000_000, true);
        deal(address(tokenA), address(strategyA.protocol()), 40 ether, true);
        deal(address(tokenB), address(strategyA.protocol()), 2.72 ether, true);
        deal(address(tokenA), address(strategyB.protocol()), 10 ether, true);
        deal(address(tokenB), address(strategyB.protocol()), 0.67 ether, true);

        // request withdrawal
        vm.prank(alice);
        mySmartVault.approve(address(smartVaultManager), 4_000_000);
        uint256 aliceWithdrawalNftId = smartVaultManager.redeem(address(mySmartVault), 3_000_000, alice, alice);

        vm.prank(bob);
        mySmartVault.approve(address(smartVaultManager), 1_000_000);
        uint256 bobWithdrawalNftId = smartVaultManager.redeem(address(mySmartVault), 200_000, bob, bob);

        // check state
        // - vault tokens are returned to vault
        assertEq(mySmartVault.balanceOf(alice), 1_000_000, "1");
        assertEq(mySmartVault.balanceOf(bob), 800_000, "2");
        assertEq(mySmartVault.balanceOf(address(mySmartVault)), 3_200_000, "3");
        // - withdrawal NFTs are minted
        assertEq(aliceWithdrawalNftId, 2 ** 255 + 1, "4");
        assertEq(bobWithdrawalNftId, 2 ** 255 + 2, "5");
        assertEq(mySmartVault.balanceOf(alice, aliceWithdrawalNftId), 1, "6");
        assertEq(mySmartVault.balanceOf(bob, bobWithdrawalNftId), 1, "7");

        // flush
        smartVaultManager.flushSmartVault(address(mySmartVault));

        // check state
        // - vault tokens are burned
        assertEq(mySmartVault.balanceOf(address(mySmartVault)), 0, "8");
        // - strategy tokens are returned to strategies
        assertEq(strategyA.balanceOf(address(mySmartVault)), 14_400_000, "9");
        assertEq(strategyB.balanceOf(address(mySmartVault)), 3_600_000, "10");
        assertEq(strategyA.balanceOf(address(strategyA)), 25_600_000, "11");
        assertEq(strategyB.balanceOf(address(strategyB)), 6_400_000, "12");

        // DHW

        SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](2);
        dhwSwapInfo[0] = new SwapInfo[](0);
        dhwSwapInfo[1] = new SwapInfo[](0);

        strategyRegistry.doHardWork(mySmartVaultStrategies, dhwSwapInfo);

        // check state
        // - strategy tokens are burned
        assertEq(strategyA.balanceOf(address(strategyA)), 0, "13");
        assertEq(strategyB.balanceOf(address(strategyB)), 0, "14");
        // - assets are withdrawn from protocol master wallet
        assertEq(tokenA.balanceOf(address(masterWallet)), 32 ether, "15");
        assertEq(tokenB.balanceOf(address(masterWallet)), 2.1696 ether, "16");
        assertEq(tokenA.balanceOf(address(strategyA)), 0, "17");
        assertEq(tokenB.balanceOf(address(strategyA)), 0, "18");
        assertEq(tokenA.balanceOf(address(strategyB)), 0, "19");
        assertEq(tokenB.balanceOf(address(strategyB)), 0, "20");

        // sync vault
        smartVaultManager.syncSmartVault(address(mySmartVault));

        // check state
        // nothing to check

        // claim withdrawal
        vm.prank(alice);
        smartVaultManager.claimWithdrawal(address(mySmartVault), aliceWithdrawalNftId, alice);

        vm.prank(bob);
        smartVaultManager.claimWithdrawal(address(mySmartVault), bobWithdrawalNftId, bob);

        // check state
        // - assets are transfered to withdrawers
        assertEq(tokenA.balanceOf(alice), 30 ether, "21");
        assertEq(tokenB.balanceOf(alice), 2.034 ether, "22");
        assertEq(tokenA.balanceOf(bob), 2 ether, "23");
        assertEq(tokenB.balanceOf(bob), 0.1356 ether, "24");
        assertEq(tokenA.balanceOf(address(masterWallet)), 0, "25");
        assertEq(tokenB.balanceOf(address(masterWallet)), 0, "26");
        // - withdrawal NFTs are burned
        assertEq(mySmartVault.balanceOf(alice, aliceWithdrawalNftId), 0, "27");
        assertEq(mySmartVault.balanceOf(bob, bobWithdrawalNftId), 0, "28");
    }
}
