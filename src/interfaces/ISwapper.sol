// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "./ISmartVaultManager.sol";

interface ISwapper {
    /**
     * @notice Performs a swap with external contracts.
     * @param swapInfo Information needed to perform the swap.
     */
    function swap(SwapInfo memory swapInfo) external;
}
