// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import {Guard, GuardManager, GuardParamType} from "../src/GuardManager.sol";
import {MockGuard} from "../src/mocks/MockGuard.sol";

contract GuardManagerTest is Test {
    GuardManager guardManager;
    MockGuard mockGuard;
    address smartVaultId = address(1);
    address user = address(256);

    function setUp() public {
        guardManager = new GuardManager();
        mockGuard = new MockGuard();
    }

    function _createGuards() internal returns(Guard[] memory) {
        GuardParamType[] memory paramTypes = new GuardParamType[](1);
        paramTypes[0] = GuardParamType.UserAddress;

        Guard memory guard = Guard(
            address(mockGuard),
            "isWhitelisted(address)",
            paramTypes,
            new bytes32[](0),
            "==",
            bytes32(uint(1))
        );

        Guard[] memory guards = new Guard[](1);
        guards[0] = guard;

        return guards;
    }

    function testPersistGuards() public {
        Guard[] memory guards = _createGuards();
        guardManager.setGuards(smartVaultId, guards);
        Guard[] memory storedGuards = guardManager.readGuards(smartVaultId);

        assertEq(storedGuards.length, 1);
        assertEq(storedGuards[0].contractAddress, guards[0].contractAddress);
        assertEq(storedGuards[0].methodSignature, guards[0].methodSignature);
        assertEq(storedGuards[0].methodParamTypes.length, 1);
        assertEq(uint8(storedGuards[0].methodParamTypes[0]), uint8(GuardParamType.UserAddress));
    }

    function testRunGuards() public {
        vm.startPrank(user);

        guardManager.setGuards(smartVaultId, _createGuards());

        vm.expectRevert("GuardManager::_checkResult: A-a, go back.");
        guardManager.runGuards(smartVaultId);

        mockGuard.setWhitelist(user, true);
        
        guardManager.runGuards(smartVaultId);
    }
}
