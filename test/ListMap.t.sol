// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../src/libraries/ListMap.sol";

contract ListMapTest is Test {
    using ListMap for ListMap.Address;

    ListMap.Address private addressListMap;

    address private addr1 = address(0x123);
    address private addr2 = address(0x456);
    address private addr3 = address(0x789);

    function setUp() public {}

    function testAddAddress() public {
        addressListMap.add(addr1);
        assertTrue(addressListMap.includes[addr1]);
        assertEq(addressListMap.list.length, 1);
        assertEq(addressListMap.list[0], addr1);

        // Try to add the same address again and expect revert
        vm.expectRevert(ListMap.ElementAlreadyInList.selector);
        addressListMap.add(addr1);
    }

    function testRemoveAddress() public {
        addressListMap.add(addr1);
        addressListMap.add(addr2);

        addressListMap.remove(addr1);
        assertFalse(addressListMap.includes[addr1]);
        assertEq(addressListMap.list.length, 1);

        // Try to remove a non-existing address and expect revert
        vm.expectRevert(ListMap.NoElementInList.selector);
        addressListMap.remove(addr3);
    }

    function testAddListAddress() public {
        address[] memory addresses = new address[](2);
        addresses[0] = addr1;
        addresses[1] = addr2;

        addressListMap.addList(addresses);
        assertTrue(addressListMap.includes[addr1]);
        assertTrue(addressListMap.includes[addr2]);
        assertEq(addressListMap.list.length, 2);
    }

    function testRemoveListAddress() public {
        address[] memory addresses = new address[](2);
        addresses[0] = addr1;
        addresses[1] = addr2;

        addressListMap.addList(addresses);
        addressListMap.removeList(addresses);
        assertFalse(addressListMap.includes[addr1]);
        assertFalse(addressListMap.includes[addr2]);
        assertEq(addressListMap.list.length, 0);
    }
}
