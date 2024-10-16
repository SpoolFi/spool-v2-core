// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../interfaces/ISmartVault.sol";
import "../interfaces/Constants.sol";
import "../access/SpoolAccessControllable.sol";

/* ========== CONTRACTS ========== */

contract UnlockGuard is SpoolAccessControllable {
    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when smart vault owner updates the unlock
     * @param smartVault Address of the smart vault.
     * @param unlock value of the unlock, in seconds
     */
    event UpdatedUnlock(address indexed smartVault, uint256 indexed unlock);

    /* ========== STATE VARIABLES ========== */

    /**
     * @notice Limited Timelocks for a smart vault.
     * Each smart vault can have a single unlock, updated by the owner.
     */
    mapping(address => uint256) public unlocks;

    /* ========== CONSTANTS ========== */

    constructor(ISpoolAccessControl accessControl_) SpoolAccessControllable(accessControl_) {}

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Check if the vault is unlocked
     * @param smartVault Address of the smart vault.
     * @return valid True when the vault is unlocked, false otherwise.
     */
    function checkUnlock(address smartVault) external view returns (bool) {
        return block.timestamp >= unlocks[smartVault];
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Update the unlock for a smart vault.
     * @dev Requirements:
     * - caller must be the owner of the smart vault
     * @param smartVault Address of the smart vault.
     * @param unlock New unlock value, in seconds.
     */
    function updateUnlock(address smartVault, uint256 unlock)
        external
        onlySmartVaultRole(smartVault, ROLE_SMART_VAULT_ADMIN, msg.sender)
    {
        unlocks[smartVault] = unlock;

        emit UpdatedUnlock(smartVault, unlock);
    }
}
