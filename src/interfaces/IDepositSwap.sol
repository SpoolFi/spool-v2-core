// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IDepositSwap {
    function swapAndDeposit(
        address vault,
        uint256[] calldata inAssets,
        uint256[] calldata slippages,
        uint256[] calldata outAssets,
        address receiver) external returns (uint256 depositNFTId);
}
