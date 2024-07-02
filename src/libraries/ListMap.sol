// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

error NoElementInList();
error ElementAlreadyInList();

/*
 * @title ListMap
 * @notice Library for combining lists and mapping
 * @notice Allows to manage easily collections and avoid iterations
 */

library ListMap {
    struct Address {
        address[] list;
        mapping(address => bool) includes;
    }

    struct Uint256 {
        uint256[] list;
        mapping(uint256 => bool) includes;
    }

    /**
     * @dev remove list
     * @param listMap listMap which should be changed
     * @param list list of items to remove from listMap
     */
    function removeList(Address storage listMap, address[] memory list) internal {
        for (uint256 i; i < list.length; i++) {
            remove(listMap, list[i]);
        }
    }
    /**
     * @dev remove list
     * @param listMap listMap which should be changed
     * @param list list of items to remove from listMap
     */

    function removeList(Uint256 storage listMap, uint256[] memory list) internal {
        for (uint256 i; i < list.length; i++) {
            remove(listMap, list[i]);
        }
    }
    /**
     * @dev remove item
     * @param listMap listMap which should be changed
     * @param value item to remove from listMap
     */

    function remove(Address storage listMap, address value) internal {
        for (uint256 i; i < listMap.list.length; i++) {
            if (listMap.list[i] == value) {
                listMap.list[i] = listMap.list[listMap.list.length - 1];
                listMap.list.pop();
                listMap.includes[value] = false;
                return;
            }
        }
        revert NoElementInList();
    }
    /**
     * @dev remove item
     * @param listMap listMap which should be changed
     * @param value item to remove from listMap
     */

    function remove(Uint256 storage listMap, uint256 value) internal {
        for (uint256 i; i < listMap.list.length; i++) {
            if (listMap.list[i] == value) {
                listMap.list[i] = listMap.list[listMap.list.length - 1];
                listMap.list.pop();
                listMap.includes[value] = false;
                return;
            }
        }
        revert NoElementInList();
    }

    /**
     * @dev add list
     * @param listMap listMap which should be changed
     * @param list list of items to add to listMap
     */
    function addList(Address storage listMap, address[] memory list) internal {
        for (uint256 i; i < list.length; i++) {
            add(listMap, list[i]);
        }
    }
    /**
     * @dev add list
     * @param listMap listMap which should be changed
     * @param list list of items to add to listMap
     */

    function addList(Uint256 storage listMap, uint256[] memory list) internal {
        for (uint256 i; i < list.length; i++) {
            add(listMap, list[i]);
        }
    }

    /**
     * @dev add item
     * @param listMap listMap which should be changed
     * @param value item to add to listMap
     */
    function add(Address storage listMap, address value) internal {
        if (listMap.includes[value]) revert ElementAlreadyInList();
        listMap.includes[value] = true;
        listMap.list.push(value);
    }
    /**
     * @dev add item
     * @param listMap listMap which should be changed
     * @param value item to add to listMap
     */

    function add(Uint256 storage listMap, uint256 value) internal {
        if (listMap.includes[value]) revert ElementAlreadyInList();
        listMap.includes[value] = true;
        listMap.list.push(value);
    }
}
