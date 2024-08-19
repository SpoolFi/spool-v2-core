// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "forge-std/console.sol";

library ArraysHelper {
    function sort(address[] memory array) public pure returns (address[] memory) {
        for (uint256 i = 1; i < array.length; ++i) {
            address current = array[i];

            uint256 j = i;
            while (j > 0 && array[j - 1] > current) {
                array[j] = array[j - 1];
                --j;
            }

            array[j] = current;
        }

        return array;
    }

    function toArray(string memory x1) public pure returns (string[] memory) {
        string[] memory result = new string[](1);
        result[0] = x1;
        return result;
    }

    function toArray(string memory x1, string memory x2) public pure returns (string[] memory) {
        string[] memory result = new string[](2);
        result[0] = x1;
        result[1] = x2;
        return result;
    }

    function toArray(string memory x1, string memory x2, string memory x3) public pure returns (string[] memory) {
        string[] memory result = new string[](3);
        result[0] = x1;
        result[1] = x2;
        result[2] = x3;
        return result;
    }

    function test_mock() external pure {}
}
