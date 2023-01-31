// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

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
    function setUp() public {
        managementFeePct = 2_000;
        setUpBase();
    }

    function test_syncVault_oneDeposit() public {
        vm.startPrank(alice);

        uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](3);
        dhwSwapInfo[0] = new SwapInfo[](0);
        dhwSwapInfo[1] = new SwapInfo[](0);
        dhwSwapInfo[2] = new SwapInfo[](0);

        tokenA.approve(address(smartVaultManager), 100 ether);
        tokenB.approve(address(smartVaultManager), 100 ether);
        tokenC.approve(address(smartVaultManager), 500 ether);

        smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), true));
        vm.stopPrank();

        strategyRegistry.doHardWork(smartVaultStrategies, dhwSwapInfo);
        uint256 dhwTimestamp = block.timestamp;

        StrategyAtIndex[] memory dhwStates =
            strategyRegistry.strategyAtIndexBatch(smartVaultStrategies, Arrays.toArray(1, 1, 1));
        DepositSyncResult memory res =
            depositManager.syncDepositsSimulate(address(smartVault), 0, smartVaultStrategies, assetGroup, dhwStates);
        smartVaultManager.syncSmartVault(address(smartVault), true);

        uint256 totalSupply = smartVault.totalSupply();

        assertEq(strategyA.totalSupply(), res.sstShares[0]);
        assertEq(strategyB.totalSupply(), res.sstShares[1]);
        assertEq(strategyC.totalSupply(), res.sstShares[2]);
        assertEq(res.sstShares[0], 214297693046938776377950000);
        assertEq(res.sstShares[1], 107148831538266256993250000);
        assertEq(res.sstShares[2], 35716275414794966628800000);
        assertEq(res.mintedSVTs, totalSupply);
        assertEq(res.mintedSVTs, 357162800000000000000000000);
        assertEq(res.lastDhwTimestamp, dhwTimestamp);
        assertEq(smartVault.totalSupply(), smartVaultManager.getSVTTotalSupply(address(smartVault)));

        uint256 vaultOwnerBalance = smartVault.balanceOf(accessControl.smartVaultOwner(address(smartVault)));
        assertEq(vaultOwnerBalance, 0);
    }

    function test_syncVault_managementFees() public {
        address vaultOwner = accessControl.smartVaultOwner(address(smartVault));
        deal(address(tokenA), alice, 1000 ether, true);
        deal(address(tokenB), alice, 1000 ether, true);
        deal(address(tokenC), alice, 1000 ether, true);

        vm.startPrank(alice);

        uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);
        SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](3);
        dhwSwapInfo[0] = new SwapInfo[](0);
        dhwSwapInfo[1] = new SwapInfo[](0);
        dhwSwapInfo[2] = new SwapInfo[](0);

        tokenA.approve(address(smartVaultManager), 1000 ether);
        tokenB.approve(address(smartVaultManager), 1000 ether);
        tokenC.approve(address(smartVaultManager), 1000 ether);

        // Deposit #1 and DHW
        smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), true));
        vm.stopPrank();

        uint256 flushIndex = smartVaultManager.getLatestFlushIndex(address(smartVault));
        assertEq(flushIndex, 1);

        strategyRegistry.doHardWork(smartVaultStrategies, dhwSwapInfo);

        skip(30 * 24 * 60 * 60); // 1 month

        // Sync previous DHW and make a new deposit
        vm.prank(alice);
        smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0), true));
        flushIndex = smartVaultManager.getLatestFlushIndex(address(smartVault));

        assertEq(flushIndex, 2);
        assertEq(smartVault.balanceOf(vaultOwner), 0);

        strategyRegistry.doHardWork(smartVaultStrategies, dhwSwapInfo);
        uint256 dhwTimestamp = block.timestamp;
        uint256 vaultSupplyBefore = smartVault.totalSupply();

        uint256[] memory dhwIndexes = smartVaultManager.dhwIndexes(address(smartVault), 1);
        StrategyAtIndex[] memory dhwStates = strategyRegistry.strategyAtIndexBatch(smartVaultStrategies, dhwIndexes);
        DepositSyncResult memory res =
            depositManager.syncDepositsSimulate(address(smartVault), 1, smartVaultStrategies, assetGroup, dhwStates);

        // Sync second DHW
        smartVaultManager.syncSmartVault(address(smartVault), true);
        uint256 vaultOwnerBalance = smartVault.balanceOf(vaultOwner);
        uint256 simulatedTotalSupply = smartVaultManager.getSVTTotalSupply(address(smartVault));

        assertEq(vaultSupplyBefore, 357162800000000000000000000);
        assertEq(res.lastDhwTimestamp, dhwTimestamp);
        assertEq(smartVault.totalSupply(), simulatedTotalSupply);
        assertGt(vaultOwnerBalance, 0);
        assertGt(res.mintedSVTs, 0);
        assertEq(smartVault.totalSupply(), vaultSupplyBefore + res.mintedSVTs + vaultOwnerBalance);
    }
}
