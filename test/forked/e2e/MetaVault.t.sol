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
        vm.startPrank(user1);
        metaVault.mint(100e6);
        vm.stopPrank();
        assertEq(metaVault.balanceOf(user1), 100e6);
        assertEq(metaVault.availableAssets(), 100e6);
        assertEq(metaVault.totalSupply(), 100e6);

        vm.startPrank(user1);
        metaVault.mint(20e6);
        vm.stopPrank();
        assertEq(metaVault.balanceOf(user1), 120e6);
        assertEq(metaVault.availableAssets(), 120e6);
        assertEq(metaVault.totalSupply(), 120e6);

        vm.startPrank(user2);
        metaVault.mint(30e6);
        vm.stopPrank();
        assertEq(metaVault.balanceOf(user2), 30e6);
        assertEq(metaVault.availableAssets(), 150e6);
        assertEq(metaVault.totalSupply(), 150e6);
    }

    function test_redeem() external {
        vm.startPrank(user1);
        metaVault.mint(100e6);
        metaVault.redeem(20e6);
        vm.stopPrank();

        assertEq(metaVault.balanceOf(user1), 80e6);
        assertEq(metaVault.availableAssets(), 100e6);
        assertEq(metaVault.totalSupply(), 80e6);
        assertEq(metaVault.userToWithdrawalIndexToRedeemedShares(user1, 1), 20e6);
        assertEq(usdc.balanceOf(address(metaVault)), 100e6);

        vm.startPrank(user1);
        metaVault.redeem(10e6);
        vm.stopPrank();

        assertEq(metaVault.balanceOf(user1), 70e6);
        assertEq(metaVault.availableAssets(), 100e6);
        assertEq(metaVault.totalSupply(), 70e6);
        assertEq(metaVault.userToWithdrawalIndexToRedeemedShares(user1, 1), 30e6);
        assertEq(usdc.balanceOf(address(metaVault)), 100e6);
    }

    function test_withdraw() external {
        vm.startPrank(user1);
        metaVault.mint(100e6);
        metaVault.redeem(20e6);
        vm.stopPrank();

        vm.startPrank(user2);
        metaVault.mint(200e6);
        metaVault.redeem(10e6);
        vm.stopPrank();

        // cannot withdraw before redeem request is fulfilled
        vm.startPrank(user1);
        vm.expectRevert(MetaVault.RedeemRequestNotFulfilled.selector);
        metaVault.withdraw(1);
        vm.stopPrank();

        // emulate fulfillment of redeem request for 1 withdrawalIndex. MetaVault generated yield for users
        stdstore.target(address(metaVault)).sig("lastFulfilledWithdrawalIndex()").checked_write(1);
        stdstore.target(address(metaVault)).sig("currentWithdrawalIndex()").checked_write(2);
        stdstore.target(address(metaVault)).sig("availableAssets()").checked_write(240e6);
        stdstore.target(address(metaVault)).sig("withdrawalIndexToWithdrawnAssets(uint256)").with_key(1).checked_write(
            60e6
        );

        assertEq(metaVault.userToWithdrawalIndexToRedeemedShares(user1, 1), 20e6);

        uint256 user1BalanceBefore = usdc.balanceOf(user1);
        vm.startPrank(user1);
        metaVault.withdraw(1);

        // cannot withdraw second time
        vm.expectRevert(MetaVault.NothingToWithdraw.selector);
        metaVault.withdraw(1);
        vm.stopPrank();

        // random user cannot withdraw anything if he has not requested
        vm.startPrank(address(0x98765));
        vm.expectRevert(MetaVault.NothingToWithdraw.selector);
        metaVault.withdraw(1);
        vm.stopPrank();

        assertEq(metaVault.balanceOf(user1), 80e6);
        assertEq(metaVault.availableAssets(), 240e6);
        assertEq(metaVault.totalSupply(), 270e6);
        assertEq(usdc.balanceOf(address(metaVault)), 260e6);
        assertEq(metaVault.userToWithdrawalIndexToRedeemedShares(user1, 1), 0);

        uint256 user1BalanceAfter = usdc.balanceOf(user1);
        assertEq(user1BalanceAfter - user1BalanceBefore, 40e6);

        uint256 user2BalanceBefore = usdc.balanceOf(user2);
        vm.startPrank(user2);
        metaVault.withdraw(1);
        vm.stopPrank();

        assertEq(metaVault.balanceOf(user2), 190e6);
        assertEq(metaVault.availableAssets(), 240e6);
        assertEq(metaVault.totalSupply(), 270e6);
        assertEq(usdc.balanceOf(address(metaVault)), 240e6);

        uint256 user2BalanceAfter = usdc.balanceOf(user2);
        assertEq(user2BalanceAfter - user2BalanceBefore, 20e6);
    }

    function test_flushDeposit() external {
        setVaults(91_00, 9_00);

        vm.startPrank(user1);
        metaVault.mint(100e6);
        vm.stopPrank();

        metaVault.flushDeposit();

        assertEq(metaVault.availableAssets(), 0);
        assertEq(usdc.balanceOf(address(metaVault)), 0);
        assertEq(metaVault.positionTotal(), 100e6);
        assertEq(metaVault.smartVaultToPosition(vault1), 91e6);
        assertEq(metaVault.smartVaultToPosition(vault2), 9e6);
        assertEq(metaVault.getSmartVaultDepositNftIds(vault1).length, 1);
        assertEq(metaVault.getSmartVaultDepositNftIds(vault2).length, 1);

        // second flushDeposit doesn't change anything
        metaVault.flushDeposit();
        assertEq(metaVault.availableAssets(), 0);
        assertEq(usdc.balanceOf(address(metaVault)), 0);
        assertEq(metaVault.positionTotal(), 100e6);
        assertEq(metaVault.smartVaultToPosition(vault1), 91e6);
        assertEq(metaVault.smartVaultToPosition(vault2), 9e6);
        assertEq(metaVault.getSmartVaultDepositNftIds(vault1).length, 1);
        assertEq(metaVault.getSmartVaultDepositNftIds(vault2).length, 1);
    }

    function test_syncDeposit() external {
        setVaults(91_00, 9_00);

        vm.startPrank(user1);
        metaVault.mint(100e6);
        vm.stopPrank();

        metaVault.flushDeposit();

        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);

        metaVault.syncDeposit();

        assertEq(metaVault.positionTotal(), 100e6);
        assertEq(metaVault.smartVaultToPosition(vault1), 91e6);
        assertEq(metaVault.smartVaultToPosition(vault2), 9e6);
        assertEq(metaVault.getSmartVaultDepositNftIds(vault1).length, 0);
        assertEq(metaVault.getSmartVaultDepositNftIds(vault2).length, 0);
        assertApproxEqAbs(ISmartVault(vault1).balanceOf(address(metaVault)), 91e21, 1e20);
        assertApproxEqAbs(ISmartVault(vault2).balanceOf(address(metaVault)), 9e21, 1e20);
    }

    function test_flushWithdrawal() external {
        setVaults(90_00, 10_00);

        // if there are no open positions flush doesn't do anything
        metaVault.flushWithdrawal();

        vm.startPrank(user1);
        metaVault.mint(100e6);
        metaVault.redeem(10e6);
        vm.stopPrank();

        // if there are available assets then withdrawal will revert
        vm.expectRevert(MetaVault.PendingDeposit.selector);
        metaVault.flushWithdrawal();
        assertEq(metaVault.currentWithdrawalIndex(), 1);

        metaVault.flushDeposit();
        // if there are pending deposit flushWithdrawal will fail
        vm.expectRevert(abi.encodeWithSelector(DepositNftNotSyncedYet.selector, 1));
        metaVault.flushWithdrawal();

        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);

        metaVault.syncDeposit();

        metaVault.flushWithdrawal();

        assertEq(metaVault.positionTotal(), 90e6);
        assertEq(metaVault.currentWithdrawalIndex(), 2);
        assertEq(metaVault.lastFulfilledWithdrawalIndex(), 0);
        assertTrue(metaVault.withdrawalIndexIsInitiated(1));
        assertEq(metaVault.smartVaultToPosition(vault1), 81e6);
        assertEq(metaVault.smartVaultToPosition(vault2), 9e6);
        assertEq(metaVault.withdrawalIndexToSmartVaultToWithdrawalNftId(1, vault1), MAXIMAL_DEPOSIT_ID + 1);
        assertEq(metaVault.withdrawalIndexToSmartVaultToWithdrawalNftId(1, vault2), MAXIMAL_DEPOSIT_ID + 1);
    }

    function test_syncWithdrawal() external {
        setVaults(90_00, 10_00);

        uint256 toRedeem = 10e6;

        vm.startPrank(user1);
        metaVault.mint(100e6);
        metaVault.redeem(toRedeem);
        vm.stopPrank();

        metaVault.flushDeposit();

        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);

        metaVault.syncDeposit();

        metaVault.flushWithdrawal();

        // syncing withdrawal is not possible if DHW has not run
        vm.expectRevert(abi.encodeWithSelector(WithdrawalNftNotSyncedYet.selector, MAXIMAL_DEPOSIT_ID + 1));
        metaVault.syncWithdrawal();

        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);

        assertEq(metaVault.lastFulfilledWithdrawalIndex(), 0);
        assertEq(metaVault.withdrawalIndexToWithdrawnAssets(1), 0);
        assertEq(usdc.balanceOf(address(metaVault)), 0);

        metaVault.syncWithdrawal();

        assertEq(metaVault.lastFulfilledWithdrawalIndex(), 1);
        assertApproxEqAbs(metaVault.withdrawalIndexToWithdrawnAssets(1), toRedeem, 1);
        assertEq(metaVault.withdrawalIndexToSmartVaultToWithdrawalNftId(1, vault1), 0);
        assertEq(metaVault.withdrawalIndexToSmartVaultToWithdrawalNftId(1, vault2), 0);
        assertApproxEqAbs(usdc.balanceOf(address(metaVault)), toRedeem, 1);
    }

    function test_flushWithdrawalFast() external {
        setVaults(90_00, 10_00);
        uint256[][][] memory slippages = new uint256[][][](2);
        slippages[0] = new uint256[][](1);
        slippages[1] = new uint256[][](1);
        // if there are no open positions flush doesn't do anything
        metaVault.flushWithdrawalFast(slippages);

        vm.startPrank(user1);
        metaVault.mint(100e6);
        metaVault.redeem(10e6);
        vm.stopPrank();

        // if there are available assets then withdrawal will revert
        vm.expectRevert(MetaVault.PendingDeposit.selector);
        metaVault.flushWithdrawalFast(slippages);
        assertEq(metaVault.currentWithdrawalIndex(), 1);

        metaVault.flushDeposit();
        // if there are pending deposit flushWithdrawal will fail
        vm.expectRevert(abi.encodeWithSelector(DepositNftNotSyncedYet.selector, 1));
        metaVault.flushWithdrawalFast(slippages);

        _flushVaults(vaults);
        _dhw(strategies);
        _syncVaults(vaults);

        metaVault.syncDeposit();

        metaVault.flushWithdrawalFast(slippages);

        assertEq(metaVault.positionTotal(), 90e6);
        assertEq(metaVault.currentWithdrawalIndex(), 2);
        assertEq(metaVault.lastFulfilledWithdrawalIndex(), 1);
        assertFalse(metaVault.withdrawalIndexIsInitiated(1));
        assertEq(metaVault.smartVaultToPosition(vault1), 81e6);
        assertEq(metaVault.smartVaultToPosition(vault2), 9e6);
        assertEq(metaVault.withdrawalIndexToSmartVaultToWithdrawalNftId(1, vault1), 0);
        assertEq(metaVault.withdrawalIndexToSmartVaultToWithdrawalNftId(1, vault2), 0);
    }

    // function test_metaVault_simpleFlow() public {
    //     ISmartVault[] memory vaults = new ISmartVault[](2);
    //     vaults[0] = vault1;
    //     vaults[1] = vault2;

    //     vm.startPrank(user1);
    //     metaVault.mint(100e6);
    //     assertEq(metaVault.balanceOf(user1), 100e6);
    //     assertEq(metaVault.availableAssets(), 100e6);
    //     assertEq(metaVault.positionTotal(), 0);
    //     assertEq(usdc.balanceOf(address(metaVault)), 100e6);
    //     vm.stopPrank();

    //     {
    //         vm.startPrank(owner);
    //         address[] memory v = new address[](2);
    //         v[0] = address(vault1);
    //         v[1] = address(vault2);
    //         uint256[] memory a = new uint256[](2);
    //         a[0] = 20_00;
    //         a[1] = 80_00;
    //         metaVault.addSmartVaults(v, a);
    //         assertEq(metaVault.getSmartVaults(), v);
    //         vm.stopPrank();
    //     }

    //     metaVault.flushDeposit();
    //     _flushVaults(vaults);
    //     _dhw(strategies);
    //     _syncVaults(vaults);
    //     metaVault.syncDeposit();

    //     assertEq(metaVault.availableAssets(), 0);
    //     assertEq(usdc.balanceOf(address(metaVault)), 0);
    //     assertEq(metaVault.positionTotal(), 100e6);

    //     uint256 withdrawalIndex = metaVault.currentWithdrawalIndex();
    //     uint256 svts1Before = vault1.balanceOf(address(metaVault));
    //     uint256 svts2Before = vault2.balanceOf(address(metaVault));
    //     assertTrue(svts1Before > 0);
    //     assertTrue(svts2Before > 0);

    //     {
    //         vm.startPrank(user1);
    //         metaVault.redeem(20e6);
    //         uint256 currentWithdrawalIndex = metaVault.currentWithdrawalIndex();
    //         uint256 totalRequested = metaVault.withdrawalIndexToRedeemedShares(currentWithdrawalIndex);
    //         uint256 userRequested = metaVault.userToWithdrawalIndexToRedeemedShares(user1, currentWithdrawalIndex);
    //         assertEq(20e6, userRequested);
    //         assertEq(totalRequested, userRequested);
    //         vm.expectRevert(MetaVault.RedeemRequestNotFulfilled.selector);
    //         // user cannot withdraw if request is not fulfilled
    //         metaVault.withdraw(currentWithdrawalIndex);
    //         vm.stopPrank();
    //     }

    //     metaVault.flushWithdrawal();

    //     assertTrue(vault1.balanceOf(address(metaVault)) > 0);
    //     assertTrue(vault2.balanceOf(address(metaVault)) > 0);
    //     assertEq(metaVault.getSmartVaultWithdrawalNftIds(address(vault1)).length, 1);
    //     assertEq(metaVault.getSmartVaultWithdrawalNftIds(address(vault2)).length, 1);

    //     assertApproxEqAbs(
    //         vault2.balanceOf(address(metaVault)) * 100_00 / vault1.balanceOf(address(metaVault)),
    //         metaVault.smartVaultToAllocation(address(vault2)) * 100_00
    //             / metaVault.smartVaultToAllocation(address(vault1)),
    //         1
    //     );
    //     assertEq(withdrawalIndex + 1, metaVault.currentWithdrawalIndex());
    //     assertEq(metaVault.getSmartVaultWithdrawalNftIds(address(vault1)).length, 1);
    //     assertEq(metaVault.getSmartVaultWithdrawalNftIds(address(vault2)).length, 1);

    //     _flushVaults(vaults);
    //     _dhw(strategies);
    //     _syncVaults(vaults);

    //     {
    //         uint256 lastFulfilledWithdrawalIndex = metaVault.lastFulfilledWithdrawalIndex();
    //         metaVault.syncWithdrawal();
    //         uint256 svts1Withdrawn = svts1Before - vault1.balanceOf(address(metaVault));
    //         uint256 svts2Withdrawn = svts2Before - vault2.balanceOf(address(metaVault));
    //         assertEq(svts1Withdrawn * 100 / svts1Before, svts2Withdrawn * 100 / svts2Before);
    //         assertEq(svts1Withdrawn * 100 / svts1Before, 20);

    //         assertEq(lastFulfilledWithdrawalIndex + 1, metaVault.lastFulfilledWithdrawalIndex());
    //         assertEq(metaVault.positionTotal(), 80e6);
    //         assertEq(metaVault.getSmartVaultWithdrawalNftIds(address(vault1)).length, 0);
    //         assertEq(metaVault.getSmartVaultWithdrawalNftIds(address(vault2)).length, 0);
    //     }

    //     {
    //         vm.startPrank(user1);
    //         uint256 userBalanceBefore = usdc.balanceOf(user1);
    //         metaVault.withdraw(1);
    //         uint256 userBalanceAfter = usdc.balanceOf(user1);
    //         assertApproxEqAbs(userBalanceAfter - userBalanceBefore, 20e6, 2);
    //         assertEq(userBalanceAfter - userBalanceBefore, metaVault.withdrawalIndexToWithdrawnAssets(1));
    //         vm.stopPrank();
    //     }
    // }

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
