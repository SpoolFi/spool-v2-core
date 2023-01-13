// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

library Arrays {
    function test_lib() external pure {}

    function toArray(uint256 x1) public pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](1);
        result[0] = x1;
        return result;
    }

    function toArray(uint256 x1, uint256 x2) public pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](2);
        result[0] = x1;
        result[1] = x2;
        return result;
    }

    function toArray(uint256 x1, uint256 x2, uint256 x3) public pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](3);
        result[0] = x1;
        result[1] = x2;
        result[2] = x3;
        return result;
    }

    function toArray(uint256 x1, uint256 x2, uint256 x3, uint256 x4) public pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](4);
        result[0] = x1;
        result[1] = x2;
        result[2] = x3;
        result[3] = x4;
        return result;
    }

    function toArray(address x1) public pure returns (address[] memory) {
        address[] memory result = new address[](1);
        result[0] = x1;
        return result;
    }

    function toArray(address x1, address x2) public pure returns (address[] memory) {
        address[] memory result = new address[](2);
        result[0] = x1;
        result[1] = x2;
        return result;
    }

    function toArray(address x1, address x2, address x3) public pure returns (address[] memory) {
        address[] memory result = new address[](3);
        result[0] = x1;
        result[1] = x2;
        result[2] = x3;
        return result;
    }
}
