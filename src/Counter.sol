// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract Counter {
    uint256 public number;

    function addNumbers(address contract_)
        external returns (bool, bytes memory)
    {
        uint256 a_ = 1;
        uint256 b_ = 2;
        // bytes32 a = bytes32(a_);
        // bytes32 b = bytes32(b_);

        bytes memory a = abi.encodePacked(uint(1));
        bytes memory b = abi.encodePacked(uint(2));
        
        (bool success, bytes memory d) = contract_.call(abi.encodeWithSignature("addNumbers(uint256,uint256)", a, b));
        return (success, d);
    }

    function returnAddress(address contract_)
        external returns (bool, bytes memory)
    {
        bytes32 a = bytes32(uint256(uint160(address(32))));
        (bool success, bytes memory d) = contract_.call(abi.encodeWithSignature("returnAddress(address)", abi.encodePacked(address(32))));
        return (success, d);
    }
}
