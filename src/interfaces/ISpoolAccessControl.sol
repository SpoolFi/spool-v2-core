// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "@openzeppelin-upgradeable/access/IAccessControlUpgradeable.sol";

/**
 * @notice Used when an account is missing a required role.
 * @param role Required role.
 * @param account Account missing the required role.
 */
error MissingRole(bytes32 role, address account);

/**
 * @notice Used when interacting with Spool when the system is paused.
 */
error SystemPaused();

/**
 * @notice Used when setting smart vault owner
 */
error SmartVaultOwnerAlreadySet(address smartVault);

interface ISpoolAccessControl is IAccessControlUpgradeable {
    /* ========== VIEW FUNCTIONS ========== */

    function smartVaultOwner(address smartVault) external view returns (address);

    /**
     * @notice Looks if an account has a role for a smart vault.
     * @param smartVault Address of the smart vault.
     * @param role Role to look for.
     * @param account Account to check.
     * @return hasRole True if account has the role for the smart vault, false otherwise.
     */
    function hasSmartVaultRole(address smartVault, bytes32 role, address account)
        external
        view
        returns (bool hasRole);

    /**
     * @notice Checks if an account is either Spool admin or admin for a smart vault.
     * @dev The function reverts if account is neither.
     * @param smartVault Address of the smart vault.
     * @param account to check.
     */
    function checkIsAdminOrVaultAdmin(address smartVault, address account) external view;

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() external view returns (bool);

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Pause the system,
     */
    function pause() external;

    /**
     * @dev Unpause the system,
     */
    function unpause() external;

    /**
     * @notice Grants role to an account for a smart vault.
     * @param smartVault Address of the smart vault.
     * @param role Role to grant.
     * @param account Account to grant the role to.
     */
    function grantSmartVaultRole(address smartVault, bytes32 role, address account) external;

    /**
     * @notice Revokes role from an account for a smart vault.
     * @param smartVault Address of the smart vault.
     * @param role Role to revoke.
     * @param account Account to revoke the role from.
     */
    function revokeSmartVaultRole(address smartVault, bytes32 role, address account) external;

    /**
     * @notice Renounce role for a smart vault.
     * @param smartVault Address of the smart vault.
     * @param role Role to renounce.
     */
    function renounceSmartVaultRole(address smartVault, bytes32 role) external;

    /**
     * @notice Grant ownership to smart vault
     * @param smartVault Address of the smart vault.
     * @param owner address to which grant ownership to
     */
    function grantSmartVaultOwnership(address smartVault, address owner) external;
}
