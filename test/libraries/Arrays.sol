// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

library Arrays {
    function toDyn1Uint(uint256[1] memory _self) public returns (uint256[] memory) {
        uint256[] memory result = new uint256[](1);
        result[0] = _self[0];
        return result;
    }

    function toDyn2Uint(uint256[2] memory _self) public returns (uint256[] memory) {
        uint256[] memory result = new uint256[](2);
        result[0] = _self[0];
        result[1] = _self[1];
        return result;
    }

    function toDyn1Addr(address[1] memory _self) public returns (address[] memory) {
        address[] memory result = new address[](1);
        result[0] = _self[0];
        return result;
    }

    function toDyn2Addr(address[2] memory _self) public returns (address[] memory) {
        address[] memory result = new address[](2);
        result[0] = _self[0];
        result[1] = _self[1];
        return result;
    }
}
