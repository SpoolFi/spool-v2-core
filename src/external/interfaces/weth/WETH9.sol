// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

interface IWETH9 {
    function deposit() external payable;

    function transfer(address dst, uint256 wad) external returns (bool);
}
