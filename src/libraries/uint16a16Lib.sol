// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

type uint16a16 is uint256;

library uint16a16Lib {
    uint256 constant bits = 16;
    uint256 constant elements = 16;
    // must ensure that bits * elements <= 256
    uint256 constant range = 1 << bits;
    uint256 constant max = range - 1;

    // get function
    function get(uint16a16 va, uint256 index) internal pure returns (uint256) {
        require(index < elements);
        return (uint16a16.unwrap(va) >> (bits * index)) & max;
    }

    // set function
    function set(uint16a16 va, uint256 index, uint256 ev) internal pure returns (uint16a16) {
        require(index < elements);
        require(ev < range);
        index *= bits;
        return uint16a16.wrap((uint16a16.unwrap(va) & ~(max << index)) | (ev << index));
    }

    function set(uint16a16 va, uint256[] memory ev) internal pure returns (uint16a16) {
        for (uint256 i = 0; i < ev.length; i++) {
            va = set(va, i, ev[i]);
        }

        return va;
    }
}
