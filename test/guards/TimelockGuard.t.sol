// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../../src/guards/TimelockGuard.sol";
import "../../src/access/SpoolAccessControl.sol";

contract SmartVaultFake {}

contract TimelockGuardTest is Test {
    event UpdatedTimelock(address indexed smartVault, uint256 indexed timelock);

    TimelockGuard private timelockGuard;
    address private smartVault1;
    address private smartVault2;

    address alice;
    address bob;
    address charlie;

    function setUp() public {
        SpoolAccessControl accessControl = new SpoolAccessControl();
        accessControl.initialize();
        timelockGuard = new TimelockGuard(accessControl);

        alice = address(0xa);
        bob = address(0xb);
        charlie = address(0xc);

        SmartVaultFake smartVaultFake1 = new SmartVaultFake();
        SmartVaultFake smartVaultFake2 = new SmartVaultFake();

        smartVault1 = address(smartVaultFake1);
        smartVault2 = address(smartVaultFake2);

        accessControl.grantSmartVaultRole(smartVault1, ROLE_SMART_VAULT_ADMIN, alice);
        accessControl.grantSmartVaultRole(smartVault2, ROLE_SMART_VAULT_ADMIN, alice);
    }

    function test_updateTimelock_shouldUpdateTimelock() public {
        vm.startPrank(alice);
        timelockGuard.updateTimelock(address(smartVault1), 1 weeks);
        timelockGuard.updateTimelock(address(smartVault2), 2 weeks);
        vm.stopPrank();

        assertEq(timelockGuard.timelocks(smartVault1), 1 weeks);
        assertEq(timelockGuard.timelocks(smartVault2), 2 weeks);
    }

    function test_updateTimelock_shouldRevertWithTimelockisOutOfRange() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(TimelockOutOfRange.selector, 366 days));
        timelockGuard.updateTimelock(smartVault1, 366 days);
        vm.stopPrank();
    }

    function test_addToTimelock_shouldRevertWhenCallerIsNotAllowedToUpdateTimelock() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SMART_VAULT_ADMIN, bob));
        timelockGuard.updateTimelock(smartVault1, 1 weeks);
    }

    function test_updateTimelock_shouldEmitUpdatedTimelockEvent() public {
        vm.expectEmit(true, true, true, false, address(timelockGuard));
        emit UpdatedTimelock(smartVault1, 2 weeks);

        vm.prank(alice);
        timelockGuard.updateTimelock(smartVault1, 2 weeks);
    }

    function test_updateTimelock_shouldResetTimelock() public {
        vm.prank(alice);
        timelockGuard.updateTimelock(address(smartVault1), 2 weeks);
        assertEq(timelockGuard.timelocks(smartVault1), 2 weeks);

        vm.prank(alice);
        timelockGuard.updateTimelock(address(smartVault1), 0);
        assertEq(timelockGuard.timelocks(smartVault1), 0);
    }
}
