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

struct TestBag {
    SmartVaultFees fees;
    SwapInfo[][] dhwSwapInfo;
    uint256[] depositAmounts;
    address vaultOwner;
}

contract VaultSyncTest is IntegrationTestFixture {
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

    function test_syncVault_oneDeposit() public {
        createVault(2_00, 0, 0);
        TestBag memory bag;
        bag.fees = SmartVaultFees(2_00, 0, 0);
        bag.depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        vm.startPrank(alice);

        tokenA.approve(address(smartVaultManager), 100 ether);
        tokenB.approve(address(smartVaultManager), 100 ether);
        tokenC.approve(address(smartVaultManager), 500 ether);

        smartVaultManager.deposit(DepositBag(address(smartVault), bag.depositAmounts, alice, address(0), true));

        vm.stopPrank();

        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroup));
        vm.stopPrank();
        uint256 dhwTimestamp = block.timestamp;

        DepositSyncResult memory syncResult = depositManager.syncDepositsSimulate(
            SimulateDepositParams(
                address(smartVault),
                [uint256(0), 0, 0], // flush index, first dhw timestamp, total SVTs minted til now
                smartVaultStrategies,
                assetGroup,
                Arrays.toUint16a16(1, 1, 1),
                Arrays.toUint16a16(0, 0, 0),
                bag.fees
            )
        );
        smartVaultManager.syncSmartVault(address(smartVault), true);

        uint256 totalSupply = smartVault.totalSupply();

        assertEq(strategyA.totalSupply(), syncResult.sstShares[0]);
        assertEq(strategyB.totalSupply(), syncResult.sstShares[1]);
        assertEq(strategyC.totalSupply(), syncResult.sstShares[2]);
        assertEq(syncResult.sstShares[0], 214297693046938776377950000);
        assertEq(syncResult.sstShares[1], 107148831538266256993250000);
        assertEq(syncResult.sstShares[2], 35716275414794966628800000);
        assertEq(syncResult.mintedSVTs, totalSupply);
        assertEq(syncResult.mintedSVTs, 357162800000000000000000000);
        assertEq(syncResult.dhwTimestamp, dhwTimestamp);
        assertEq(smartVault.totalSupply(), smartVaultManager.getSVTTotalSupply(address(smartVault)));

        uint256 vaultOwnerBalance = smartVault.balanceOf(accessControl.smartVaultOwner(address(smartVault)));
        assertEq(vaultOwnerBalance, 0);
    }

    function test_syncVault_managementFees() public {
        createVault(2_00, 0, 0);
        TestBag memory bag;
        bag.fees = SmartVaultFees(2_00, 0, 0);
        bag.vaultOwner = accessControl.smartVaultOwner(address(smartVault));
        bag.depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        vm.startPrank(alice);

        // Deposit #1 and DHW
        smartVaultManager.deposit(DepositBag(address(smartVault), bag.depositAmounts, alice, address(0), true));
        vm.stopPrank();

        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroup));
        vm.stopPrank();
        uint256 dhwTimestamp = block.timestamp;

        skip(30 * 24 * 60 * 60); // 1 month

        // Sync previous DHW and make a new deposit
        vm.prank(alice);
        smartVaultManager.deposit(DepositBag(address(smartVault), bag.depositAmounts, alice, address(0), true));

        // Should have no fees after syncing first DHW
        assertEq(smartVault.balanceOf(bag.vaultOwner), 0);

        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroup));
        vm.stopPrank();

        uint256 dhw2Timestamp = block.timestamp;
        uint256 vaultSupplyBefore = smartVault.totalSupply();

        uint16a16 dhwIndexes = smartVaultManager.dhwIndexes(address(smartVault), 1);
        DepositSyncResult memory syncResult = depositManager.syncDepositsSimulate(
            SimulateDepositParams(
                address(smartVault),
                [1, dhwTimestamp, vaultSupplyBefore],
                smartVaultStrategies,
                assetGroup,
                dhwIndexes,
                uint16a16.wrap(0),
                bag.fees
            )
        );

        // Sync second DHW
        smartVaultManager.syncSmartVault(address(smartVault), true);
        uint256 vaultOwnerBalance = smartVault.balanceOf(bag.vaultOwner);
        uint256 simulatedTotalSupply = smartVaultManager.getSVTTotalSupply(address(smartVault));

        // Should have management fees after syncing second DHW
        assertEq(vaultSupplyBefore, 357162800000000000000000000);
        assertEq(syncResult.dhwTimestamp, dhw2Timestamp);
        assertEq(smartVault.totalSupply(), simulatedTotalSupply);
        assertGt(vaultOwnerBalance, 0);
        assertGt(syncResult.mintedSVTs, 0);
        assertEq(smartVault.totalSupply(), vaultSupplyBefore + syncResult.mintedSVTs + vaultOwnerBalance);
    }

    function test_syncVault_depositFees() public {
        createVault(0, 3_00, 0);

        {
            vm.startPrank(alice);

            uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

            // Deposit #1 and DHW
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), true));
            vm.stopPrank();

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroup));
            vm.stopPrank();
        }

        // Run simulations
        uint16a16 dhwIndexes = smartVaultManager.dhwIndexes(address(smartVault), 0);

        DepositSyncResult memory syncResult = depositManager.syncDepositsSimulate(
            SimulateDepositParams(
                address(smartVault),
                [uint256(0), 0, 0],
                smartVaultStrategies,
                assetGroup,
                dhwIndexes,
                uint16a16.wrap(0),
                SmartVaultFees(0, 3_00, 0)
            )
        );

        uint256 simulatedTotalSupply = smartVaultManager.getSVTTotalSupply(address(smartVault));
        address vaultOwner = accessControl.smartVaultOwner(address(smartVault));
        uint256 ownerBalance = smartVaultManager.getUserSVTBalance(address(smartVault), vaultOwner);

        // Sync previous DHW
        smartVaultManager.syncSmartVault(address(smartVault), true);

        // Should have deposit fees, after syncing first DHW
        uint256 mintedSVTs = 357162800000000000000000000;
        uint256 depositFee = mintedSVTs * 3_00 / 100_00;
        uint256 totalSupply = smartVault.totalSupply();
        assertEq(smartVault.balanceOf(vaultOwner), depositFee);
        assertEq(ownerBalance, depositFee);
        assertEq(totalSupply, mintedSVTs);
        assertEq(smartVault.totalSupply(), simulatedTotalSupply);
        assertEq(syncResult.mintedSVTs, mintedSVTs - depositFee);
    }

    function test_syncVault_performanceFees() public {
        uint16 vaultPerformanceFee = 10_00;
        createVault(0, 0, vaultPerformanceFee);

        {
            vm.startPrank(alice);

            uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

            // Deposit #1 and DHW
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), true));
            vm.stopPrank();

            DoHardWorkParameterBag memory dhwBag = generateDhwParameterBag(smartVaultStrategies, assetGroup);
            dhwBag.baseYields[0][0] = YIELD_FULL_PERCENT_INT / 10;
            dhwBag.baseYields[0][1] = YIELD_FULL_PERCENT_INT / 10;
            dhwBag.baseYields[0][2] = YIELD_FULL_PERCENT_INT / 10;

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(dhwBag);
            vm.stopPrank();
        }

        // Run simulations
        uint16a16 dhwIndexes = smartVaultManager.dhwIndexes(address(smartVault), 0);

        uint16a16 dhwIndexesBefore = uint16a16.wrap(0xff);

        int256[] memory yieldsBefore = new int256[](3);

        vm.mockCall(
            address(strategyRegistry), abi.encodeCall(StrategyRegistry.strategyAtIndexBatch, (smartVaultStrategies, dhwIndexesBefore, assetGroup.length)), abi.encode(yieldsBefore)
        );

        DepositSyncResult memory syncResult = depositManager.syncDepositsSimulate(
            SimulateDepositParams(
                address(smartVault),
                [uint256(0), 0, 0],
                smartVaultStrategies,
                assetGroup,
                dhwIndexes,
                dhwIndexesBefore,
                SmartVaultFees(0, 0, vaultPerformanceFee)
            )
        );

        uint256 simulatedTotalSupply = smartVaultManager.getSVTTotalSupply(address(smartVault));
        address vaultOwner = accessControl.smartVaultOwner(address(smartVault));
        uint256 ownerBalance = smartVaultManager.getUserSVTBalance(address(smartVault), vaultOwner);

        // Sync previous DHW
        smartVaultManager.syncSmartVault(address(smartVault), true);

        // Should have deposit fees, after syncing first DHW
        uint256 mintedSVTs = 357162800000000000000000000;
        uint256 depositFee = mintedSVTs * vaultPerformanceFee / 100_00;
        uint256 totalSupply = smartVault.totalSupply();
        assertEq(smartVault.balanceOf(vaultOwner), depositFee);
        assertEq(ownerBalance, depositFee);
        assertEq(totalSupply, mintedSVTs);
        assertEq(smartVault.totalSupply(), simulatedTotalSupply);
        assertEq(syncResult.mintedSVTs, mintedSVTs - depositFee);
    }

    function test_depositAndRedeemNFTs() public {
        TestBag memory bag;
        createVault();
        vm.clearMockedCalls();

        bag.fees = SmartVaultFees(0, 0, 0);
        bag.depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        vm.prank(alice);
        uint256 nftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), bag.depositAmounts, alice, address(0), true));

        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroup));
        vm.stopPrank();

        uint256 aliceBalance = smartVaultManager.getUserSVTBalance(address(smartVault), alice);
        vm.startPrank(alice);
        uint256 redeemNftId = smartVaultManager.redeem(
            RedeemBag(address(smartVault), aliceBalance, Arrays.toArray(nftId), Arrays.toArray(NFT_MINTED_SHARES)),
            alice,
            true
        );
        vm.stopPrank();

        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroup));
        vm.stopPrank();

        vm.startPrank(alice);
        (uint256[] memory withdrawnAssets,) = smartVaultManager.claimWithdrawal(
            address(smartVault), Arrays.toArray(redeemNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
        );

        assertEq(withdrawnAssets[0], bag.depositAmounts[0]);
        assertEq(withdrawnAssets[1], bag.depositAmounts[1]);
        assertEq(withdrawnAssets[2], bag.depositAmounts[2]);

        assertEq(smartVault.balanceOf(alice), 0);
        assertEq(smartVault.balanceOf(alice, nftId), 0);
    }
}
