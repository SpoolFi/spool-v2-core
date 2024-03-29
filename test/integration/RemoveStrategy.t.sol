// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

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
    using uint16a16Lib for uint16a16;

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
        assertEq(smartVaultManager.strategies(address(smartVault)).length, 3);
        assertTrue(accessControl.hasRole(ROLE_STRATEGY, smartVaultStrategies[1]));

        smartVaultManager.removeStrategyFromVaults(smartVaultStrategies[1], Arrays.toArray(address(smartVault)), true);

        address[] memory strategies2 = smartVaultManager.strategies(address(smartVault));
        uint16a16 allocations = smartVaultManager.allocations(address(smartVault));

        assertFalse(accessControl.hasRole(ROLE_STRATEGY, smartVaultStrategies[1]));
        assertEq(strategies2.length, 3);
        assertEq(strategies2[1], address(ghostStrategy));
        assertGt(allocations.get(0), 0);
        assertEq(allocations.get(1), 0);
        assertGt(allocations.get(2), 0);
    }

    function test_removeStrategy_withoutVaults() public {
        vm.prank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(0xabcd));

        assertTrue(accessControl.hasRole(ROLE_STRATEGY, address(0xabcd)));
        smartVaultManager.removeStrategyFromVaults(address(0xabcd), Arrays.toArray(address(smartVault)), false);
        assertTrue(accessControl.hasRole(ROLE_STRATEGY, address(0xabcd)));
    }

    function test_removeStrategy_betweenFlushAndDHW() public {
        TestBag memory bag;
        createVault();
        bag.depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        vm.prank(alice);
        smartVaultManager.deposit(DepositBag(address(smartVault), bag.depositAmounts, alice, address(0), true));

        assertEq(tokenA.balanceOf(address(masterWallet)), 100 ether);
        assertEq(tokenB.balanceOf(address(masterWallet)), 7.237 ether);
        assertEq(tokenC.balanceOf(address(masterWallet)), 438.8 ether);

        uint256[] memory deposits = strategyRegistry.depositedAssets(address(strategyA), 1);
        smartVaultManager.removeStrategyFromVaults(smartVaultStrategies[0], Arrays.toArray(address(smartVault)), false);
        smartVaultStrategies = smartVaultManager.strategies(address(smartVault));

        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(
            generateDhwParameterBag(Arrays.toArray(address(strategyB), address(strategyC)), assetGroup)
        );
        vm.stopPrank();

        DepositSyncResult memory syncResult = depositManager.syncDepositsSimulate(
            SimulateDepositParams(
                address(smartVault),
                [uint256(0), 0], // flush index, first dhw timestamp
                smartVaultStrategies,
                assetGroup,
                Arrays.toUint16a16(1, 1, 1),
                Arrays.toUint16a16(0, 0, 0),
                bag.fees
            )
        );
        smartVaultManager.syncSmartVault(address(smartVault), true);

        assertEq(smartVaultStrategies[0], address(ghostStrategy));
        assertEq(syncResult.mintedSVTs, smartVault.totalSupply() - INITIAL_LOCKED_SHARES);
        assertEq(ghostStrategy.totalSupply(), 0);
        assertEq(strategyA.totalSupply(), syncResult.sstShares[0]);
        assertEq(strategyB.totalSupply(), syncResult.sstShares[1] + INITIAL_LOCKED_SHARES);
        assertEq(strategyC.totalSupply(), syncResult.sstShares[2] + INITIAL_LOCKED_SHARES);
        assertEq(syncResult.sstShares[0], 0);
        assertEq(syncResult.sstShares[1] + INITIAL_LOCKED_SHARES, 107148831538266256993250000);
        assertEq(syncResult.sstShares[2] + INITIAL_LOCKED_SHARES, 35716275414794966628800000);

        assertGt(deposits[0], 0);
        assertGt(deposits[1], 0);
        assertGt(deposits[2], 0);
        assertEq(tokenA.balanceOf(address(masterWallet)), deposits[0]);
        assertEq(tokenB.balanceOf(address(masterWallet)), deposits[1]);
        assertEq(tokenC.balanceOf(address(masterWallet)), deposits[2]);
    }

    function test_removeStrategy_betweenDHWAndVaultSync() public {
        TestBag memory bag;
        createVault();
        bag.depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        vm.prank(alice);
        smartVaultManager.deposit(DepositBag(address(smartVault), bag.depositAmounts, alice, address(0), true));

        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroup));
        vm.stopPrank();

        smartVaultManager.removeStrategyFromVaults(smartVaultStrategies[0], Arrays.toArray(address(smartVault)), false);
        smartVaultStrategies = smartVaultManager.strategies(address(smartVault));

        DepositSyncResult memory syncResult = depositManager.syncDepositsSimulate(
            SimulateDepositParams(
                address(smartVault),
                [uint256(0), 0], // flush index, first dhw timestamp
                smartVaultStrategies,
                assetGroup,
                Arrays.toUint16a16(1, 1, 1),
                Arrays.toUint16a16(0, 0, 0),
                bag.fees
            )
        );
        smartVaultManager.syncSmartVault(address(smartVault), true);

        assertEq(smartVaultStrategies[0], address(ghostStrategy));
        assertEq(syncResult.mintedSVTs, smartVault.totalSupply() - INITIAL_LOCKED_SHARES);
        assertEq(ghostStrategy.totalSupply(), 0);
        assertEq(strategyA.totalSupply(), 214297693046938776377950000);
        assertEq(strategyB.totalSupply(), syncResult.sstShares[1] + INITIAL_LOCKED_SHARES);
        assertEq(strategyC.totalSupply(), syncResult.sstShares[2] + INITIAL_LOCKED_SHARES);
        assertEq(syncResult.sstShares[0], 0);
        assertEq(syncResult.sstShares[1] + INITIAL_LOCKED_SHARES, 107148831538266256993250000);
        assertEq(syncResult.sstShares[2] + INITIAL_LOCKED_SHARES, 35716275414794966628800000);
    }

    function test_removeStrategy_betweenFlushAndDhwWithdrawals() public {
        TestBag memory bag;
        createVault();
        bag.depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        vm.prank(alice);
        uint256 nftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), bag.depositAmounts, alice, address(0), true));

        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(
            generateDhwParameterBag(
                Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)), assetGroup
            )
        );
        vm.stopPrank();

        smartVaultManager.syncSmartVault(address(smartVault), true);

        uint256 aliceBalance = spoolLens.getUserSVTBalance(address(smartVault), alice, Arrays.toArray(nftId));
        vm.startPrank(alice);
        uint256 redeemNftId = smartVaultManager.redeem(
            RedeemBag(address(smartVault), aliceBalance, Arrays.toArray(nftId), Arrays.toArray(NFT_MINTED_SHARES)),
            alice,
            true
        );
        vm.stopPrank();

        smartVaultManager.removeStrategyFromVaults(smartVaultStrategies[0], Arrays.toArray(address(smartVault)), false);
        smartVaultStrategies = smartVaultManager.strategies(address(smartVault));

        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(
            generateDhwParameterBag(Arrays.toArray(address(strategyB), address(strategyC)), assetGroup)
        );
        vm.stopPrank();

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

    function test_removeStrategy_shouldRevertWhenNotCalledByAdmin() public {
        address smartVaultOwner = address(0x123);
        address user = address(0x456);

        smartVaultStrategies = Arrays.toArray(address(strategyA), address(strategyB), address(strategyC));
        vm.mockCall(
            address(riskManager),
            abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
            abi.encode(Arrays.toUint16a16(600, 300, 100))
        );
        vm.startPrank(smartVaultOwner);
        smartVault = smartVaultFactory.deploySmartVault(
            SmartVaultSpecification({
                smartVaultName: "MySmartVault",
                svtSymbol: "MSV",
                baseURI: "https://token-cdn-domain/",
                assetGroupId: assetGroupId,
                actions: new IAction[](0),
                actionRequestTypes: new RequestType[](0),
                guards: new GuardDefinition[][](0),
                guardRequestTypes: new RequestType[](0),
                strategies: smartVaultStrategies,
                strategyAllocation: uint16a16.wrap(0),
                riskTolerance: 4,
                riskProvider: riskProvider,
                managementFeePct: 0,
                depositFeePct: 0,
                allocationProvider: address(allocationProvider),
                performanceFeePct: 0,
                allowRedeemFor: true
            })
        );
        vm.stopPrank();

        address[] memory smartVaultsToRemove = Arrays.toArray(address(smartVault));

        // strategy cannot be removed by user
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SPOOL_ADMIN, user));
        smartVaultManager.removeStrategyFromVaults(smartVaultStrategies[1], smartVaultsToRemove, true);
        // strategy cannot be removed by vault owner
        vm.prank(smartVaultOwner);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SPOOL_ADMIN, smartVaultOwner));
        smartVaultManager.removeStrategyFromVaults(smartVaultStrategies[1], smartVaultsToRemove, true);
        // strategy can be removed by admin
        smartVaultManager.removeStrategyFromVaults(smartVaultStrategies[1], smartVaultsToRemove, true);
    }
}
