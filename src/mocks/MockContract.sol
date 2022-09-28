// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

contract MockContract {
    function addNumbers(uint256 a, uint256 b) external returns (uint256) {
        return a + b;
    }

    function returnAddress(address address_) external returns (address) {
        return address_;
    }
}