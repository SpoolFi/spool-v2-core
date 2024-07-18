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

import "../../../src/MetaVault.sol";
import "../../../src/libraries/ListMap.sol";
import "../../../src/managers/DepositManager.sol";
import "../../../src/managers/WithdrawalManager.sol";

import "forge-std/console.sol";

contract MetaVaultTest is ForkTestFixtureDeployment {
    using stdStorage for StdStorage;

    MockAllocationProvider public mockAllocationProvider;
    MetaVault public metaVault;
    ISmartVault[] public vaults;
    address public vault1;
    address public vault2;

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

        vm.startPrank(owner);
        address metaVaultImpl = address(
            new MetaVault(_smartVaultManager, _deploySpool.spoolAccessControl(), _deploySpool.assetGroupRegistry())
        );
        metaVault = MetaVault(address(new ERC1967Proxy(metaVaultImpl, "")));
        metaVault.initialize(address(usdc), "MetaVault", "M");
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
    }

    function changeAllocation(uint256 allocation1, uint256 allocation2) internal {
        uint256[] memory allocations = new uint256[](2);
        allocations[0] = allocation1;
        allocations[1] = allocation2;
        vm.startPrank(owner);
        metaVault.setSmartVaultAllocations(allocations);
        vm.stopPrank();
    }

    function test_smartVaultIsValid() external {
        // same asset group, zero management and deposit fee vault is valid
        assertTrue(metaVault.smartVaultIsValid(address(vault1)));
        assertTrue(metaVault.smartVaultIsValid(address(vault2)));
        // different asset group is not valid
        {
            uint256 assetGroup = _getAssetGroupId(USDT_KEY);
            address vault = address(
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
            vm.expectRevert(MetaVault.InvalidVaultAsset.selector);
            metaVault.smartVaultIsValid(vault);
        }
        // non zero management fee is not valid
        {
            uint256 assetGroup = _getAssetGroupId(USDC_KEY);
            address vault = address(
                _createVault(
                    assetGroup,
                    Arrays.toArray(_getStrategyAddress(AAVE_V2_KEY, assetGroup)),
                    uint16a16Lib.set(uint16a16.wrap(0), Arrays.toArray(FULL_PERCENT)),
                    address(0),
                    10,
                    0,
                    100
                )
            );
            vm.expectRevert(MetaVault.InvalidVaultManagementFee.selector);
            metaVault.smartVaultIsValid(vault);
        }
        // non zero deposit fee is not valid
        {
            uint256 assetGroup = _getAssetGroupId(USDC_KEY);
            address vault = address(
                _createVault(
                    assetGroup,
                    Arrays.toArray(_getStrategyAddress(AAVE_V2_KEY, assetGroup)),
                    uint16a16Lib.set(uint16a16.wrap(0), Arrays.toArray(FULL_PERCENT)),
                    address(0),
                    0,
                    10,
                    100
                )
            );
            vm.expectRevert(MetaVault.InvalidVaultDepositFee.selector);
            metaVault.smartVaultIsValid(vault);
        }
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
            vm.expectRevert(ElementAlreadyInList.selector);
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
            vm.expectRevert(MetaVault.MaxSmartVaultAmount.selector);
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
            vm.expectRevert(MetaVault.WrongAllocation.selector);
            metaVault.setSmartVaultAllocations(allocations);
            vm.stopPrank();
        }
        //  owner cannot set wrong allocation
        {
            uint256[] memory allocations = new uint256[](1);
            allocations[0] = 100_00;
            vm.startPrank(owner);
            vm.expectRevert(MetaVault.ArgumentLengthMismatch.selector);
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
            vm.expectRevert(MetaVault.ArgumentLengthMismatch.selector);
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

    function test_smartVaultSupported() external {
        assertFalse(metaVault.smartVaultSupported(address(vault1)));
        {
            address[] memory v = new address[](1);
            v[0] = address(vault1);
            uint256[] memory allocations = new uint256[](1);
            allocations[0] = 100_00;
            vm.startPrank(owner);
            metaVault.addSmartVaults(v, allocations);
            vm.stopPrank();
        }
        assertTrue(metaVault.smartVaultSupported(address(vault1)));
        assertFalse(metaVault.smartVaultSupported(address(vault2)));
    }

    function test_removeSmartVaults() external {
        setVaults(90_00, 10_00);
        // vault cannot be removed if its allocation is non zero
        {
            address[] memory v = new address[](2);
            v[0] = address(vault1);
            v[1] = address(vault2);
            uint256[] memory allocations = new uint256[](2);
            allocations[0] = 90_00;
            allocations[1] = 10_00;
            vm.startPrank(owner);
            vm.expectRevert(MetaVault.NonZeroAllocation.selector);
            metaVault.removeSmartVaults(v);
            vm.stopPrank();
        }
        // remove vault
        {
            uint256[] memory allocations = new uint256[](2);
            allocations[0] = 0;
            allocations[1] = 100_00;
            vm.startPrank(owner);
            metaVault.setSmartVaultAllocations(allocations);
            address[] memory v = new address[](1);
            v[0] = address(vault1);
            metaVault.removeSmartVaults(v);
            v[0] = address(vault2);
            vm.stopPrank();
            assertEq(metaVault.getSmartVaults(), v);
        }
    }

    function test_mint() external {
        assertEq(metaVault.userToDepositIndex(user1), 0);
        vm.startPrank(user1);
        metaVault.mint(100e6);
        vm.stopPrank();
        assertEq(metaVault.balanceOf(user1), 100e6);
        assertEq(metaVault.availableAssets(), 100e6);
        assertEq(metaVault.totalSupply(), 100e6);
        assertEq(metaVault.userToDepositIndex(user1), 1);

        vm.startPrank(user1);
        metaVault.mint(20e6);
        vm.stopPrank();
        assertEq(metaVault.balanceOf(user1), 120e6);
        assertEq(metaVault.availableAssets(), 120e6);
        assertEq(metaVault.totalSupply(), 120e6);
        assertEq(metaVault.userToDepositIndex(user1), 1);

        assertEq(metaVault.userToDepositIndex(user2), 0);
        vm.startPrank(user2);
        metaVault.mint(30e6);
        vm.stopPrank();
        assertEq(metaVault.balanceOf(user2), 30e6);
        assertEq(metaVault.availableAssets(), 150e6);
        assertEq(metaVault.totalSupply(), 150e6);
        assertEq(metaVault.userToDepositIndex(user2), 1);
    }

    function test_redeem() external {
        setVaults(50_00, 50_00);

        vm.startPrank(user1);
        metaVault.mint(100e6);
        vm.expectRevert(MetaVault.PendingDeposit.selector);
        metaVault.redeem(20e6);
        vm.stopPrank();

        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        vm.startPrank(user1);
        metaVault.redeem(20e6);
        vm.stopPrank();

        assertEq(metaVault.balanceOf(user1), 80e6);
        assertEq(metaVault.availableAssets(), 0);
        assertEq(metaVault.totalSupply(), 80e6);
        assertEq(metaVault.userToWithdrawalIndexToRedeemedShares(user1, 1), 20e6);
        assertEq(usdc.balanceOf(address(metaVault)), 0);

        vm.startPrank(user1);
        metaVault.redeem(10e6);
        vm.stopPrank();

        assertEq(metaVault.balanceOf(user1), 70e6);
        assertEq(metaVault.availableAssets(), 0);
        assertEq(metaVault.totalSupply(), 70e6);
        assertEq(metaVault.userToWithdrawalIndexToRedeemedShares(user1, 1), 30e6);
        assertEq(usdc.balanceOf(address(metaVault)), 0);
    }

    function test_withdraw() external {
        setVaults(50_00, 50_00);

        vm.startPrank(user1);
        metaVault.mint(100e6);
        vm.stopPrank();
        vm.startPrank(user2);
        metaVault.mint(200e6);
        vm.stopPrank();

        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        vm.startPrank(user1);
        metaVault.redeem(20e6);
        vm.stopPrank();
        vm.startPrank(user2);
        metaVault.redeem(10e6);
        vm.stopPrank();

        // cannot withdraw before redeem request is fulfilled
        vm.startPrank(user1);
        vm.expectRevert(MetaVault.RedeemRequestNotFulfilled.selector);
        metaVault.withdraw(1);
        vm.stopPrank();

        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        assertApproxEqAbs(usdc.balanceOf(address(metaVault)), 30e6, 2);

        // random user cannot withdraw anything if he has not requested
        vm.startPrank(address(0x98765));
        vm.expectRevert(MetaVault.NothingToWithdraw.selector);
        metaVault.withdraw(1);
        vm.stopPrank();

        uint256 user1BalanceBefore = usdc.balanceOf(user1);
        vm.startPrank(user1);
        metaVault.withdraw(1);
        // cannot withdraw second time
        vm.expectRevert(MetaVault.NothingToWithdraw.selector);
        metaVault.withdraw(1);
        vm.stopPrank();

        assertEq(metaVault.balanceOf(user1), 80e6);
        assertEq(metaVault.totalSupply(), 270e6);
        assertEq(usdc.balanceOf(address(metaVault)), 10e6);
        assertEq(metaVault.userToWithdrawalIndexToRedeemedShares(user1, 1), 0);

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
        metaVault.mint(100e6);
        vm.stopPrank();

        metaVault.flush();

        assertEq(metaVault.availableAssets(), 0);
        assertEq(usdc.balanceOf(address(metaVault)), 0);
        assertEq(metaVault.positionTotal(), 100e6);
        assertEq(metaVault.smartVaultToPosition(vault1), 91e6);
        assertEq(metaVault.smartVaultToPosition(vault2), 9e6);
        assertEq(metaVault.getSmartVaultDepositNftIds(vault1).length, 1);
        assertEq(metaVault.getSmartVaultDepositNftIds(vault2).length, 1);

        // second flushDeposit doesn't change anything
        metaVault.flush();
        assertEq(metaVault.availableAssets(), 0);
        assertEq(usdc.balanceOf(address(metaVault)), 0);
        assertEq(metaVault.positionTotal(), 100e6);
        assertEq(metaVault.smartVaultToPosition(vault1), 91e6);
        assertEq(metaVault.smartVaultToPosition(vault2), 9e6);
        assertEq(metaVault.getSmartVaultDepositNftIds(vault1).length, 1);
        assertEq(metaVault.getSmartVaultDepositNftIds(vault2).length, 1);
    }

    function test_sync_deposit_only() external {
        setVaults(91_00, 9_00);

        vm.startPrank(user1);
        metaVault.mint(100e6);
        vm.stopPrank();

        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        assertEq(metaVault.positionTotal(), 100e6);
        assertEq(metaVault.smartVaultToPosition(vault1), 91e6);
        assertEq(metaVault.smartVaultToPosition(vault2), 9e6);
        assertEq(metaVault.getSmartVaultDepositNftIds(vault1).length, 0);
        assertEq(metaVault.getSmartVaultDepositNftIds(vault2).length, 0);
        assertApproxEqAbs(ISmartVault(vault1).balanceOf(address(metaVault)), 91e21, 1e20);
        assertApproxEqAbs(ISmartVault(vault2).balanceOf(address(metaVault)), 9e21, 1e20);
    }

    function test_flush_withdrawal_only() external {
        setVaults(90_00, 10_00);

        // if there are no open positions flush doesn't do anything
        metaVault.flush();

        vm.startPrank(user1);
        metaVault.mint(100e6);
        vm.stopPrank();

        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        vm.startPrank(user1);
        metaVault.redeem(10e6);
        vm.stopPrank();

        metaVault.flush();

        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);

        assertEq(metaVault.positionTotal(), 90e6);
        assertEq(metaVault.withdrawalIndex(), 2);
        assertEq(metaVault.lastFulfilledWithdrawalIndex(), 0);
        assertTrue(metaVault.withdrawalIndexIsInitiated(1));
        assertEq(metaVault.smartVaultToPosition(vault1), 81e6);
        assertEq(metaVault.smartVaultToPosition(vault2), 9e6);
        assertEq(metaVault.withdrawalIndexToSmartVaultToWithdrawalNftId(1, vault1), MAXIMAL_DEPOSIT_ID + 1);
        assertEq(metaVault.withdrawalIndexToSmartVaultToWithdrawalNftId(1, vault2), MAXIMAL_DEPOSIT_ID + 1);
    }

    function test_sync_withdraw_only() external {
        setVaults(90_00, 10_00);

        uint256 toRedeem = 10e6;

        vm.startPrank(user1);
        metaVault.mint(100e6);
        vm.stopPrank();
        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        vm.startPrank(user1);
        metaVault.redeem(toRedeem);
        vm.stopPrank();
        metaVault.flush();

        assertEq(metaVault.lastFulfilledWithdrawalIndex(), 0);
        assertEq(metaVault.withdrawalIndexToWithdrawnAssets(1), 0);
        assertEq(usdc.balanceOf(address(metaVault)), 0);

        // syncing withdrawal is not possible if DHW has not run
        vm.expectRevert(abi.encodeWithSelector(WithdrawalNftNotSyncedYet.selector, MAXIMAL_DEPOSIT_ID + 1));
        metaVault.sync();

        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        assertEq(metaVault.lastFulfilledWithdrawalIndex(), 1);
        assertApproxEqAbs(metaVault.withdrawalIndexToWithdrawnAssets(1), toRedeem, 1);
        assertEq(metaVault.withdrawalIndexToSmartVaultToWithdrawalNftId(1, vault1), 0);
        assertEq(metaVault.withdrawalIndexToSmartVaultToWithdrawalNftId(1, vault2), 0);
        assertApproxEqAbs(usdc.balanceOf(address(metaVault)), toRedeem, 1);
    }

    function test_reallocate() external {
        setVaults(90_00, 10_00);
        uint256[][][] memory slippages = new uint256[][][](2);
        slippages[0] = new uint256[][](1);
        slippages[1] = new uint256[][](1);

        vm.startPrank(user1);
        metaVault.mint(100e6);
        vm.stopPrank();

        metaVault.flush();
        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);
        metaVault.sync();

        // first reallocation
        {
            changeAllocation(50_00, 50_00);

            metaVault.reallocate(slippages);

            _flushVaults(ISmartVault(vault2));
            _dhw(strategies);
            _syncVaults(ISmartVault(vault2));

            metaVault.sync();

            assertApproxEqAbs(ISmartVault(vault1).balanceOf(address(metaVault)), 50e21, 1e20);
            assertApproxEqAbs(ISmartVault(vault2).balanceOf(address(metaVault)), 50e21, 1e20);
            assertEq(metaVault.availableAssets(), 0);
            assertEq(usdc.balanceOf(address(metaVault)), 0);

            assertApproxEqAbs(_deploySpool.spoolLens().getSmartVaultAssetBalances(vault1, false)[0], 50e6, 2);
            assertApproxEqAbs(_deploySpool.spoolLens().getSmartVaultAssetBalances(vault2, false)[0], 50e6, 2);
        }

        // second reallocation
        {
            changeAllocation(15_00, 85_00);

            metaVault.reallocate(slippages);

            _flushVaults(ISmartVault(vault2));
            _dhw(strategies);
            _syncVaults(ISmartVault(vault2));

            metaVault.sync();

            assertApproxEqAbs(ISmartVault(vault1).balanceOf(address(metaVault)), 15e21, 1e20);
            assertApproxEqAbs(ISmartVault(vault2).balanceOf(address(metaVault)), 85e21, 1e20);
            assertEq(metaVault.availableAssets(), 0);
            assertEq(usdc.balanceOf(address(metaVault)), 0);

            assertApproxEqAbs(_deploySpool.spoolLens().getSmartVaultAssetBalances(vault1, false)[0], 15e6, 2);
            assertApproxEqAbs(_deploySpool.spoolLens().getSmartVaultAssetBalances(vault2, false)[0], 85e6, 2);
        }

        // third reallocation
        {
            changeAllocation(100_00, 0);

            metaVault.reallocate(slippages);

            _flushVaults(ISmartVault(vault1));
            _dhw(strategies);
            _syncVaults(ISmartVault(vault1));

            metaVault.sync();

            assertApproxEqAbs(ISmartVault(vault1).balanceOf(address(metaVault)), 100e21, 1e20);
            assertEq(ISmartVault(vault2).balanceOf(address(metaVault)), 0);
            assertEq(metaVault.availableAssets(), 0);
            assertEq(usdc.balanceOf(address(metaVault)), 0);

            assertApproxEqAbs(_deploySpool.spoolLens().getSmartVaultAssetBalances(vault1, false)[0], 100e6, 2);
            assertEq(_deploySpool.spoolLens().getSmartVaultAssetBalances(vault2, false)[0], 0);
        }
    }

    function test_reallocate_viewOnly() external {
        setVaults(90_00, 10_00);
        uint256[][][] memory slippages = new uint256[][][](2);
        slippages[0] = new uint256[][](1);
        slippages[1] = new uint256[][](1);

        vm.startPrank(user1);
        metaVault.mint(100e6);
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
