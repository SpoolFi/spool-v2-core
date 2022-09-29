// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/GuardManager.sol";
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

    function _createGuards() internal view returns(GuardDefinition[] memory) {
        GuardParamType[] memory paramTypes = new GuardParamType[](1);
        paramTypes[0] = GuardParamType.Executor;

        GuardDefinition memory guard = GuardDefinition(
            address(mockGuard),
            "isWhitelisted(address)",
            bytes32(uint(1)),
            paramTypes, 
            new bytes32[](0),
            RequestType.Deposit,
            "=="
        );

        GuardDefinition memory guard2 = GuardDefinition(
            address(mockGuard),
            "isWhitelisted(address)",
            bytes32(uint(1)),
            paramTypes, 
            new bytes32[](0),
            RequestType.Withdrawal,
            "=="
        );
         GuardDefinition memory guard3 = GuardDefinition(
            address(mockGuard),
            "isWhitelisted(address)",
            bytes32(uint(1)),
            paramTypes, 
            new bytes32[](0),
            RequestType.Withdrawal,
            "=="
        );

        GuardDefinition[] memory guards = new GuardDefinition[](3);
        guards[0] = guard;
        guards[1] = guard2;
        guards[2] = guard3;
        
        return guards;
    }

    function testPersistGuards() public {
        GuardDefinition[] memory guards = _createGuards();
        guardManager.setGuards(smartVaultId, guards);
        GuardDefinition[] memory storedGuards = guardManager.readGuards(smartVaultId);

        assertEq(storedGuards.length, 3);
        assertEq(storedGuards[0].contractAddress, guards[0].contractAddress);
        assertEq(storedGuards[0].methodSignature, guards[0].methodSignature);
        assertEq(storedGuards[0].methodParamTypes.length, 1);
        assertEq(uint8(storedGuards[0].requestType), uint8(RequestType.Deposit));
        assertEq(uint8(storedGuards[1].requestType), uint8(RequestType.Withdrawal));
        assertEq(uint8(storedGuards[0].methodParamTypes[0]), uint8(GuardParamType.Executor));
    }

    function testRunGuards() public {
        guardManager.setGuards(smartVaultId, _createGuards());
        RequestContext memory context = RequestContext(
            address(user),
            address(user),
            RequestType.Deposit,
            new uint256[](0),
            new address[](0)
        );

        vm.expectRevert("GuardManager::_checkResult: A-a, go back.");
        guardManager.runGuards(smartVaultId, context);

        mockGuard.setWhitelist(user, true);
        
        guardManager.runGuards(smartVaultId, context);
    }
}
