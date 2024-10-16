// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../../src/guards/UnlockGuard.sol";
import "../../src/access/SpoolAccessControl.sol";

contract SmartVaultFake {}

contract UnlockGuardTest is Test {
    event UpdatedUnlock(address indexed smartVault, uint256 indexed unlock);

    UnlockGuard private unlockGuard;
    address private smartVault1;
    address private smartVault2;

    address alice;
    address bob;
    address charlie;

    function setUp() public {
        SpoolAccessControl accessControl = new SpoolAccessControl();
        accessControl.initialize();
        unlockGuard = new UnlockGuard(accessControl);

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

    function test_updateUnlock_shouldUpdateUnlock() public {
        vm.startPrank(alice);
        unlockGuard.updateUnlock(address(smartVault1), 1 weeks);
        unlockGuard.updateUnlock(address(smartVault2), 2 weeks);
        vm.stopPrank();

        assertEq(unlockGuard.unlocks(smartVault1), 1 weeks);
        assertEq(unlockGuard.unlocks(smartVault2), 2 weeks);
    }

    function test_addToUnlock_shouldRevertWhenCallerIsNotAllowedToUpdateUnlock() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SMART_VAULT_ADMIN, bob));
        unlockGuard.updateUnlock(smartVault1, 1 weeks);
    }

    function test_updateUnlock_shouldEmitUpdatedUnlockEvent() public {
        vm.expectEmit(true, true, true, false, address(unlockGuard));
        emit UpdatedUnlock(smartVault1, 2 weeks);

        vm.prank(alice);
        unlockGuard.updateUnlock(smartVault1, 2 weeks);
    }

    function test_updateUnlock_shouldResetUnlock() public {
        vm.prank(alice);
        unlockGuard.updateUnlock(address(smartVault1), 2 weeks);
        assertEq(unlockGuard.unlocks(smartVault1), 2 weeks);

        vm.prank(alice);
        unlockGuard.updateUnlock(address(smartVault1), 0);
        assertEq(unlockGuard.unlocks(smartVault1), 0);
    }
}
