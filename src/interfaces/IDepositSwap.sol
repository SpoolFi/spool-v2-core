// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./ISwapper.sol";
import "./IMetaVault.sol";

/**
 * @notice Input for swapping and depositing assets.
 * @custom:member inTokens Input tokens to be swapped.
 * @custom:member inAmounts Maximal amount of input tokens to be swapped.
 * @custom:member swapInfo Information needed to perform the swap.
 * @custom:member smartVault Smart vault for which the deposit is made.
 * @custom:member receiver Receiver of the deposit NFT.
 * @custom:member referral Referral address.
 * @custom:member doFlush If true, the smart vault will be flushed after the deposit as part of same transaction.
 */
struct SwapDepositBag {
    address[] inTokens;
    uint256[] inAmounts;
    SwapInfo[] swapInfo;
    address smartVault;
    address receiver;
    address referral;
    bool doFlush;
}

interface IDepositSwap {
    /**
     * @notice Swaps tokens input tokens based on provided swap info and
     * deposits swapped tokens into the smart vault.
     *
     * When sent eth, it will wrap it into WETH. After wrapping, WETH can be swapped
     * if it is included in inTokens parameter.
     * @dev Unswapped tokens are transferred back to the caller.
     * Requirements:
     * - caller must set approval for this contract on input tokens in input amount
     * @param swapDepositBag Data to swap and deposit assets into a smart vault.
     * @return depositNftId ID of the minted deposit NFT.
     */
    function swapAndDeposit(SwapDepositBag calldata swapDepositBag) external payable returns (uint256 depositNftId);

    /**
     * @notice Swaps tokens input tokens based on provided swap info and
     * deposits swapped tokens into the smart vault.
     *
     * When sent eth, it will wrap it into WETH. After wrapping, WETH can be swapped
     * if it is included in inTokens parameter.
     * @dev Unswapped tokens are transferred back to the caller.
     * Requirements:
     * - caller must set approval for this contract on input tokens in input amount
     * @param metaVault for deposit
     * @param inTokens tokens for swap
     * @param inAmounts token amounts for swap
     * @param swapInfo for swapper to perform the swap
     */
    function swapAndDepositIntoMetaVault(
        IMetaVault metaVault,
        address[] calldata inTokens,
        uint256[] calldata inAmounts,
        SwapInfo[] calldata swapInfo
    ) external payable;
}
