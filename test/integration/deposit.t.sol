// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

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
import "../../src/SmartVaultFactory.sol";
import "../../src/Swapper.sol";
import "../libraries/Arrays.sol";
import "../libraries/Constants.sol";
import "../mocks/MockStrategy.sol";
import "../mocks/MockToken.sol";
import "../mocks/MockPriceFeedManager.sol";
import "../fixtures/TestFixture.sol";
import "../fixtures/IntegrationTestFixture.sol";

contract DepositIntegrationTest is IntegrationTestFixture {
    using uint16a16Lib for uint16a16;

    function setUp() public {
        setUpBase();
        createVault();
    }

    function test_deposit_revertNothingToFlushAndSync() public {
        // Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        vm.expectRevert(abi.encodeWithSelector(NothingToFlush.selector));
        smartVaultManager.flushSmartVault(address(smartVault));

        vm.expectRevert(abi.encodeWithSelector(NothingToSync.selector));
        smartVaultManager.syncSmartVault(address(smartVault), true);

        vm.stopPrank();
    }

    function test_shouldBeAbleToDeposit() public {
        // Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        uint256 aliceDepositNftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), false));

        vm.stopPrank();

        // check state
        // - tokens were transferred
        assertEq(tokenA.balanceOf(alice), 0 ether);
        assertEq(tokenB.balanceOf(alice), 2.763 ether);
        assertEq(tokenC.balanceOf(alice), 61.2 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 100 ether);
        assertEq(tokenB.balanceOf(address(masterWallet)), 7.237 ether);
        assertEq(tokenC.balanceOf(address(masterWallet)), 438.8 ether);
        // - deposit NFT was minted
        assertEq(aliceDepositNftId, 1);
        assertEq(smartVault.balanceOfFractional(alice, aliceDepositNftId), NFT_MINTED_SHARES);

        // flush
        smartVaultManager.flushSmartVault(address(smartVault));

        // DHW
        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroup));
        vm.stopPrank();

        // check state
        // - tokens were routed to the protocol
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 60_787285104601546518);
        assertEq(tokenB.balanceOf(address(strategyA.protocol())), 4_315894186899635873);
        assertEq(tokenC.balanceOf(address(strategyA.protocol())), 261_378837986158860145);
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 29_529225446144834384);
        assertEq(tokenB.balanceOf(address(strategyB.protocol())), 2_185161135984433228);
        assertEq(tokenC.balanceOf(address(strategyB.protocol())), 132_878216195362039975);
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 9_683489449253619098);
        assertEq(tokenB.balanceOf(address(strategyC.protocol())), 735944677115930899);
        assertEq(tokenC.balanceOf(address(strategyC.protocol())), 44_542945818479099880);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0);
        assertEq(tokenB.balanceOf(address(masterWallet)), 0);
        assertEq(tokenC.balanceOf(address(masterWallet)), 0);
        // - strategy tokens were minted
        assertEq(strategyA.totalSupply(), 214297693046938776377950000);
        assertEq(strategyB.totalSupply(), 107148831538266256993250000);
        assertEq(strategyC.totalSupply(), 35716275414794966628800000);

        // sync vault
        smartVaultManager.syncSmartVault(address(smartVault), true);

        // check state
        // - strategy tokens were claimed
        assertEq(strategyA.balanceOf(address(smartVault)), 214297693046938776377950000);
        assertEq(strategyB.balanceOf(address(smartVault)), 107148831538266256993250000);
        assertEq(strategyC.balanceOf(address(smartVault)), 35716275414794966628800000);
        assertEq(strategyA.balanceOf(address(strategyA)), 0);
        assertEq(strategyB.balanceOf(address(strategyB)), 0);
        assertEq(strategyC.balanceOf(address(strategyC)), 0);
        // - vault tokens were minted
        assertEq(smartVault.totalSupply(), 357162800000000000000000000);
        assertEq(smartVault.balanceOf(address(smartVault)), 357162800000000000000000000);

        uint256[] memory ids = Arrays.toArray(aliceDepositNftId);
        uint256 balance = smartVaultManager.getUserSVTBalance(address(smartVault), alice, ids);
        assertEq(balance, 357162800000000000000000000);

        // claim deposit
        uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);
        vm.prank(alice);
        smartVaultManager.claimSmartVaultTokens(address(smartVault), ids, amounts);

        // check state
        // - vault tokens were claimed
        assertEq(smartVault.balanceOf(address(alice)), 357162800000000000000000000);
        assertEq(smartVault.balanceOf(address(smartVault)), 0);
        // - deposit NFT was burned
        assertEq(smartVault.balanceOfFractional(alice, aliceDepositNftId), 0);
    }

    function test_flushMultipleDeposits() public {
        // Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        uint256 aliceDepositNftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), false));

        vm.stopPrank();

        // Bob deposits
        address bob = address(0x1234);
        vm.startPrank(bob);

        deal(address(tokenA), bob, 2000 ether, true);
        deal(address(tokenB), bob, 2000 ether, true);
        deal(address(tokenC), bob, 2000 ether, true);

        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        uint256 bobDepositNftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, bob, address(0), false));

        vm.stopPrank();

        // check state
        // - deposit NFTs were minted
        assertEq(aliceDepositNftId, 1);
        assertEq(smartVault.balanceOfFractional(alice, aliceDepositNftId), NFT_MINTED_SHARES);
        assertEq(bobDepositNftId, 2);
        assertEq(smartVault.balanceOfFractional(bob, bobDepositNftId), NFT_MINTED_SHARES);

        // - master wallet has funds
        assertEq(tokenA.balanceOf(address(masterWallet)), 100 ether * 2);
        assertEq(tokenB.balanceOf(address(masterWallet)), 7.237 ether * 2);
        assertEq(tokenC.balanceOf(address(masterWallet)), 438.8 ether * 2);

        // flush
        smartVaultManager.flushSmartVault(address(smartVault));

        // DHW
        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroup));
        vm.stopPrank();

        // check state
        // - master wallet has funds
        assertEq(tokenA.balanceOf(address(masterWallet)), 0);
        assertEq(tokenB.balanceOf(address(masterWallet)), 0);
        assertEq(tokenC.balanceOf(address(masterWallet)), 0);

        // - tokens were routed to the protocol
        assertEq(
            tokenA.balanceOf(address(strategyA.protocol())) + tokenA.balanceOf(address(strategyB.protocol()))
                + tokenA.balanceOf(address(strategyC.protocol())),
            100 ether * 2
        );

        assertEq(
            tokenB.balanceOf(address(strategyA.protocol())) + tokenB.balanceOf(address(strategyB.protocol()))
                + tokenB.balanceOf(address(strategyC.protocol())),
            7.237 ether * 2
        );

        assertEq(
            tokenC.balanceOf(address(strategyA.protocol())) + tokenC.balanceOf(address(strategyB.protocol()))
                + tokenC.balanceOf(address(strategyC.protocol())),
            438.8 ether * 2
        );
    }

    function test_claimSmartVaultTokensPartially() public {
        // Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        uint256 aliceDepositNftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), false));

        vm.stopPrank();

        // flush
        smartVaultManager.flushSmartVault(address(smartVault));

        // DHW
        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroup));
        vm.stopPrank();

        // sync vault
        smartVaultManager.syncSmartVault(address(smartVault), true);

        uint256 svtBalance = 357162800000000000000000000;

        // - vault tokens were minted
        assertEq(smartVault.totalSupply(), svtBalance);
        assertEq(smartVault.balanceOf(address(smartVault)), svtBalance);

        uint256 balance =
            smartVaultManager.getUserSVTBalance(address(smartVault), alice, Arrays.toArray(aliceDepositNftId));
        assertEq(balance, svtBalance);

        // burn half of NFT
        uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES / 2);
        uint256[] memory ids = Arrays.toArray(aliceDepositNftId);
        vm.startPrank(alice);
        smartVaultManager.claimSmartVaultTokens(address(smartVault), ids, amounts);

        // check state
        // - vault tokens were partially claimed
        assertEq(smartVault.balanceOf(address(alice)), svtBalance / 2);
        assertEq(smartVault.balanceOf(address(smartVault)), svtBalance / 2);

        // - deposit NFT was partially burned
        assertEq(smartVault.balanceOfFractional(alice, aliceDepositNftId), NFT_MINTED_SHARES / 2);

        // burn remaining of NFT
        smartVaultManager.claimSmartVaultTokens(address(smartVault), ids, amounts);

        // check state
        // - vault tokens were claimed in full
        assertEq(smartVault.balanceOf(address(alice)), svtBalance);
        assertEq(smartVault.balanceOf(address(smartVault)), 0);

        // - deposit NFT was burned in full
        assertEq(smartVault.balanceOfFractional(alice, aliceDepositNftId), 0);
    }

    function test_getUserSVTBalance_withActiveDepositNFT() public {
        deal(address(tokenA), alice, 2000 ether, true);
        deal(address(tokenB), alice, 2000 ether, true);
        deal(address(tokenC), alice, 2000 ether, true);

        // Alice deposits #1
        vm.startPrank(alice);

        uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);
        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        uint256 aliceBalance;
        uint256 aliceDepositNftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), true));
        vm.stopPrank();

        uint256[] memory nftIds = Arrays.toArray(aliceDepositNftId);
        // DHW
        // balance before DHW should be 0
        aliceBalance = smartVaultManager.getUserSVTBalance(address(smartVault), alice, nftIds);
        assertEq(smartVault.totalSupply(), 0);
        assertEq(smartVault.balanceOf(address(smartVault)), 0);
        assertEq(smartVault.balanceOf(alice), 0);
        assertEq(aliceBalance, 0);

        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroup));
        vm.stopPrank();

        // balance after DHW, before vault sync
        // should simulate sync
        uint256 expectedBalance = 357162800000000000000000000;
        aliceBalance = smartVaultManager.getUserSVTBalance(address(smartVault), alice, nftIds);
        assertEq(smartVault.totalSupply(), 0);
        assertEq(smartVault.balanceOf(address(smartVault)), 0);
        assertEq(smartVault.balanceOf(alice), 0);
        assertEq(aliceBalance, expectedBalance);

        smartVaultManager.syncSmartVault(address(smartVault), true);

        // balances after vault sync
        aliceBalance = smartVaultManager.getUserSVTBalance(address(smartVault), alice, nftIds);
        assertEq(aliceBalance, expectedBalance);
        assertEq(smartVault.totalSupply(), expectedBalance);
        assertEq(smartVault.balanceOf(address(smartVault)), expectedBalance);

        // Alice deposits #2
        vm.startPrank(alice);

        depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);
        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        aliceDepositNftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), true));
        vm.stopPrank();

        nftIds = Arrays.toArray(nftIds[0], aliceDepositNftId);
        // balances after deposit #2, before DHW, should be the same
        aliceBalance = smartVaultManager.getUserSVTBalance(address(smartVault), alice, nftIds);
        assertEq(aliceBalance, expectedBalance);
        assertEq(smartVault.totalSupply(), expectedBalance);
        assertEq(smartVault.balanceOf(address(smartVault)), expectedBalance);
    }

    function test_claimWithdrawal_revertIfDepositNFT() public {
        // Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);
        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        uint256 aliceDepositNftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), false));
        vm.stopPrank();

        smartVaultManager.flushSmartVault(address(smartVault));

        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroup));
        vm.stopPrank();

        smartVaultManager.syncSmartVault(address(smartVault), true);

        vm.startPrank(alice);
        uint256[] memory nftIds = Arrays.toArray(aliceDepositNftId);
        uint256[] memory nftAmounts = Arrays.toArray(NFT_MINTED_SHARES);
        vm.expectRevert(abi.encodeWithSelector(InvalidWithdrawalNftId.selector, aliceDepositNftId));
        smartVaultManager.claimWithdrawal(address(smartVault), nftIds, nftAmounts, alice);
        vm.stopPrank();
    }

    function test_claimSVTs_revertInvalidNFT() public {
        deal(address(tokenA), alice, 2000 ether, true);
        deal(address(tokenB), alice, 2000 ether, true);
        deal(address(tokenC), alice, 2000 ether, true);

        uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        // Alice deposits #1
        vm.startPrank(alice);

        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        uint256 aliceDepositNftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), true));
        vm.stopPrank();

        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroup));
        vm.stopPrank();

        // Alice withdraws
        uint256 aliceBalance =
            smartVaultManager.getUserSVTBalance(address(smartVault), alice, Arrays.toArray(aliceDepositNftId));
        vm.startPrank(alice);
        uint256 aliceWithdrawalNftId = smartVaultManager.redeem(
            RedeemBag(
                address(smartVault),
                aliceBalance / 3,
                Arrays.toArray(aliceDepositNftId),
                Arrays.toArray(NFT_MINTED_SHARES / 2)
            ),
            alice,
            false
        );

        uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES / 3);
        uint256[] memory ids = Arrays.toArray(aliceWithdrawalNftId);

        // alice tries to claim tokens with invalid NFT
        vm.expectRevert(abi.encodeWithSelector(InvalidDepositNftId.selector, aliceWithdrawalNftId));
        smartVaultManager.claimSmartVaultTokens(address(smartVault), ids, amounts);

        vm.stopPrank();
    }

    function test_doubleDeposit_revertOverlappingFlush() public {
        address bob = address(0xb0b);

        deal(address(tokenA), bob, 100 ether, true);
        deal(address(tokenB), bob, 10 ether, true);
        deal(address(tokenC), bob, 500 ether, true);

        // Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), false));

        vm.stopPrank();

        // flush
        smartVaultManager.flushSmartVault(address(smartVault));

        // Deposit again should fail
        // Bob deposits
        vm.startPrank(bob);

        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        // Should revert for trying to flush after depositing
        vm.expectRevert(abi.encodeWithSelector(FlushOverlap.selector, smartVaultStrategies[0]));
        smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, bob, address(0), true));

        smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, bob, address(0), false));

        vm.stopPrank();

        // Should revert for trying to flush
        vm.expectRevert(abi.encodeWithSelector(FlushOverlap.selector, smartVaultStrategies[0]));
        smartVaultManager.flushSmartVault(address(smartVault));
    }

    function test_depositClaim_shouldRevertWhenTryingToClaimUnsyncedNfts() public {
        // Alice deposits
        vm.startPrank(alice);
        uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        uint256 aliceDepositNftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), false));
        vm.stopPrank();

        // flush
        smartVaultManager.flushSmartVault(address(smartVault));

        // try to claim SVTs
        uint256[] memory ids = Arrays.toArray(aliceDepositNftId);
        uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(DepositNftNotSyncedYet.selector, aliceDepositNftId));
        smartVaultManager.claimSmartVaultTokens(address(smartVault), ids, amounts);
        vm.stopPrank();
    }

    function test_depositRedeem_shouldRevertWhenTryingToRedeemUnsyncedNfts() public {
        // Alice deposits
        vm.startPrank(alice);
        uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        uint256 aliceDepositNftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), false));
        vm.stopPrank();

        // flush
        smartVaultManager.flushSmartVault(address(smartVault));

        // try to redeem
        uint256[] memory ids = Arrays.toArray(aliceDepositNftId);
        uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(DepositNftNotSyncedYet.selector, aliceDepositNftId));
        smartVaultManager.redeem(RedeemBag(address(smartVault), 0, ids, amounts), alice, false);
        vm.stopPrank();
    }

    function test_depositRedeemFast_shouldRevertWhenTryingToRedeemUnsyncedNfts() public {
        // Alice deposits
        vm.startPrank(alice);
        uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        uint256 aliceDepositNftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), false));
        vm.stopPrank();

        // flush
        smartVaultManager.flushSmartVault(address(smartVault));

        // try to redeem
        uint256[] memory ids = Arrays.toArray(aliceDepositNftId);
        uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);

        uint256[][] memory withdrawalSlippages = new uint256[][](3);
        uint256[2][] memory exchangeRateSlippages = new uint256[2][](3);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(DepositNftNotSyncedYet.selector, aliceDepositNftId));
        smartVaultManager.redeemFast(
            RedeemBag(address(smartVault), 0, ids, amounts), withdrawalSlippages, exchangeRateSlippages
        );
        vm.stopPrank();
    }

    function test_removeStrategyBeforeDeposit() public {
        {
            // remove strategy A
            smartVaultManager.removeStrategyFromVaults(
                smartVaultStrategies[0], Arrays.toArray(address(smartVault)), true
            );
        }

        uint256 aliceDepositNftId;
        {
            // Alice deposits into strategy
            vm.startPrank(alice);
            uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.449 ether, 452.5 ether);

            tokenA.approve(address(smartVaultManager), depositAmounts[0]);
            tokenB.approve(address(smartVaultManager), depositAmounts[1]);
            tokenC.approve(address(smartVaultManager), depositAmounts[2]);

            aliceDepositNftId =
                smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), false));
            vm.stopPrank();

            // check state
            // - tokens were transferred
            assertEq(tokenA.balanceOf(alice), 0 ether);
            assertEq(tokenB.balanceOf(alice), 2.551 ether);
            assertEq(tokenC.balanceOf(alice), 47.5 ether);
            assertEq(tokenA.balanceOf(address(masterWallet)), 100 ether);
            assertEq(tokenB.balanceOf(address(masterWallet)), 7.449 ether);
            assertEq(tokenC.balanceOf(address(masterWallet)), 452.5 ether);
            // - deposit NFT was minted
            assertEq(aliceDepositNftId, 1);
            assertEq(smartVault.balanceOfFractional(alice, aliceDepositNftId), NFT_MINTED_SHARES);
        }

        {
            // flush
            smartVaultManager.flushSmartVault(address(smartVault));
        }

        {
            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(
                generateDhwParameterBag(Arrays.toArray(address(strategyB), address(strategyC)), assetGroup)
            );
            vm.stopPrank();

            // check state
            // - tokens were routed to the protocol
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 0);
            assertEq(tokenB.balanceOf(address(strategyA.protocol())), 0);
            assertEq(tokenC.balanceOf(address(strategyA.protocol())), 0);
            assertEq(tokenA.balanceOf(address(strategyB.protocol())), 75_305230777606881815);
            assertEq(tokenB.balanceOf(address(strategyB.protocol())), 5_572295679584402828);
            assertEq(tokenC.balanceOf(address(strategyB.protocol())), 338_896398523816514292);
            assertEq(tokenA.balanceOf(address(strategyC.protocol())), 24_694769222393118185);
            assertEq(tokenB.balanceOf(address(strategyC.protocol())), 1_876704320415597172);
            assertEq(tokenC.balanceOf(address(strategyC.protocol())), 113_603601476183485708);
            assertEq(tokenA.balanceOf(address(masterWallet)), 0);
            assertEq(tokenB.balanceOf(address(masterWallet)), 0);
            assertEq(tokenC.balanceOf(address(masterWallet)), 0);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 0);
            assertEq(strategyB.totalSupply(), 273253953679742923416040000);
            assertEq(strategyC.totalSupply(), 91084646320257076583960000);
        }

        {
            // sync vault
            smartVaultManager.syncSmartVault(address(smartVault), true);

            // check state
            // - strategy tokens were claimed
            assertEq(strategyA.balanceOf(address(smartVault)), 0);
            assertEq(strategyB.balanceOf(address(smartVault)), 273253953679742923416040000);
            assertEq(strategyC.balanceOf(address(smartVault)), 91084646320257076583960000);
            assertEq(strategyA.balanceOf(address(strategyA)), 0);
            assertEq(strategyB.balanceOf(address(strategyB)), 0);
            assertEq(strategyC.balanceOf(address(strategyC)), 0);
            // - vault tokens were minted
            assertEq(smartVault.totalSupply(), 364338600000000000000000000);
            assertEq(smartVault.balanceOf(address(smartVault)), 364338600000000000000000000);
        }

        {
            // claim deposit
            uint256[] memory ids = Arrays.toArray(aliceDepositNftId);
            uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);
            vm.prank(alice);
            smartVaultManager.claimSmartVaultTokens(address(smartVault), ids, amounts);

            // check state
            // - vault tokens were claimed
            assertEq(smartVault.balanceOf(address(alice)), 364338600000000000000000000);
            assertEq(smartVault.balanceOf(address(smartVault)), 0);
            // - deposit NFT was burned
            assertEq(smartVault.balanceOfFractional(alice, aliceDepositNftId), 0);
        }
    }

    function test_removeStrategyAfterDepositAndBeforeFlush() public {
        console.log("strategyA", address(strategyA));
        console.log("strategyB", address(strategyB));
        console.log("strategyC", address(strategyC));
        console.log("ghost strategy", address(ghostStrategy));

        uint256 aliceDepositNftId;
        {
            // Alice deposits
            vm.startPrank(alice);

            uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

            tokenA.approve(address(smartVaultManager), depositAmounts[0]);
            tokenB.approve(address(smartVaultManager), depositAmounts[1]);
            tokenC.approve(address(smartVaultManager), depositAmounts[2]);

            aliceDepositNftId =
                smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), false));

            vm.stopPrank();

            // check state
            // - tokens were transferred
            assertEq(tokenA.balanceOf(alice), 0 ether);
            assertEq(tokenB.balanceOf(alice), 2.763 ether);
            assertEq(tokenC.balanceOf(alice), 61.2 ether);
            assertEq(tokenA.balanceOf(address(masterWallet)), 100 ether);
            assertEq(tokenB.balanceOf(address(masterWallet)), 7.237 ether);
            assertEq(tokenC.balanceOf(address(masterWallet)), 438.8 ether);
            // - deposit NFT was minted
            assertEq(aliceDepositNftId, 1);
            assertEq(smartVault.balanceOfFractional(alice, aliceDepositNftId), NFT_MINTED_SHARES);
        }

        {
            // remove strategyA
            smartVaultManager.removeStrategyFromVaults(
                smartVaultStrategies[0], Arrays.toArray(address(smartVault)), true
            );
        }

        {
            // flush
            smartVaultManager.flushSmartVault(address(smartVault));

            // check state
            uint256 currentFlushIndex = smartVaultManager.getLatestFlushIndex(address(smartVault));
            uint16a16 dhwIndexes = smartVaultManager.dhwIndexes(address(smartVault), currentFlushIndex - 1);
            uint256[] memory assetsAssigned;
            // - assets were assigned to strategies
            assetsAssigned = strategyRegistry.depositedAssets(address(strategyA), dhwIndexes.get(0));
            assertEq(assetsAssigned[0], 0);
            assertEq(assetsAssigned[1], 0);
            assertEq(assetsAssigned[2], 0);
            assetsAssigned = strategyRegistry.depositedAssets(address(strategyB), dhwIndexes.get(1));
            assertEq(assetsAssigned[0], 75_305230777606881815);
            assertEq(assetsAssigned[1], 5_413707052376469763);
            assertEq(assetsAssigned[2], 328_635888778454555738);
            assetsAssigned = strategyRegistry.depositedAssets(address(strategyC), dhwIndexes.get(2));
            assertEq(assetsAssigned[0], 24_694769222393118185);
            assertEq(assetsAssigned[1], 1_823292947623530237);
            assertEq(assetsAssigned[2], 110_164111221545444262);
        }

        {
            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(
                generateDhwParameterBag(Arrays.toArray(address(strategyB), address(strategyC)), assetGroup)
            );
            vm.stopPrank();

            // check state
            // - tokens were routed to the protocol
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 0);
            assertEq(tokenB.balanceOf(address(strategyA.protocol())), 0);
            assertEq(tokenC.balanceOf(address(strategyA.protocol())), 0);
            assertEq(tokenA.balanceOf(address(strategyB.protocol())), 75_305230777606881815);
            assertEq(tokenB.balanceOf(address(strategyB.protocol())), 5_413707052376469763);
            assertEq(tokenC.balanceOf(address(strategyB.protocol())), 328_635888778454555738);
            assertEq(tokenA.balanceOf(address(strategyC.protocol())), 24_694769222393118185);
            assertEq(tokenB.balanceOf(address(strategyC.protocol())), 1_823292947623530237);
            assertEq(tokenC.balanceOf(address(strategyC.protocol())), 110_164111221545444262);
            assertEq(tokenA.balanceOf(address(masterWallet)), 0);
            assertEq(tokenB.balanceOf(address(masterWallet)), 0);
            assertEq(tokenC.balanceOf(address(masterWallet)), 0);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 0);
            assertEq(strategyB.totalSupply(), 267882762562285092340460000);
            assertEq(strategyC.totalSupply(), 89280037437714907659540000);
        }

        {
            // sync vault
            smartVaultManager.syncSmartVault(address(smartVault), true);

            // check state
            // - strategy tokens were claimed
            assertEq(strategyA.balanceOf(address(smartVault)), 0);
            assertEq(strategyB.balanceOf(address(smartVault)), 267882762562285092340460000);
            assertEq(strategyC.balanceOf(address(smartVault)), 89280037437714907659540000);
            assertEq(strategyA.balanceOf(address(strategyA)), 0);
            assertEq(strategyB.balanceOf(address(strategyB)), 0);
            assertEq(strategyC.balanceOf(address(strategyC)), 0);
            // - vault tokens were minted
            assertEq(smartVault.totalSupply(), 357162800000000000000000000);
            assertEq(smartVault.balanceOf(address(smartVault)), 357162800000000000000000000);
        }

        {
            // claim deposit
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVault), Arrays.toArray(aliceDepositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();

            // check state
            // - vault tokens were claimed
            assertEq(smartVault.balanceOf(address(alice)), 357162800000000000000000000);
            assertEq(smartVault.balanceOf(address(smartVault)), 0);
            // - deposit NFT was burned
            assertEq(smartVault.balanceOfFractional(alice, aliceDepositNftId), 0);
        }
    }

    function test_removeStrategyAfterFlushAndBeforeDhw() public {
        uint256 aliceDepositNftId;
        {
            // Alice deposits
            vm.startPrank(alice);

            uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

            tokenA.approve(address(smartVaultManager), depositAmounts[0]);
            tokenB.approve(address(smartVaultManager), depositAmounts[1]);
            tokenC.approve(address(smartVaultManager), depositAmounts[2]);

            aliceDepositNftId =
                smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), false));

            vm.stopPrank();

            // check state
            // - tokens were transferred
            assertEq(tokenA.balanceOf(alice), 0 ether);
            assertEq(tokenB.balanceOf(alice), 2.763 ether);
            assertEq(tokenC.balanceOf(alice), 61.2 ether);
            assertEq(tokenA.balanceOf(address(masterWallet)), 100 ether);
            assertEq(tokenB.balanceOf(address(masterWallet)), 7.237 ether);
            assertEq(tokenC.balanceOf(address(masterWallet)), 438.8 ether);
            // - deposit NFT was minted
            assertEq(aliceDepositNftId, 1);
            assertEq(smartVault.balanceOfFractional(alice, aliceDepositNftId), NFT_MINTED_SHARES);
        }

        {
            // flush
            smartVaultManager.flushSmartVault(address(smartVault));

            // check state
            // - assets were assigned to strategies
            uint256 currentFlushIndex = smartVaultManager.getLatestFlushIndex(address(smartVault));
            uint16a16 dhwIndexes = smartVaultManager.dhwIndexes(address(smartVault), currentFlushIndex - 1);
            uint256[] memory assetsAssigned;
            assetsAssigned = strategyRegistry.depositedAssets(address(strategyA), dhwIndexes.get(0));
            assertEq(assetsAssigned[0], 60_787285104601546518);
            assertEq(assetsAssigned[1], 4_315894186899635873);
            assertEq(assetsAssigned[2], 261_378837986158860145);
            assetsAssigned = strategyRegistry.depositedAssets(address(strategyB), dhwIndexes.get(1));
            assertEq(assetsAssigned[0], 29_529225446144834384);
            assertEq(assetsAssigned[1], 2_185161135984433228);
            assertEq(assetsAssigned[2], 132_878216195362039975);
            assetsAssigned = strategyRegistry.depositedAssets(address(strategyC), dhwIndexes.get(2));
            assertEq(assetsAssigned[0], 9_683489449253619098);
            assertEq(assetsAssigned[1], 735944677115930899);
            assertEq(assetsAssigned[2], 44_542945818479099880);
        }

        {
            // remove strategyA
            smartVaultManager.removeStrategyFromVaults(
                smartVaultStrategies[0], Arrays.toArray(address(smartVault)), true
            );

            // check state
            // - tokens for strategy A were moved from master wallet to emergency withdrawal recipient
            assertEq(tokenA.balanceOf(address(masterWallet)), 29_529225446144834384 + 9_683489449253619098);
            assertEq(tokenB.balanceOf(address(masterWallet)), 2_185161135984433228 + 735944677115930899);
            assertEq(tokenC.balanceOf(address(masterWallet)), 132_878216195362039975 + 44_542945818479099880);
            assertEq(tokenA.balanceOf(address(emergencyWithdrawalRecipient)), 60_787285104601546518);
            assertEq(tokenB.balanceOf(address(emergencyWithdrawalRecipient)), 4_315894186899635873);
            assertEq(tokenC.balanceOf(address(emergencyWithdrawalRecipient)), 261_378837986158860145);
        }

        {
            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(
                generateDhwParameterBag(Arrays.toArray(address(strategyB), address(strategyC)), assetGroup)
            );
            vm.stopPrank();

            // check state
            // - tokens were routed to the protocol
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 0);
            assertEq(tokenB.balanceOf(address(strategyA.protocol())), 0);
            assertEq(tokenC.balanceOf(address(strategyA.protocol())), 0);
            assertEq(tokenA.balanceOf(address(strategyB.protocol())), 29_529225446144834384);
            assertEq(tokenB.balanceOf(address(strategyB.protocol())), 2_185161135984433228);
            assertEq(tokenC.balanceOf(address(strategyB.protocol())), 132_878216195362039975);
            assertEq(tokenA.balanceOf(address(strategyC.protocol())), 9_683489449253619098);
            assertEq(tokenB.balanceOf(address(strategyC.protocol())), 735944677115930899);
            assertEq(tokenC.balanceOf(address(strategyC.protocol())), 44_542945818479099880);
            assertEq(tokenA.balanceOf(address(masterWallet)), 0);
            assertEq(tokenB.balanceOf(address(masterWallet)), 0);
            assertEq(tokenC.balanceOf(address(masterWallet)), 0);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 0);
            assertEq(strategyB.totalSupply(), 107148831538266256993250000);
            assertEq(strategyC.totalSupply(), 35716275414794966628800000);
        }

        {
            // sync vault
            smartVaultManager.syncSmartVault(address(smartVault), true);

            // check state
            // - strategy tokens were claimed
            assertEq(strategyA.balanceOf(address(smartVault)), 0);
            assertEq(strategyB.balanceOf(address(smartVault)), 107148831538266256993250000);
            assertEq(strategyC.balanceOf(address(smartVault)), 35716275414794966628800000);
            assertEq(strategyA.balanceOf(address(strategyA)), 0);
            assertEq(strategyB.balanceOf(address(strategyB)), 0);
            assertEq(strategyC.balanceOf(address(strategyC)), 0);
            // - vault tokens were minted
            assertEq(smartVault.totalSupply(), 142865106953061223622050000);
            assertEq(smartVault.balanceOf(address(smartVault)), 142865106953061223622050000);
        }

        {
            // claim deposit
            uint256[] memory ids = Arrays.toArray(aliceDepositNftId);
            uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);
            vm.prank(alice);
            smartVaultManager.claimSmartVaultTokens(address(smartVault), ids, amounts);

            // check state
            // - vault tokens were claimed
            assertEq(smartVault.balanceOf(address(alice)), 142865106953061223622050000);
            assertEq(smartVault.balanceOf(address(smartVault)), 0);
            // - deposit NFT was burned
            assertEq(smartVault.balanceOfFractional(alice, aliceDepositNftId), 0);
        }
    }

    function test_removeStrategyAfterDhwAndBeforeSync() public {
        uint256 aliceDepositNftId;
        {
            // Alice deposits
            vm.startPrank(alice);

            uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

            tokenA.approve(address(smartVaultManager), depositAmounts[0]);
            tokenB.approve(address(smartVaultManager), depositAmounts[1]);
            tokenC.approve(address(smartVaultManager), depositAmounts[2]);

            aliceDepositNftId =
                smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), false));

            vm.stopPrank();

            // check state
            // - tokens were transferred
            assertEq(tokenA.balanceOf(alice), 0 ether);
            assertEq(tokenB.balanceOf(alice), 2.763 ether);
            assertEq(tokenC.balanceOf(alice), 61.2 ether);
            assertEq(tokenA.balanceOf(address(masterWallet)), 100 ether);
            assertEq(tokenB.balanceOf(address(masterWallet)), 7.237 ether);
            assertEq(tokenC.balanceOf(address(masterWallet)), 438.8 ether);
            // - deposit NFT was minted
            assertEq(aliceDepositNftId, 1);
            assertEq(smartVault.balanceOfFractional(alice, aliceDepositNftId), NFT_MINTED_SHARES);
        }

        {
            // flush
            smartVaultManager.flushSmartVault(address(smartVault));
        }

        {
            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(
                generateDhwParameterBag(
                    Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)), assetGroup
                )
            );
            vm.stopPrank();

            // check state
            // - tokens were routed to the protocol
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 60_787285104601546518);
            assertEq(tokenB.balanceOf(address(strategyA.protocol())), 4_315894186899635873);
            assertEq(tokenC.balanceOf(address(strategyA.protocol())), 261_378837986158860145);
            assertEq(tokenA.balanceOf(address(strategyB.protocol())), 29_529225446144834384);
            assertEq(tokenB.balanceOf(address(strategyB.protocol())), 2_185161135984433228);
            assertEq(tokenC.balanceOf(address(strategyB.protocol())), 132_878216195362039975);
            assertEq(tokenA.balanceOf(address(strategyC.protocol())), 9_683489449253619098);
            assertEq(tokenB.balanceOf(address(strategyC.protocol())), 735944677115930899);
            assertEq(tokenC.balanceOf(address(strategyC.protocol())), 44_542945818479099880);
            assertEq(tokenA.balanceOf(address(masterWallet)), 0);
            assertEq(tokenB.balanceOf(address(masterWallet)), 0);
            assertEq(tokenC.balanceOf(address(masterWallet)), 0);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 214297693046938776377950000);
            assertEq(strategyB.totalSupply(), 107148831538266256993250000);
            assertEq(strategyC.totalSupply(), 35716275414794966628800000);
        }

        {
            // remove strategyA
            smartVaultManager.removeStrategyFromVaults(
                smartVaultStrategies[0], Arrays.toArray(address(smartVault)), true
            );
        }

        {
            // sync vault
            smartVaultManager.syncSmartVault(address(smartVault), true);

            // check state
            // - strategy tokens for strategy B and C were claimed, for A they remain with strategy
            assertEq(strategyA.balanceOf(address(smartVault)), 0);
            assertEq(strategyB.balanceOf(address(smartVault)), 107148831538266256993250000);
            assertEq(strategyC.balanceOf(address(smartVault)), 35716275414794966628800000);
            assertEq(strategyA.balanceOf(address(strategyA)), 214297693046938776377950000);
            assertEq(strategyB.balanceOf(address(strategyB)), 0);
            assertEq(strategyC.balanceOf(address(strategyC)), 0);
            // - vault tokens were minted
            assertEq(smartVault.totalSupply(), 142865106953061223622050000);
            assertEq(smartVault.balanceOf(address(smartVault)), 142865106953061223622050000);
        }

        {
            // claim deposit
            uint256[] memory ids = Arrays.toArray(aliceDepositNftId);
            uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);
            vm.prank(alice);
            smartVaultManager.claimSmartVaultTokens(address(smartVault), ids, amounts);

            // check state
            // - vault tokens were claimed
            assertEq(smartVault.balanceOf(address(alice)), 142865106953061223622050000);
            assertEq(smartVault.balanceOf(address(smartVault)), 0);
            // - deposit NFT was burned
            assertEq(smartVault.balanceOfFractional(alice, aliceDepositNftId), 0);
        }
    }
}
