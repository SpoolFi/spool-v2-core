// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

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
import "../mocks/MockStrategy.sol";
import "../mocks/MockToken.sol";

contract WithdrawalIntegrationTest is Test {
    address private alice = address(0xa);
    address private bob = address(0xb);

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

    function setUp() public {
        tokenA = new MockToken("Token A", "TA");
        tokenB = new MockToken("Token B", "TB");

        masterWallet = new MasterWallet();

        address[] memory assetGroup = new address[](2);
        assetGroup[0] = address(tokenA);
        assetGroup[1] = address(tokenB);
        assetGroupRegistry = new AssetGroupRegistry();
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        GuardDefinition[] memory emptyGuards = new GuardDefinition[](0);
        IAction[] memory emptyActions = new IAction[](0);
        RequestType[] memory emptyActionsRequestTypes = new RequestType[](0);

        strategyRegistry = new StrategyRegistry(masterWallet);
        strategyRegistry.initialize();
        GuardManager guardManager = new GuardManager();
        ActionManager actionManager = new ActionManager();
        RiskManager riskManager = new RiskManager();
        UsdPriceFeedManager priceFeedManager = new UsdPriceFeedManager();
        SmartVaultDeposits vaultDepositManager = new SmartVaultDeposits(new MasterWallet());

        smartVaultManager = new SmartVaultManager(
            strategyRegistry,
            riskManager,
            vaultDepositManager,
            priceFeedManager
        );

        strategyRegistry.grantRole(strategyRegistry.CLAIMER_ROLE(), address(smartVaultManager));

        strategyA = new MockStrategy("StratA", strategyRegistry);
        uint256[] memory strategyARatios = new uint256[](2);
        strategyARatios[0] = 1_000;
        strategyARatios[1] = 68;
        strategyA.initialize(assetGroupId, assetGroupRegistry, strategyARatios);
        strategyRegistry.registerStrategy(address(strategyA));

        strategyB = new MockStrategy("StratB", strategyRegistry);
        uint256[] memory strategyBRatios = new uint256[](2);
        strategyBRatios[0] = 1_000;
        strategyBRatios[1] = 67;
        strategyB.initialize(assetGroupId, assetGroupRegistry, strategyBRatios);
        strategyRegistry.registerStrategy(address(strategyB));

        mySmartVault = new SmartVault(
            "MySmartVault",
            guardManager,
            actionManager,
            smartVaultManager,
            masterWallet
        );
        mySmartVault.initialize(assetGroupId, assetGroupRegistry);
        smartVaultManager.registerSmartVault(address(mySmartVault));
        guardManager.setGuards(address(mySmartVault), emptyGuards);
        actionManager.setActions(address(mySmartVault), emptyActions, emptyActionsRequestTypes);
        mySmartVaultStrategies = new address[](2);
        mySmartVaultStrategies[0] = address(strategyA);
        mySmartVaultStrategies[1] = address(strategyB);
        smartVaultManager.setStrategies(address(mySmartVault), mySmartVaultStrategies);
        masterWallet.setWalletManager(address(mySmartVault), true);
    }

    function test_shouldBeAbleToWithdraw() public {
        // set initial state
        deal(address(mySmartVault), alice, 4_000_000, true);
        deal(address(mySmartVault), bob, 1_000_000, true);
        deal(address(strategyA), address(mySmartVault), 40_000_000, true);
        deal(address(strategyB), address(mySmartVault), 10_000_000, true);

        // request withdrawal
        vm.prank(alice);
        uint256 aliceWithdrawalNftId = mySmartVault.redeem(3_000_000, alice, alice);

        vm.prank(bob);
        uint256 bobWithdrawalNftId = mySmartVault.redeem(200_000, bob, bob);

        // check state
        // - vault tokens are returned to vault
        assertEq(mySmartVault.balanceOf(alice), 1_000_000);
        assertEq(mySmartVault.balanceOf(bob), 800_000);
        assertEq(mySmartVault.balanceOf(address(mySmartVault)), 3_200_000);
        // - withdrawal NFTs are minted
        assertEq(aliceWithdrawalNftId, 2 ** 255 + 1);
        assertEq(bobWithdrawalNftId, 2 ** 255 + 2);
        assertEq(mySmartVault.balanceOf(alice, aliceWithdrawalNftId), 1);
        assertEq(mySmartVault.balanceOf(bob, bobWithdrawalNftId), 1);

        // flush
        SwapInfo[] memory swapInfo = new SwapInfo[](0);
        smartVaultManager.flushSmartVault(address(mySmartVault), swapInfo);

        // check state
        // - vault tokens are burned
        assertEq(mySmartVault.balanceOf(address(mySmartVault)), 0);
        // - strategy tokens are returned to strategies
        assertEq(strategyA.balanceOf(address(mySmartVault)), 14_400_000);
        assertEq(strategyB.balanceOf(address(mySmartVault)), 3_600_000);
        assertEq(strategyA.balanceOf(address(strategyA)), 25_600_000);
        assertEq(strategyB.balanceOf(address(strategyB)), 6_400_000);

        // simulate DHW
        uint256[] memory strategyAWithdrawnAssets = new uint256[](2);
        strategyAWithdrawnAssets[0] = 25.6 ether;
        strategyAWithdrawnAssets[1] = 1.7408 ether;
        strategyA._setWithdrawnAssets(strategyAWithdrawnAssets);
        tokenA.mint(address(strategyA), 25.6 ether);
        tokenB.mint(address(strategyA), 1.7408 ether);

        uint256[] memory strategyBWithdrawnAssets = new uint256[](2);
        strategyBWithdrawnAssets[0] = 6.4 ether;
        strategyBWithdrawnAssets[1] = 0.4288 ether;
        strategyB._setWithdrawnAssets(strategyBWithdrawnAssets);
        tokenA.mint(address(strategyB), 6.4 ether);
        tokenB.mint(address(strategyB), 0.4288 ether);

        strategyRegistry.doHardWork(mySmartVaultStrategies);

        // check state
        // - strategy tokens are burned
        assertEq(strategyA.balanceOf(address(strategyA)), 0);
        assertEq(strategyB.balanceOf(address(strategyB)), 0);
        // - assets are withdrawn from protocol master wallet
        assertEq(tokenA.balanceOf(address(masterWallet)), 32 ether);
        assertEq(tokenB.balanceOf(address(masterWallet)), 2.1696 ether);
        assertEq(tokenA.balanceOf(address(strategyA)), 0);
        assertEq(tokenB.balanceOf(address(strategyA)), 0);
        assertEq(tokenA.balanceOf(address(strategyB)), 0);
        assertEq(tokenB.balanceOf(address(strategyB)), 0);

        // sync the vault
        smartVaultManager.syncSmartVault(address(mySmartVault));

        // check state
        // nothing to check

        // claim withdrawal
        vm.prank(alice);
        mySmartVault.claimWithdrawal(aliceWithdrawalNftId, alice);

        vm.prank(bob);
        mySmartVault.claimWithdrawal(bobWithdrawalNftId, bob);

        // check state
        // - assets are transfered to withdrawers
        assertEq(tokenA.balanceOf(alice), 30 ether);
        assertEq(tokenB.balanceOf(alice), 2.034 ether);
        assertEq(tokenA.balanceOf(bob), 2 ether);
        assertEq(tokenB.balanceOf(bob), 0.1356 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0);
        assertEq(tokenB.balanceOf(address(masterWallet)), 0);
        // - withdrawal NFTs are burned
        assertEq(mySmartVault.balanceOf(alice, aliceWithdrawalNftId), 0);
        assertEq(mySmartVault.balanceOf(bob, bobWithdrawalNftId), 0);
    }
}
