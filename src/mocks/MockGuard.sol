// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {console} from "forge-std/console.sol";

contract MockGuard {
    mapping(address => bool) whitelist;

    function isWhitelisted(address address_) external view returns(bool) {
        return whitelist[address_];
    }

    function setWhitelist(address address_, bool whitelisted_) external {
        whitelist[address_] = whitelisted_;
    }
}