// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {console} from "forge-std/console.sol";

contract MockGuard {
    mapping(address => bool) whitelist;

    function isWhitelisted(address address_) external view returns (bool) {
        return whitelist[address_];
    }

    function checkAddressesLength(uint256 expectedResult, address[] memory addresses) external pure returns (bool) {
        return expectedResult == addresses.length;
    }

    function setWhitelist(address address_, bool whitelisted_) external {
        whitelist[address_] = whitelisted_;
    }

    function checkArraySum(uint256[] memory numbers, uint256 expectedValue) external pure returns (bool) {
        uint256 result = 0;
        for (uint256 i = 0; i < numbers.length; i++) {
            result += numbers[i];
        }

        return result == expectedValue;
    }
}
