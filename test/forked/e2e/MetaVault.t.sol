// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {stdStorage, StdStorage} from "forge-std/Test.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/strategies/AaveV2Strategy.sol";
import "../../../src/strategies/CompoundV2Strategy.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../../mocks/MockAllocationProvider.sol";
import "../ForkTestFixtureDeployment.sol";

import "@openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/token/ERC20/extensions/ERC20Permit.sol";

import "../../../src/MetaVault.sol";
import "../../../src/interfaces/IMetaVault.sol";
import "../../../src/MetaVaultGuard.sol";
import "../../../src/MetaVaultFactory.sol";
import "../../../src/libraries/ListMap.sol";
import "../../../src/managers/DepositManager.sol";
import "../../../src/managers/WithdrawalManager.sol";

import "../../utils/SigUtils.sol";
import "../../utils/SigUtilsDai.sol";

import "forge-std/console.sol";

contract MetaVaultTest is ForkTestFixtureDeployment {
    using stdStorage for StdStorage;

    MockAllocationProvider public mockAllocationProvider;
    MetaVault public metaVault;
    ISmartVault[] public vaults;
    address public vault1;
    address public vault2;

    MetaVaultGuard metaVaultGuard;
    MetaVaultFactory metaVaultFactory;

    address[] public strategies;

    address owner = address(0x19);
    address user1 = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        _deploy(Extended.INITIAL); // deploy just initial strategies

        mockAllocationProvider = new MockAllocationProvider();
        vm.startPrank(_spoolAdmin);
        _deploySpool.spoolAccessControl().grantRole(ROLE_ALLOCATION_PROVIDER, address(mockAllocationProvider));
        _deploySpool.spoolAccessControl().grantRole(ROLE_DO_HARD_WORKER, address(this));
        _deploySpool.spoolAccessControl().grantRole(ROLE_META_VAULT_DEPLOYER, owner);
        vm.stopPrank();

        uint256 assetGroupIdUSDC = _getAssetGroupId(USDC_KEY);

        address strategy1 = _getStrategyAddress(AAVE_V2_KEY, assetGroupIdUSDC);
        address strategy2 = _getStrategyAddress(COMPOUND_V2_KEY, assetGroupIdUSDC);
        strategies.push(strategy1);
        strategies.push(strategy2);

        uint16a16 allocations = uint16a16Lib.set(uint16a16.wrap(0), Arrays.toArray(FULL_PERCENT));
        vault1 = address(_createVault(assetGroupIdUSDC, Arrays.toArray(strategy1), allocations, address(0), 0, 0, 100));
        vault2 = address(_createVault(assetGroupIdUSDC, Arrays.toArray(strategy2), allocations, address(0), 0, 0, 100));

        vaults.push(ISmartVault(vault1));
        vaults.push(ISmartVault(vault2));

        _dealTokens(user1);
        _dealTokens(user2);
        _dealTokens(owner);

        metaVaultGuard =
            new MetaVaultGuard(_smartVaultManager, _deploySpool.assetGroupRegistry(), _deploySpool.guardManager());

        address metaVaultImpl = address(
            new MetaVault(
                _smartVaultManager, _deploySpool.spoolAccessControl(), metaVaultGuard, _deploySpool.spoolLens()
            )
        );
        metaVaultFactory =
            new MetaVaultFactory(metaVaultImpl, _deploySpool.spoolAccessControl(), _deploySpool.assetGroupRegistry());
        vm.startPrank(owner);
        metaVault =
            metaVaultFactory.deployMetaVault(address(usdc), "MetaVault", "M", new address[](0), new uint256[](0));
        vm.stopPrank();

        vm.startPrank(user1);
        usdc.approve(address(metaVault), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(user2);
        usdc.approve(address(metaVault), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);
        usdc.approve(address(metaVault), type(uint256).max);
        vm.stopPrank();
    }

    function setVaults(uint256 allocation1, uint256 allocation2) internal {
        address[] memory v = new address[](2);
        v[0] = address(vault1);
        v[1] = address(vault2);
        uint256[] memory allocations = new uint256[](2);
        allocations[0] = allocation1;
        allocations[1] = allocation2;
        vm.startPrank(owner);
        metaVault.addSmartVaults(v, allocations);
        vm.stopPrank();
        reallocate();
    }

    function changeAllocation(uint256 allocation1, uint256 allocation2) internal {
        uint256[] memory allocations = new uint256[](2);
        allocations[0] = allocation1;
        allocations[1] = allocation2;
        vm.startPrank(owner);
        metaVault.setSmartVaultAllocations(allocations);
        vm.stopPrank();
    }

    function reallocate() internal {
        uint256[][][] memory slippages = new uint256[][][](2);
        slippages[0] = new uint256[][](1);
        slippages[1] = new uint256[][](1);
        metaVault.reallocate(slippages);
    }

    function assertVaultBalance(address vault, uint256 balance) internal {
        address[] memory v = new address[](1);
        v[0] = vault;
        (uint256 totalBalance,) = metaVault.getBalances(v);
        assertApproxEqAbs(totalBalance, balance, 3);
    }

    function test_addSmartVaults() external {
        // owner can add smart vault
        {
            address[] memory v = new address[](1);
            v[0] = address(vault1);
            uint256[] memory allocations = new uint256[](1);
            allocations[0] = 100_00;
            vm.startPrank(owner);
            metaVault.addSmartVaults(v, allocations);
            vm.stopPrank();
            assertEq(metaVault.getSmartVaults(), v);
        }
        // owner cannot add the same vault second time
        {
            address[] memory v = new address[](1);
            v[0] = address(vault1);
            uint256[] memory allocations = new uint256[](2);
            allocations[0] = 50_00;
            allocations[1] = 50_00;
            vm.startPrank(owner);
            vm.expectRevert(ListMap.ElementAlreadyInList.selector);
            metaVault.addSmartVaults(v, allocations);
            vm.stopPrank();
        }
        // not owner cannot add vault
        {
            address[] memory v = new address[](1);
            v[0] = address(vault2);
            uint256[] memory allocations = new uint256[](2);
            allocations[0] = 50_00;
            allocations[1] = 50_00;
            vm.expectRevert("Ownable: caller is not the owner");
            metaVault.addSmartVaults(v, allocations);
        }
        // max amount of managed vaults cannot exceed MAX_SMART_VAULT_AMOUNT
        {
            uint256 vaultsToAddAmount = metaVault.MAX_SMART_VAULT_AMOUNT() - metaVault.getSmartVaults().length + 1;
            address[] memory vaultsToAdd = new address[](vaultsToAddAmount);
            uint256 assetGroup = _getAssetGroupId(USDC_KEY);
            for (uint256 i; i < vaultsToAddAmount; i++) {
                vaultsToAdd[i] = address(
                    _createVault(
                        assetGroup,
                        Arrays.toArray(_getStrategyAddress(AAVE_V2_KEY, assetGroup)),
                        uint16a16Lib.set(uint16a16.wrap(0), Arrays.toArray(FULL_PERCENT)),
                        address(0),
                        0,
                        0,
                        100
                    )
                );
            }
            vm.startPrank(owner);
            vm.expectRevert(IMetaVault.MaxSmartVaultAmount.selector);
            metaVault.addSmartVaults(vaultsToAdd, new uint256[](1));
            vm.stopPrank();
        }
    }

    function test_setSmartVaultAllocations() external {
        setVaults(50_00, 50_00);
        //  owner cannot set wrong allocation
        {
            uint256[] memory allocations = new uint256[](2);
            allocations[0] = 50_00;
            allocations[1] = 40_00;
            vm.startPrank(owner);
            vm.expectRevert(IMetaVault.WrongAllocation.selector);
            metaVault.setSmartVaultAllocations(allocations);
            vm.stopPrank();
        }
        //  owner cannot set wrong allocation
        {
            uint256[] memory allocations = new uint256[](1);
            allocations[0] = 100_00;
            vm.startPrank(owner);
            vm.expectRevert(IMetaVault.ArgumentLengthMismatch.selector);
            metaVault.setSmartVaultAllocations(allocations);
            vm.stopPrank();
        }
        //  owner cannot set wrong allocation
        {
            uint256[] memory allocations = new uint256[](3);
            allocations[0] = 20_00;
            allocations[1] = 30_00;
            allocations[2] = 50_00;
            vm.startPrank(owner);
            vm.expectRevert(IMetaVault.ArgumentLengthMismatch.selector);
            metaVault.setSmartVaultAllocations(allocations);
            vm.stopPrank();
        }
        //  not owner cannot change allocation
        {
            uint256[] memory allocations = new uint256[](2);
            allocations[0] = 10_00;
            allocations[1] = 90_00;
            vm.expectRevert("Ownable: caller is not the owner");
            metaVault.setSmartVaultAllocations(allocations);
        }
    }

    function test_deposit() external {
        vm.startPrank(user1);
        metaVault.deposit(100e6);
        vm.stopPrank();
        assertEq(metaVault.balanceOf(user1), 0);
        assertEq(metaVault.userToFlushToDepositedAssets(user1, 0), 100e6);
        assertEq(metaVault.flushToDepositedAssets(0), 100e6);
        assertEq(metaVault.totalSupply(), 0);

        vm.startPrank(user1);
        metaVault.deposit(20e6);
        vm.stopPrank();
        assertEq(metaVault.balanceOf(user1), 0);
        assertEq(metaVault.userToFlushToDepositedAssets(user1, 0), 120e6);
        assertEq(metaVault.flushToDepositedAssets(0), 120e6);
        assertEq(metaVault.totalSupply(), 0);

        vm.startPrank(user2);
        metaVault.deposit(30e6);
        vm.stopPrank();
        assertEq(metaVault.balanceOf(user2), 0);
        assertEq(metaVault.userToFlushToDepositedAssets(user2, 0), 30e6);
        assertEq(metaVault.flushToDepositedAssets(0), 150e6);
        assertEq(metaVault.totalSupply(), 0);
    }

    function test_claim() external {
        setVaults(50_00, 50_00);

        vm.startPrank(user1);
        metaVault.deposit(100e6);
        vm.stopPrank();
        vm.startPrank(user2);
        metaVault.deposit(50e6);
        vm.stopPrank();

        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        vm.startPrank(address(0x123456));
        vm.expectRevert(IMetaVault.NothingToClaim.selector);
        metaVault.claim(0);
        vm.stopPrank();

        vm.startPrank(user1);
        metaVault.claim(0);
        // it is not possible to claim second time
        vm.expectRevert(IMetaVault.NothingToClaim.selector);
        metaVault.claim(0);
        vm.stopPrank();
        vm.startPrank(user2);
        metaVault.claim(0);
        // it is not possible to claim second time
        vm.expectRevert(IMetaVault.NothingToClaim.selector);
        metaVault.claim(0);
        vm.stopPrank();

        assertEq(metaVault.userToFlushToDepositedAssets(user1, 0), 0);
        assertEq(metaVault.userToFlushToDepositedAssets(user2, 0), 0);
        assertEq(metaVault.balanceOf(user1), 100e6);
        assertEq(metaVault.balanceOf(user2), 50e6);

        vm.startPrank(user1);
        metaVault.deposit(100e6);
        vm.stopPrank();
        vm.startPrank(user2);
        metaVault.deposit(50e6);
        vm.stopPrank();

        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        vm.startPrank(user1);
        metaVault.claim(1);
        vm.stopPrank();
        vm.startPrank(user2);
        metaVault.claim(1);
        vm.stopPrank();

        assertApproxEqAbs(metaVault.balanceOf(user1), 200e6, 2);
        assertApproxEqAbs(metaVault.balanceOf(user2), 100e6, 2);
    }

    function test_redeem() external {
        setVaults(50_00, 50_00);

        vm.startPrank(user1);
        metaVault.deposit(100e6);
        vm.stopPrank();

        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        vm.startPrank(user1);
        metaVault.claim(0);
        metaVault.redeem(20e6);
        vm.stopPrank();

        assertEq(metaVault.balanceOf(user1), 80e6);
        assertEq(metaVault.flushToDepositedAssets(0), 100e6);
        assertEq(metaVault.totalSupply(), 80e6);
        assertEq(metaVault.userToFlushToRedeemedShares(user1, 1), 20e6);
        assertEq(usdc.balanceOf(address(metaVault)), 0);

        vm.startPrank(user1);
        metaVault.redeem(10e6);
        vm.stopPrank();

        assertEq(metaVault.balanceOf(user1), 70e6);
        assertEq(metaVault.totalSupply(), 70e6);
        assertEq(metaVault.userToFlushToRedeemedShares(user1, 1), 30e6);
        assertEq(usdc.balanceOf(address(metaVault)), 0);
    }

    function test_withdraw() external {
        setVaults(50_00, 50_00);

        vm.startPrank(user1);
        metaVault.deposit(100e6);
        vm.stopPrank();
        vm.startPrank(user2);
        metaVault.deposit(200e6);
        vm.stopPrank();

        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        vm.startPrank(user1);
        metaVault.claim(0);
        metaVault.redeem(20e6);
        vm.stopPrank();
        vm.startPrank(user2);
        metaVault.claim(0);
        metaVault.redeem(10e6);
        vm.stopPrank();

        // cannot withdraw before redeem request is fulfilled
        vm.startPrank(user1);
        vm.expectRevert(IMetaVault.NothingToWithdraw.selector);
        metaVault.withdraw(2);
        vm.stopPrank();

        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        assertApproxEqAbs(usdc.balanceOf(address(metaVault)), 30e6, 2);

        // random user cannot withdraw anything if he has not requested
        vm.startPrank(address(0x98765));
        vm.expectRevert(IMetaVault.NothingToWithdraw.selector);
        metaVault.withdraw(1);
        vm.stopPrank();

        uint256 user1BalanceBefore = usdc.balanceOf(user1);
        vm.startPrank(user1);
        metaVault.withdraw(1);
        // cannot withdraw second time
        vm.expectRevert(IMetaVault.NothingToWithdraw.selector);
        metaVault.withdraw(1);
        vm.stopPrank();

        assertEq(metaVault.balanceOf(user1), 80e6);
        assertEq(metaVault.totalSupply(), 270e6);
        assertEq(usdc.balanceOf(address(metaVault)), 10e6);
        assertEq(metaVault.userToFlushToRedeemedShares(user1, 1), 0);

        uint256 user1BalanceAfter = usdc.balanceOf(user1);
        assertApproxEqAbs(user1BalanceAfter - user1BalanceBefore, 20e6, 2);

        uint256 user2BalanceBefore = usdc.balanceOf(user2);
        vm.startPrank(user2);
        metaVault.withdraw(1);
        vm.stopPrank();

        assertEq(metaVault.balanceOf(user2), 190e6);
        assertEq(metaVault.totalSupply(), 270e6);
        assertApproxEqAbs(usdc.balanceOf(address(metaVault)), 0, 1);

        uint256 user2BalanceAfter = usdc.balanceOf(user2);
        assertApproxEqAbs(user2BalanceAfter - user2BalanceBefore, 10e6, 2);
    }

    function test_flush_deposits_only() external {
        setVaults(91_00, 9_00);

        vm.startPrank(user1);
        metaVault.deposit(100e6);
        vm.stopPrank();

        metaVault.flush();

        assertEq(metaVault.flushToDepositedAssets(0), 100e6);
        assertEq(usdc.balanceOf(address(metaVault)), 0);
        assertVaultBalance(vault1, 0);
        assertVaultBalance(vault2, 0);
        assertTrue(metaVault.smartVaultToDepositNftId(vault1) == 1);
        assertTrue(metaVault.smartVaultToDepositNftId(vault2) == 1);
        assertEq(metaVault.smartVaultToDepositNftIdFromReallocation(vault1), 0);
        assertEq(metaVault.smartVaultToDepositNftIdFromReallocation(vault2), 0);

        // second flushDeposit is blocked until previous one is not synced
        vm.expectRevert(IMetaVault.PendingSync.selector);
        metaVault.flush();
    }

    function test_sync_deposit_only() external {
        setVaults(91_00, 9_00);

        vm.startPrank(user1);
        metaVault.deposit(100e6);
        vm.stopPrank();

        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        assertVaultBalance(vault1, 91e6);
        assertVaultBalance(vault2, 9e6);

        assertTrue(metaVault.smartVaultToDepositNftId(vault1) == 0);
        assertTrue(metaVault.smartVaultToDepositNftId(vault2) == 0);
        assertApproxEqAbs(ISmartVault(vault1).balanceOf(address(metaVault)), 91e21, 1e20);
        assertApproxEqAbs(ISmartVault(vault2).balanceOf(address(metaVault)), 9e21, 1e20);
    }

    function test_flush_withdrawal_only() external {
        setVaults(90_00, 10_00);

        {
            (uint128 flush, uint128 sync) = metaVault.index();
            assertEq(flush, 0);
            assertEq(sync, 0);
        }
        metaVault.flush();
        {
            (uint128 flush, uint128 sync) = metaVault.index();
            assertEq(flush, 0);
            assertEq(sync, 0);
        }

        vm.startPrank(user1);
        metaVault.deposit(100e6);
        vm.stopPrank();

        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        vm.startPrank(user1);
        metaVault.claim(0);
        metaVault.redeem(10e6);
        vm.stopPrank();

        metaVault.flush();

        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);

        {
            (uint128 flush, uint128 sync) = metaVault.index();
            assertEq(flush, 2);
            assertEq(sync, 1);
        }
        assertVaultBalance(vault1, 81e6);
        assertVaultBalance(vault2, 9e6);
        assertEq(metaVault.flushToSmartVaultToWithdrawalNftId(1, vault1), MAXIMAL_DEPOSIT_ID + 1);
        assertEq(metaVault.flushToSmartVaultToWithdrawalNftId(1, vault2), MAXIMAL_DEPOSIT_ID + 1);
    }

    function test_sync_withdraw_only() external {
        setVaults(90_00, 10_00);

        uint256 toRedeem = 10e6;

        vm.startPrank(user1);
        metaVault.deposit(100e6);
        vm.stopPrank();
        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        vm.startPrank(user1);
        metaVault.claim(0);
        metaVault.redeem(toRedeem);
        vm.stopPrank();
        metaVault.flush();

        assertEq(metaVault.flushToWithdrawnAssets(1), 0);
        assertEq(usdc.balanceOf(address(metaVault)), 0);

        // syncing withdrawal is not possible if DHW has not run
        vm.expectRevert(abi.encodeWithSelector(WithdrawalNftNotSyncedYet.selector, MAXIMAL_DEPOSIT_ID + 1));
        metaVault.sync();

        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        assertApproxEqAbs(metaVault.flushToWithdrawnAssets(1), toRedeem, 1);
        assertEq(metaVault.flushToSmartVaultToWithdrawalNftId(1, vault1), 0);
        assertEq(metaVault.flushToSmartVaultToWithdrawalNftId(1, vault2), 0);
        assertApproxEqAbs(usdc.balanceOf(address(metaVault)), toRedeem, 1);
    }

    function test_reallocate() external {
        setVaults(90_00, 10_00);

        vm.startPrank(user1);
        metaVault.deposit(100e6);
        vm.stopPrank();

        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        // first reallocation
        {
            changeAllocation(50_00, 50_00);

            {
                (uint128 index, uint128 syncIndex) = metaVault.reallocationIndex();
                assertEq(index, 0);
                assertEq(syncIndex, 0);
            }

            reallocate();

            assertTrue(metaVault.smartVaultToDepositNftId(vault1) == 0);
            assertTrue(metaVault.smartVaultToDepositNftId(vault2) == 0);
            assertEq(metaVault.smartVaultToDepositNftIdFromReallocation(vault1), 0);
            assertTrue(metaVault.smartVaultToDepositNftIdFromReallocation(vault2) > 0);
            {
                (uint128 index, uint128 syncIndex) = metaVault.reallocationIndex();
                assertEq(index, 1);
                assertEq(syncIndex, 0);
            }

            vm.expectRevert(IMetaVault.PendingSync.selector);
            reallocate();

            _flushVaults(ISmartVault(vault2));
            _dhw(strategies);
            _syncVaults(ISmartVault(vault2));

            metaVault.reallocateSync();

            assertTrue(metaVault.smartVaultToDepositNftId(vault1) == 0);
            assertTrue(metaVault.smartVaultToDepositNftId(vault2) == 0);
            assertEq(metaVault.smartVaultToDepositNftIdFromReallocation(vault1), 0);
            assertEq(metaVault.smartVaultToDepositNftIdFromReallocation(vault2), 0);
            {
                (uint128 index, uint128 syncIndex) = metaVault.reallocationIndex();
                assertEq(index, 1);
                assertEq(syncIndex, 1);
            }

            assertApproxEqAbs(ISmartVault(vault1).balanceOf(address(metaVault)), 50e21, 1e20);
            assertApproxEqAbs(ISmartVault(vault2).balanceOf(address(metaVault)), 50e21, 1e20);
            assertEq(usdc.balanceOf(address(metaVault)), 0);

            assertVaultBalance(vault1, 50e6);
            assertVaultBalance(vault2, 50e6);
        }

        // second reallocation
        {
            changeAllocation(15_00, 85_00);

            reallocate();

            _flushVaults(ISmartVault(vault2));
            _dhw(strategies);
            _syncVaults(ISmartVault(vault2));

            metaVault.reallocateSync();

            assertApproxEqAbs(ISmartVault(vault1).balanceOf(address(metaVault)), 15e21, 1e20);
            assertApproxEqAbs(ISmartVault(vault2).balanceOf(address(metaVault)), 85e21, 1e20);
            assertEq(usdc.balanceOf(address(metaVault)), 0);

            assertVaultBalance(vault1, 15e6);
            assertVaultBalance(vault2, 85e6);
        }

        // third reallocation
        {
            changeAllocation(100_00, 0);

            reallocate();

            // vault with zero allocation will be removed on reallocation
            {
                address[] memory v = metaVault.getSmartVaults();
                assertEq(v.length, 1);
                assertEq(v[0], vault1);
            }

            _flushVaults(ISmartVault(vault1));
            _dhw(strategies);
            _syncVaults(ISmartVault(vault1));

            metaVault.reallocateSync();

            assertApproxEqAbs(ISmartVault(vault1).balanceOf(address(metaVault)), 100e21, 1e20);
            assertEq(ISmartVault(vault2).balanceOf(address(metaVault)), 0);
            assertEq(usdc.balanceOf(address(metaVault)), 0);

            assertVaultBalance(vault1, 100e6);
            assertVaultBalance(vault2, 0);
        }
    }

    function test_reallocate_viewOnly() external {
        setVaults(90_00, 10_00);
        uint256[][][] memory slippages = new uint256[][][](2);
        slippages[0] = new uint256[][](1);
        slippages[1] = new uint256[][](1);

        vm.startPrank(user1);
        metaVault.deposit(100e6);
        vm.stopPrank();

        metaVault.flush();

        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);

        metaVault.sync();

        // first reallocation
        {
            changeAllocation(50_00, 50_00);
            vm.startPrank(address(0), address(0));
            vm.recordLogs();
            metaVault.reallocate(slippages);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            assertEq(entries.length, 1);
            assertEq(entries[0].topics.length, 1);
            assertEq(entries[0].topics[0], keccak256("SvtToRedeem(address,uint256)"));
            (address vault, uint256 amount) = abi.decode(entries[0].data, (address, uint256));
            assertEq(vault, vault1);
            assertApproxEqAbs(amount, 40e21, 1e20);
            vm.stopPrank();
        }

        // second reallocation
        {
            changeAllocation(100_00, 0);
            vm.startPrank(address(0), address(0));
            vm.recordLogs();
            metaVault.reallocate(slippages);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            assertEq(entries.length, 1);
            assertEq(entries[0].topics.length, 1);
            assertEq(entries[0].topics[0], keccak256("SvtToRedeem(address,uint256)"));
            (address vault, uint256 amount) = abi.decode(entries[0].data, (address, uint256));
            assertEq(vault, vault2);
            assertApproxEqAbs(amount, 10e21, 1e20);
            vm.stopPrank();
        }
    }

    function test_multicall() external {
        setVaults(50_00, 50_00);

        vm.startPrank(user1);
        metaVault.deposit(100e6);
        vm.stopPrank();

        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        vm.startPrank(user1);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(IMetaVault.claim.selector, 0);
        data[1] = abi.encodeWithSelector(IMetaVault.redeem.selector, 20e6);
        metaVault.multicall(data);

        assertEq(metaVault.balanceOf(user1), 80e6);
        assertEq(metaVault.totalSupply(), 80e6);
        assertEq(metaVault.userToFlushToRedeemedShares(user1, 1), 20e6);
        assertEq(usdc.balanceOf(address(metaVault)), 0);
    }

    function test_pausing() external {
        bytes4 depositSelector = bytes4(keccak256(abi.encodePacked("deposit(uint256)")));

        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_PAUSER, address(this)));
        metaVault.setPaused(depositSelector, true);

        assertFalse(metaVault.selectorToPaused(depositSelector));

        vm.startPrank(_spoolAdmin);
        _deploySpool.spoolAccessControl().grantRole(ROLE_PAUSER, address(this));
        vm.stopPrank();

        metaVault.setPaused(depositSelector, true);
        assertTrue(metaVault.selectorToPaused(depositSelector));

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(IMetaVault.Paused.selector, depositSelector));
        metaVault.deposit(1);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_UNPAUSER, address(this)));
        metaVault.setPaused(depositSelector, false);

        vm.startPrank(_spoolAdmin);
        _deploySpool.spoolAccessControl().grantRole(ROLE_UNPAUSER, address(this));
        vm.stopPrank();

        metaVault.setPaused(depositSelector, false);
        assertFalse(metaVault.selectorToPaused(depositSelector));

        vm.startPrank(user1);
        metaVault.deposit(1);
        vm.stopPrank();
    }

    function test_depositUsdcWithPermit() external {
        ERC20Permit asset = ERC20Permit(address(usdc));
        SigUtils sigUtils = new SigUtils(asset.DOMAIN_SEPARATOR());
        uint256 userPrivateKey = 0xA11CE;
        address userAddress = vm.addr(userPrivateKey);

        _dealTokens(userAddress);

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: userAddress,
            spender: address(metaVault),
            value: 1e6,
            nonce: asset.nonces(userAddress),
            deadline: block.timestamp + 1 minutes
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        assertEq(usdc.allowance(userAddress, address(metaVault)), 0);
        assertEq(usdc.balanceOf(address(metaVault)), 0);
        uint256 userBalanceBefore = usdc.balanceOf(userAddress);

        vm.startPrank(userAddress);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(IMetaVault.permitAsset.selector, permit.value, permit.deadline, v, r, s);
        data[1] = abi.encodeWithSelector(bytes4(keccak256(abi.encodePacked("deposit(uint256)"))), permit.value);
        metaVault.multicall(data);
        vm.stopPrank();

        assertEq(usdc.allowance(userAddress, address(metaVault)), 0);
        assertEq(usdc.balanceOf(address(metaVault)), permit.value);

        uint256 userBalanceAfter = usdc.balanceOf(userAddress);

        assertEq(userBalanceBefore - userBalanceAfter, permit.value);
    }

    function test_depositDaiWithPermit() external {
        vm.startPrank(owner);
        MetaVault metaVault2 =
            metaVaultFactory.deployMetaVault(address(dai), "MetaVault", "M", new address[](0), new uint256[](0));
        vm.stopPrank();

        ERC20Permit asset = ERC20Permit(address(dai));
        SigUtilsDai sigUtils = new SigUtilsDai(asset.DOMAIN_SEPARATOR());
        uint256 userPrivateKey = 0xA11CE;
        address userAddress = vm.addr(userPrivateKey);

        _dealTokens(userAddress);

        uint256 nonce = asset.nonces(userAddress);
        uint256 deadline = block.timestamp + 1 minutes;

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPrivateKey, sigUtils.getTypedDataHash(userAddress, address(metaVault2), nonce, deadline, true));

        assertEq(dai.allowance(userAddress, address(metaVault2)), 0);
        assertEq(dai.balanceOf(address(metaVault2)), 0);
        uint256 userBalanceBefore = dai.balanceOf(userAddress);

        uint256 amount = 1e18;
        {
            vm.startPrank(userAddress);
            bytes[] memory data = new bytes[](2);
            //  permitDai(uint256 nonce, uint256 deadline, bool allowed, uint8 v, bytes32 r, bytes32 s)
            data[0] = abi.encodeWithSelector(IMetaVault.permitDai.selector, nonce, deadline, true, v, r, s);
            data[1] = abi.encodeWithSelector(bytes4(keccak256(abi.encodePacked("deposit(uint256)"))), amount);
            metaVault2.multicall(data);
            vm.stopPrank();
        }

        assertEq(dai.allowance(userAddress, address(metaVault2)), type(uint256).max);
        assertEq(dai.balanceOf(address(metaVault2)), amount);

        assertEq(userBalanceBefore - dai.balanceOf(userAddress), amount);
    }

    function _createVault(
        uint256 assetGroupId,
        address[] memory strategies_,
        uint16a16 allocations,
        address allocationProvider,
        uint16 managementFeePct,
        uint16 depositFeePct,
        uint16 performanceFeePct
    ) internal returns (ISmartVault smartVault) {
        address riskProvider = _riskProvider;

        if (uint16a16.unwrap(allocations) > 0) {
            riskProvider = address(0);
        }

        smartVault = _deploySpool.smartVaultFactory().deploySmartVault(
            SmartVaultSpecification({
                smartVaultName: "MySmartVault",
                svtSymbol: "MSV",
                baseURI: "https://token-cdn-domain/",
                assetGroupId: assetGroupId,
                actions: new IAction[](0),
                actionRequestTypes: new RequestType[](0),
                guards: new GuardDefinition[][](0),
                guardRequestTypes: new RequestType[](0),
                strategies: strategies_,
                strategyAllocation: allocations,
                riskTolerance: 0,
                riskProvider: riskProvider,
                managementFeePct: managementFeePct,
                depositFeePct: depositFeePct,
                allocationProvider: allocationProvider,
                performanceFeePct: performanceFeePct,
                allowRedeemFor: false
            })
        );
    }
}
