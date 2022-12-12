// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import "../interfaces/ISpoolAccessControl.sol";

contract SpoolAccessRoles {
    bytes32 public constant ROLE_SPOOL_ADMIN = 0x00;

    /**
     * @dev Grants persmission to manage ROLE_SMART_VAULT.
     */
    bytes32 public constant ADMIN_ROLE_SMART_VAULT = keccak256("ADMIN_SMART_VAULT");

    /**
     * @dev Marks a contract as a smart vault.
     */
    bytes32 public constant ROLE_SMART_VAULT = keccak256("SMART_VAULT");

    /**
     * @dev Grants permission to integrate new smart vault into SPOOL.
     */
    bytes32 public constant ROLE_SMART_VAULT_INTEGRATOR = keccak256("ROLE_SMART_VAULT_INTEGRATOR");

    bytes32 public constant ROLE_SMART_VAULT_ADMIN = keccak256("SMART_VAULT_ADMIN");
    bytes32 public constant ROLE_GUARD_ALLOWLIST_MANAGER = keccak256("GUARD_ALLOWLIST_MANAGER");
    bytes32 public constant ROLE_STRATEGY_CLAIMER = keccak256("STRATEGY_CLAIMER");
    bytes32 public constant ROLE_MASTER_WALLET_MANAGER = keccak256("MASTER_WALLET_MANAGER");
    bytes32 public constant ROLE_SMART_VAULT_MANAGER = keccak256("SMART_VAULT_MANAGER");
    bytes32 public constant ROLE_RISK_PROVIDER = keccak256("RISK_PROVIDER");
}

/**
 * @notice Spool access control management
 */
contract SpoolAccessControl is AccessControlUpgradeable, ISpoolAccessControl, SpoolAccessRoles {
    /* ========== CONSTRUCTOR ========== */

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        _setRoleAdmin(ROLE_SMART_VAULT, ADMIN_ROLE_SMART_VAULT);
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Check whether account was granted given role for given smart vault
     */
    function hasSmartVaultRole(address smartVault, bytes32 role, address account) external view returns (bool) {
        return hasRole(_getSmartVaultRole(smartVault, role), account);
    }

    function checkIsAdminOrVaultAdmin(address smartVault, address account) external view {
        _onlyAdminOrVaultAdmin(smartVault, account);
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Grant role to account for given smart vault
     */
    function grantSmartVaultRole(address smartVault, bytes32 role, address account)
        external
        onlyAdminOrVaultAdmin(smartVault, msg.sender)
    {
        _grantRole(_getSmartVaultRole(smartVault, role), account);
    }

    /**
     * @notice Revoke specific role for given smart vault
     */
    function revokeSmartVaultRole(address smartVault, bytes32 role, address account)
        external
        onlyAdminOrVaultAdmin(smartVault, msg.sender)
    {
        _revokeRole(_getSmartVaultRole(smartVault, role), account);
    }

    /**
     * @notice Renounce specific role for given smart vault
     */
    function renounceSmartVaultRole(address smartVault, bytes32 role) external {
        renounceRole(_getSmartVaultRole(smartVault, role), msg.sender);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _onlyAdminOrVaultAdmin(address smartVault, address account) private view {
        bytes32 vaultAdminRole = _getSmartVaultRole(smartVault, ROLE_SMART_VAULT_ADMIN);
        if (!hasRole(DEFAULT_ADMIN_ROLE, account) && !hasRole(vaultAdminRole, account)) {
            revert MissingRole(vaultAdminRole, account);
        }
    }

    function _getSmartVaultRole(address smartVault, bytes32 role) internal view returns (bytes32) {
        return keccak256(abi.encode(smartVault, role));
    }

    /* ========== MODIFIERS ========== */

    /**
     * @notice Reverts if account not admin or smart vault admin
     */
    modifier onlyAdminOrVaultAdmin(address smartVault, address account) {
        _onlyAdminOrVaultAdmin(smartVault, account);
        _;
    }
}

/**
 * @notice Account access role verification middleware
 */
abstract contract SpoolAccessControllable is SpoolAccessRoles {
    /* ========== CONSTANTS ========== */

    /// @notice Access control manager
    ISpoolAccessControl internal immutable _accessControl;

    /* ========== CONSTRUCTOR ========== */

    constructor(ISpoolAccessControl accessControl_) {
        _accessControl = accessControl_;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Revert with a standard message if `account` is missing `role`.
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!_accessControl.hasRole(role, account)) {
            revert MissingRole(role, account);
        }
    }

    /**
     * @dev Revert with a standard message if `account` is missing `role`.
     */
    function _checkSmartVaultRole(address smartVault, bytes32 role, address account) internal view virtual {
        if (!_accessControl.hasSmartVaultRole(smartVault, role, account)) {
            revert MissingRole(role, account);
        }
    }

    /* ========== MODIFIERS ========== */

    /**
     * @notice Reverts if account was not granted specified role
     */
    modifier onlyRole(bytes32 role, address account) {
        _checkRole(role, account);
        _;
    }

    /**
     * @notice Reverts if account was not granted specified role for given smart vault
     */
    modifier onlySmartVaultRole(address smartVault, bytes32 role, address account) {
        _checkSmartVaultRole(smartVault, role, account);
        _;
    }

    /**
     * @notice Reverts if account not admin or smart vault admin
     */
    modifier onlyAdminOrVaultAdmin(address smartVault, address account) {
        _accessControl.checkIsAdminOrVaultAdmin(smartVault, account);
        _;
    }
}
