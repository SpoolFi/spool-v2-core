// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "./ISmartVaultManager.sol";

interface ISwapper {
    /**
     * @notice Performs a swap of tokens with external contracts.
     * - deposit tokens into the swapper contract
     * - swapper will swap tokens based on swap info provided
     * - swapper will return unswapped tokens to the receiver
     * @param tokens Addresses of tokens available for the swap.
     * @param swapInfo Information needed to perform the swap.
     * @param receiver Receiver of unswapped tokens.
     */
    function swap(address[] calldata tokens, SwapInfo[] calldata swapInfo, address receiver) external;
}
