// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/managers/GuardManager.sol";
import {MockGuard} from "../src/mocks/MockGuard.sol";

contract GuardManagerTest is Test {
    IGuardManager guardManager;
    MockGuard mockGuard;
    address smartVaultId = address(1);
    address user = address(256);
    GuardDefinition[] guards;

    function setUp() public {
        guardManager = new GuardManager();
        mockGuard = new MockGuard();

        _createGuards();
        guardManager.setGuards(smartVaultId, guards);
    }

    function _createGuards() internal {
        bytes[] memory emptyBytes = new bytes[](0);
        GuardParamType[] memory paramTypes = new GuardParamType[](1);
        paramTypes[0] = GuardParamType.Executor;

        GuardDefinition memory guard = GuardDefinition(
            address(mockGuard),
            "isWhitelisted(address)",
            bytes32(uint256(1)),
            paramTypes,
            emptyBytes,
            RequestType.Deposit,
            "=="
        );

        GuardParamType[] memory paramTypes2 = new GuardParamType[](2);
        paramTypes2[0] = GuardParamType.CustomValue;
        paramTypes2[1] = GuardParamType.Tokens;
        bytes[] memory methodValues2 = new bytes[](1);
        methodValues2[0] = abi.encode(uint256(4));

        GuardDefinition memory guard2 = GuardDefinition(
            address(mockGuard),
            "checkAddressesLength(uint256,address[])",
            bytes32(uint256(1)),
            paramTypes2,
            methodValues2,
            RequestType.Deposit,
            "=="
        );

        GuardDefinition memory guard3 = GuardDefinition(
            address(mockGuard),
            "isWhitelisted(address)",
            bytes32(uint256(1)),
            paramTypes,
            emptyBytes,
            RequestType.Withdrawal,
            "=="
        );

        GuardParamType[] memory paramTypes4 = new GuardParamType[](2);
        paramTypes4[0] = GuardParamType.DynamicCustomValue;
        paramTypes4[1] = GuardParamType.CustomValue;

        bytes[] memory methodValues4 = new bytes[](2);
        uint256[] memory numbersToSum = new uint256[](3);
        numbersToSum[0] = uint256(2);
        numbersToSum[1] = uint256(4);
        numbersToSum[2] = uint256(6);
        methodValues4[0] = abi.encodePacked(numbersToSum);
        methodValues4[1] = abi.encode(uint256(12));

        GuardDefinition memory guard4 = GuardDefinition(
            address(mockGuard),
            "checkArraySum(uint256[],uint256)",
            bytes32(uint256(1)),
            paramTypes4,
            methodValues4,
            RequestType.Deposit,
            "=="
        );

        guards.push(guard);
        guards.push(guard2);
        guards.push(guard3);
        guards.push(guard4);
    }

    function test_readGuards() public {
        GuardDefinition[] memory storedGuards = guardManager.readGuards(smartVaultId);

        assertEq(storedGuards.length, 4);
        assertEq(storedGuards[0].contractAddress, guards[0].contractAddress);
        assertEq(storedGuards[0].methodSignature, guards[0].methodSignature);
        assertEq(storedGuards[0].methodParamTypes.length, 1);
        assertEq(uint8(storedGuards[0].requestType), uint8(RequestType.Deposit));
        assertEq(uint8(storedGuards[1].requestType), uint8(RequestType.Deposit));
        assertEq(uint8(storedGuards[2].requestType), uint8(RequestType.Withdrawal));
        assertEq(uint8(storedGuards[0].methodParamTypes[0]), uint8(GuardParamType.Executor));
    }

    function test_runGuards() public {
        address[] memory tokens = new address[](4);
        tokens[0] = address(10);
        tokens[1] = address(11);
        tokens[2] = address(12);
        tokens[3] = address(13);

        RequestContext memory context =
            RequestContext(address(user), address(user), RequestType.Deposit, new uint256[](0), tokens);

        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector));
        guardManager.runGuards(smartVaultId, context);

        mockGuard.setWhitelist(user, true);

        guardManager.runGuards(smartVaultId, context);
    }

    function test_writeGuards() public {
        guardManager.setGuards(address(2), guards);
    }
}
