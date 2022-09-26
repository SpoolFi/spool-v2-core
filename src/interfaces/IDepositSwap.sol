// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IDepositSwap {
    /**
     * @notice TODO
     * @param vault TODO
     * @param inAssets TODO
     * @param slippages TODO
     * @param outAssets TODO
     * @return depositNFTId TODO
     */
    function swapAndDeposit(
        address vault,
        uint256[] calldata inAssets,
        uint256[] calldata slippages,
        uint256[] calldata outAssets,
        address receiver) external returns (uint256 depositNFTId);
}
