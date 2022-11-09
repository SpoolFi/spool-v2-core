// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import "../interfaces/ISpoolAccessControl.sol";

/**
 * @notice Spool access control management
 */
contract SpoolAccessControl is AccessControlUpgradeable, ISpoolAccessControl {
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Check whether account was granted given role for given smart vault
     */
    function hasSmartVaultRole(address smartVault, bytes32 role, address account) external view returns (bool) {
        bytes32 role_ = keccak256(abi.encodePacked(smartVault, role));
        return hasRole(role_, account);
    }

    /**
     * @notice Grant role to account for given smart vault
     */
    function grantSmartVaultRole(address smartVault, bytes32 role, address account) external {
        bytes32 role_ = keccak256(abi.encodePacked(smartVault, role));
        grantRole(role_, account);
    }
}

contract SpoolAccessRoles {
    bytes32 public constant ROLE_SMART_VAULT = keccak256("SMART_VAULT");
    bytes32 public constant ROLE_GUARD_ALLOWLIST_MANAGER = keccak256("GUARD_ALLOWLIST_MANAGER");
    bytes32 public constant ROLE_STRATEGY_CLAIMER = keccak256("STRATEGY_CLAIMER");
}

/**
 * @notice Account access role verification middleware
 */
abstract contract SpoolAccessControllable is SpoolAccessRoles {
    /// @notice Access control manager
    ISpoolAccessControl internal immutable _accessControl;

    constructor(ISpoolAccessControl accessControl_) {
        _accessControl = accessControl_;
    }

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
}
