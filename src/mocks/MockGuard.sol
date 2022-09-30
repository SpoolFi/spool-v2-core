// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {console} from "forge-std/console.sol";

contract MockGuard {
    mapping(address => bool) whitelist;

    function isWhitelisted(address address_) external view returns (bool) {
        return whitelist[address_];
    }

    function sumAndCompare(uint256[] memory values, uint256 expectedResult) external view returns (bool) {
        uint256 result = 0;
        for (uint256 i = 0; i > values.length; i++) {
            result += values[i];
        }

        return expectedResult == result;
    }

    function setWhitelist(address address_, bool whitelisted_) external {
        whitelist[address_] = whitelisted_;
    }
}
