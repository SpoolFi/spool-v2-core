// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "./interfaces/IDepositSwap.sol";

contract DepositSwap is IDepositSwap {
    /* ========== STATE VARIABLES ========== */

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Initializes variables
     */
    constructor() {}
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
        address receiver
    ) external returns (uint256 depositNFTId) {
        revert("0");
    }

    /* ========== MODIFIERS ========== */

    /* ========== EXTERNAL FUNCTIONS ========== */

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /* ========== PUBLIC FUNCTIONS ========== */

    /* ========== INTERNAL FUNCTIONS ========== */

    /* ========== PRIVATE FUNCTIONS ========== */
}
