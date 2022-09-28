// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/Counter.sol";
import "../src/mocks/MockToken.sol";
import "../src/mocks/MockContract.sol";

contract CounterTest is Test {
    Counter public counter;
    MockToken public mockToken;
    MockContract public mockContract;

    function setUp() public {
        mockToken = new MockToken("TST", "TST");
        mockContract = new MockContract();
        counter = new Counter();
    }

    function testAddNumbers() public {
        (bool success, bytes memory d) = counter.addNumbers(address(mockContract));
        console.logBytes(d);
        console.log(success);

        assertTrue(success);
    }

    function testReturnAddress() public {
        (bool success, bytes memory d) = counter.returnAddress(address(mockContract));
        console.logBytes(d);
        console.log(success);
        console.log(address(uint160(uint(bytes32(d)))));
        console.log(address(32));
        assertTrue(success);
    }
}
