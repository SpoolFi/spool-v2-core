// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin-upgradeable/security/PausableUpgradeable.sol";
import "../interfaces/ISpoolAccessControl.sol";
import "./Roles.sol";

/**
 * @notice Spool access control management
 */
contract SpoolAccessControl is AccessControlUpgradeable, PausableUpgradeable, ISpoolAccessControl {
    /* ========== CONSTRUCTOR ========== */

    constructor() {}

    function initialize() public initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ROLE_SMART_VAULT, ADMIN_ROLE_SMART_VAULT);
        __Pausable_init();
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function hasSmartVaultRole(address smartVault, bytes32 role, address account) external view returns (bool) {
        return hasRole(_getSmartVaultRole(smartVault, role), account);
    }

    function checkIsAdminOrVaultAdmin(address smartVault, address account) external view {
        _onlyAdminOrVaultAdmin(smartVault, account);
    }

    function paused() public view override(ISpoolAccessControl, PausableUpgradeable) returns (bool) {
        return super.paused();
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function grantSmartVaultRole(address smartVault, bytes32 role, address account)
        external
        onlyAdminOrVaultAdmin(smartVault, msg.sender)
    {
        _grantRole(_getSmartVaultRole(smartVault, role), account);
    }

    function revokeSmartVaultRole(address smartVault, bytes32 role, address account)
        external
        onlyAdminOrVaultAdmin(smartVault, msg.sender)
    {
        _revokeRole(_getSmartVaultRole(smartVault, role), account);
    }

    function renounceSmartVaultRole(address smartVault, bytes32 role) external {
        renounceRole(_getSmartVaultRole(smartVault, role), msg.sender);
    }

    function pause() external onlyRole(ROLE_PAUSER) {
        _pause();
    }

    function unpause() external onlyRole(ROLE_UNPAUSER) {
        _unpause();
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _onlyAdminOrVaultAdmin(address smartVault, address account) private view {
        bytes32 vaultAdminRole = _getSmartVaultRole(smartVault, ROLE_SMART_VAULT_ADMIN);
        if (!hasRole(DEFAULT_ADMIN_ROLE, account) && !hasRole(vaultAdminRole, account)) {
            revert MissingRole(vaultAdminRole, account);
        }
    }

    function _getSmartVaultRole(address smartVault, bytes32 role) internal pure returns (bytes32) {
        return keccak256(abi.encode(smartVault, role));
    }

    function _checkRole(bytes32 role, address account) internal view override {
        if (!hasRole(role, account)) {
            revert MissingRole(role, account);
        }
    }

    /* ========== MODIFIERS ========== */

    modifier onlyAdminOrVaultAdmin(address smartVault, address account) {
        _onlyAdminOrVaultAdmin(smartVault, account);
        _;
    }
}

/**
 * @notice Account access role verification middleware
 */
abstract contract SpoolAccessControllable {
    /* ========== CONSTANTS ========== */

    /**
     * @dev Spool access control manager.
     */
    ISpoolAccessControl internal immutable _accessControl;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @param accessControl_ Spool access control manager.
     */
    constructor(ISpoolAccessControl accessControl_) {
        _accessControl = accessControl_;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Reverts if an account is missing a role.\
     * @param role Role to check for.
     * @param account Account to check.
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!_accessControl.hasRole(role, account)) {
            revert MissingRole(role, account);
        }
    }

    /**
     * @dev Revert if an account is missing a role for a smartVault.
     * @param smartVault Address of the smart vault.
     * @param role Role to check for.
     * @param account Account to check.
     */
    function _checkSmartVaultRole(address smartVault, bytes32 role, address account) private view {
        if (!_accessControl.hasSmartVaultRole(smartVault, role, account)) {
            revert MissingRole(role, account);
        }
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        if (_accessControl.paused()) {
            revert SystemPaused();
        }
    }

    /* ========== MODIFIERS ========== */

    /**
     * @notice Only allows accounts with granted role.
     * @dev Reverts when the account fails check.
     * @param role Role to check for.
     * @param account Account to check.
     */
    modifier onlyRole(bytes32 role, address account) {
        _checkRole(role, account);
        _;
    }

    /**
     * @notice Only allows accounts with granted role for a smart vault.
     * @dev Reverts when the account fails check.
     * @param smartVault Address of the smart vault.
     * @param role Role to check for.
     * @param account Account to check.
     */
    modifier onlySmartVaultRole(address smartVault, bytes32 role, address account) {
        _checkSmartVaultRole(smartVault, role, account);
        _;
    }

    /**
     * @notice Only allows accounts that are Spool admins or admins of a smart vault.
     * @dev Reverts when the account fails check.
     * @param smartVault Address of the smart vault.
     * @param account Account to check.
     */
    modifier onlyAdminOrVaultAdmin(address smartVault, address account) {
        _accessControl.checkIsAdminOrVaultAdmin(smartVault, account);
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }
}
