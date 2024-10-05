// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

/**
 * @title IPirexEth
 * @notice Interface for the PirexEth contract
 * @dev This interface defines the methods for interacting with PirexEth.
 * @author redactedcartel.finance
 */
interface IPirexEth {
    /**
     * @notice Handle pxETH minting in return for ETH deposits
     * @dev    This function handles the minting of pxETH in return for ETH deposits.
     * @param  receiver        address  Receiver of the minted pxETH or apxEth
     * @param  shouldCompound  bool     Whether to also compound into the vault
     * @return postFeeAmount   uint256  pxETH minted for the receiver
     * @return feeAmount       uint256  pxETH distributed as fees
     */
    function deposit(address receiver, bool shouldCompound)
        external
        payable
        returns (uint256 postFeeAmount, uint256 feeAmount);

    /**
     * @notice The AutoPxEth contract responsible for automated management of the pxEth token.
     * @dev    This variable holds the address of the AutoPxEth contract,
     *         which represents pxEth deposit to auto compounding vault.
     */
    function autoPxEth() external view returns (address);

    /**
     * @notice The PxEth contract responsible for managing the pxEth token.
     * @dev    This variable holds the address of the PxEth contract,
     *         which represents ETH deposit made to Dinero protocol.
     */
    function pxEth() external view returns (address);
}
