// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../fixtures/TestFixture.sol";
import "../fixtures/IntegrationTestFixture.sol";

struct TestBag {
    SmartVaultFees fees;
    SwapInfo[][] dhwSwapInfo;
    uint256[] depositAmounts;
    address vaultOwner;
}

contract RemoveStrategyTest is IntegrationTestFixture {
    function setUp() public {
        setUpBase();
        deal(address(tokenA), alice, 1000 ether, true);
        deal(address(tokenB), alice, 1000 ether, true);
        deal(address(tokenC), alice, 1000 ether, true);

        vm.startPrank(alice);
        tokenA.approve(address(smartVaultManager), 1000 ether);
        tokenB.approve(address(smartVaultManager), 1000 ether);
        tokenC.approve(address(smartVaultManager), 1000 ether);
        vm.stopPrank();
    }

    function test_removeStrategy_ok() public {
        createVault();
        vm.clearMockedCalls();

        assertEq(smartVaultManager.strategies(address(smartVault)).length, 3);
        assertTrue(accessControl.hasRole(ROLE_STRATEGY, smartVaultStrategies[0]));

        smartVaultManager.removeStrategy(smartVaultStrategies[0]);

        address[] memory strategies2 = smartVaultManager.strategies(address(smartVault));
        uint256[] memory allocations = smartVaultManager.allocations(address(smartVault));

        assertFalse(accessControl.hasRole(ROLE_STRATEGY, smartVaultStrategies[0]));
        assertEq(strategies2.length, 3);
        assertEq(strategies2[0], address(ghostStrategy));
        assertEq(allocations[0], 0);
        assertGt(allocations[1], 0);
        assertGt(allocations[2], 0);
    }

    function test_removeStrategy_revertInvalidStrategy() public {
        createVault();

        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_STRATEGY, address(0xabc)));
        smartVaultManager.removeStrategy(address(0xabc));
    }

    function test_removeStrategy_betweenFlushAndDHW() public {
        TestBag memory bag;
        createVault();
        vm.clearMockedCalls();

        bag.fees = SmartVaultFees(0, 0);
        bag.dhwSwapInfo = new SwapInfo[][](3);
        bag.depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        bag.dhwSwapInfo[0] = new SwapInfo[](0);
        bag.dhwSwapInfo[1] = new SwapInfo[](0);
        bag.dhwSwapInfo[2] = new SwapInfo[](0);

        vm.prank(alice);
        smartVaultManager.deposit(DepositBag(address(smartVault), bag.depositAmounts, alice, address(0), true));

        smartVaultManager.removeStrategy(smartVaultStrategies[0]);
        smartVaultStrategies = smartVaultManager.strategies(address(smartVault));
        strategyRegistry.doHardWork(smartVaultStrategies, bag.dhwSwapInfo);

        DepositSyncResult memory syncResult = depositManager.syncDepositsSimulate(
            address(smartVault),
            0, // flush index
            0, // first dhw timestamp
            0, // total SVTs minted til now
            smartVaultStrategies,
            assetGroup,
            Arrays.toUint16a16(1, 1, 1),
            bag.fees
        );
        smartVaultManager.syncSmartVault(address(smartVault), true);

        assertEq(smartVaultStrategies[0], address(ghostStrategy));
        assertEq(syncResult.mintedSVTs, smartVault.totalSupply());
        assertEq(ghostStrategy.totalSupply(), 0);
        assertEq(strategyA.totalSupply(), syncResult.sstShares[0]);
        assertEq(strategyB.totalSupply(), syncResult.sstShares[1]);
        assertEq(strategyC.totalSupply(), syncResult.sstShares[2]);
        assertEq(syncResult.sstShares[0], 0);
        assertEq(syncResult.sstShares[1], 107148831538266256993250000);
        assertEq(syncResult.sstShares[2], 35716275414794966628800000);
    }

    function test_removeStrategy_betweenDHWAndVaultSync() public {
        TestBag memory bag;
        createVault();
        vm.clearMockedCalls();

        bag.fees = SmartVaultFees(0, 0);
        bag.dhwSwapInfo = new SwapInfo[][](3);
        bag.depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        bag.dhwSwapInfo[0] = new SwapInfo[](0);
        bag.dhwSwapInfo[1] = new SwapInfo[](0);
        bag.dhwSwapInfo[2] = new SwapInfo[](0);

        vm.prank(alice);
        smartVaultManager.deposit(DepositBag(address(smartVault), bag.depositAmounts, alice, address(0), true));

        strategyRegistry.doHardWork(smartVaultStrategies, bag.dhwSwapInfo);

        smartVaultManager.removeStrategy(smartVaultStrategies[0]);
        smartVaultStrategies = smartVaultManager.strategies(address(smartVault));

        DepositSyncResult memory syncResult = depositManager.syncDepositsSimulate(
            address(smartVault),
            0, // flush index
            0, // first dhw timestamp
            0, // total SVTs minted til now
            smartVaultStrategies,
            assetGroup,
            Arrays.toUint16a16(1, 1, 1),
            bag.fees
        );
        smartVaultManager.syncSmartVault(address(smartVault), true);

        assertEq(smartVaultStrategies[0], address(ghostStrategy));
        assertEq(syncResult.mintedSVTs, smartVault.totalSupply());
        assertEq(ghostStrategy.totalSupply(), 0);
        assertEq(strategyA.totalSupply(), 214297693046938776377950000);
        assertEq(strategyB.totalSupply(), syncResult.sstShares[1]);
        assertEq(strategyC.totalSupply(), syncResult.sstShares[2]);
        assertEq(syncResult.sstShares[0], 0);
        assertEq(syncResult.sstShares[1], 107148831538266256993250000);
        assertEq(syncResult.sstShares[2], 35716275414794966628800000);
    }

    function test_removeStrategy_betweenFlushAndDhwWithdrawals() public {
        TestBag memory bag;
        createVault();
        vm.clearMockedCalls();

        bag.fees = SmartVaultFees(0, 0);
        bag.dhwSwapInfo = new SwapInfo[][](3);
        bag.depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        bag.dhwSwapInfo[0] = new SwapInfo[](0);
        bag.dhwSwapInfo[1] = new SwapInfo[](0);
        bag.dhwSwapInfo[2] = new SwapInfo[](0);

        vm.prank(alice);
        uint256 nftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), bag.depositAmounts, alice, address(0), true));

        smartVaultManager.removeStrategy(smartVaultStrategies[0]);
        smartVaultStrategies = smartVaultManager.strategies(address(smartVault));
        strategyRegistry.doHardWork(smartVaultStrategies, bag.dhwSwapInfo);

        uint256 aliceBalance = smartVaultManager.getUserSVTBalance(address(smartVault), alice);
        vm.startPrank(alice);
        uint256 redeemNftId = smartVaultManager.redeem(
            RedeemBag(address(smartVault), aliceBalance, Arrays.toArray(nftId), Arrays.toArray(NFT_MINTED_SHARES)),
            alice,
            true
        );
        vm.stopPrank();

        strategyRegistry.doHardWork(smartVaultStrategies, bag.dhwSwapInfo);

        vm.startPrank(alice);
        (uint256[] memory withdrawnAssets,) = smartVaultManager.claimWithdrawal(
            address(smartVault), Arrays.toArray(redeemNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
        );

        assertEq(smartVaultStrategies[0], address(ghostStrategy));
        assertEq(ghostStrategy.totalSupply(), 0);
        assertGt(withdrawnAssets[0], 0);
        assertGt(withdrawnAssets[1], 0);
        assertGt(withdrawnAssets[2], 0);
    }
}
