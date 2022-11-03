pragma solidity ^0.8.13;

import "@openzeppelin/token/ERC20/IERC20.sol";

error ManagerAlreadySet(address manager);
error ManagerNotAllowed(address manager);

interface IMasterWallet {
    /**
     * @notice Approves the amount of token the spender can use.
     * @dev Requirements:
     * - must be called by a wallet manager
     * @param token Token on which to make the approval.
     * @param spender Address that is approved.
     * @param amount Amount of tokens to approve.
     */
    function approve(IERC20 token, address spender, uint256 amount) external;

    /**
     * @notice Resets the approval on token for spender back to 0.
     * @dev Requirements:
     * - must be called by a wallet manager
     * @param token Token on which to reset the approval.
     * @param spender Address for which to reset the approval.
     */
    function resetApprove(IERC20 token, address spender) external;

    /**
     * @notice Transfers amount of token to the recipient.
     * @dev Requirements:
     * - must be called by a wallet manager
     * @param token Token to transfer.
     * @param recipient Target of the transfer.
     * @param amount Amount to transfer.
     */
    function transfer(IERC20 token, address recipient, uint256 amount) external;

    /**
     * @notice Sets or unsets the address that is allowed to manage funds.
     * Wallet manager can manage approvals and make transfers.
     * @param manager Address to set.
     * @param set True to set the manager, false to unset.
     */
    function setWalletManager(address manager, bool set) external;
}
