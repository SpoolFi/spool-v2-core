// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "./ISmartVaultManager.sol";

/**
 * @notice Information needed to make a swap of assets.
 * @custom:member swapTarget Contract executing the swap.
 * @custom:member token Token to be swapped.
 * @custom:member amountIn Amount to swap.
 * @custom:member swapCallData Calldata describing the swap itself.
 */
struct SwapInfo {
    address swapTarget;
    address token;
    uint256 amountIn;
    bytes swapCallData;
}

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
