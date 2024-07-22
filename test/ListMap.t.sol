// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../src/libraries/ListMap.sol";

contract ListMapTest is Test {
    using ListMap for ListMap.Address;
    using ListMap for ListMap.Uint256;

    ListMap.Address private addressListMap;
    ListMap.Uint256 private uint256ListMap;

    address private addr1 = address(0x123);
    address private addr2 = address(0x456);
    address private addr3 = address(0x789);

    uint256 private uint1 = 1;
    uint256 private uint2 = 2;
    uint256 private uint3 = 3;

    function setUp() public {
        addressListMap.clean();
        uint256ListMap.clean();
    }

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

    function testAddUint256() public {
        uint256ListMap.add(uint1);
        assertTrue(uint256ListMap.includes[uint1]);
        assertEq(uint256ListMap.list.length, 1);
        assertEq(uint256ListMap.list[0], uint1);

        // Try to add the same uint256 again and expect revert
        vm.expectRevert(ListMap.ElementAlreadyInList.selector);
        uint256ListMap.add(uint1);
    }

    function testRemoveUint256() public {
        uint256ListMap.add(uint1);
        uint256ListMap.add(uint2);

        uint256ListMap.remove(uint1);
        assertFalse(uint256ListMap.includes[uint1]);
        assertEq(uint256ListMap.list.length, 1);

        // Try to remove a non-existing uint256 and expect revert
        vm.expectRevert(ListMap.NoElementInList.selector);
        uint256ListMap.remove(uint3);
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

    function testAddListUint256() public {
        uint256[] memory uints = new uint256[](2);
        uints[0] = uint1;
        uints[1] = uint2;

        uint256ListMap.addList(uints);
        assertTrue(uint256ListMap.includes[uint1]);
        assertTrue(uint256ListMap.includes[uint2]);
        assertEq(uint256ListMap.list.length, 2);
    }

    function testRemoveListUint256() public {
        uint256[] memory uints = new uint256[](2);
        uints[0] = uint1;
        uints[1] = uint2;

        uint256ListMap.addList(uints);
        uint256ListMap.removeList(uints);
        assertFalse(uint256ListMap.includes[uint1]);
        assertFalse(uint256ListMap.includes[uint2]);
        assertEq(uint256ListMap.list.length, 0);
    }

    function testCleanAddress() public {
        addressListMap.add(addr1);
        addressListMap.add(addr2);

        addressListMap.clean();
        assertFalse(addressListMap.includes[addr1]);
        assertFalse(addressListMap.includes[addr2]);
        assertEq(addressListMap.list.length, 0);
    }

    function testCleanUint256() public {
        uint256ListMap.add(uint1);
        uint256ListMap.add(uint2);

        uint256ListMap.clean();
        assertFalse(uint256ListMap.includes[uint1]);
        assertFalse(uint256ListMap.includes[uint2]);
        assertEq(uint256ListMap.list.length, 0);
    }
}
