// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin-upgradeable/security/PausableUpgradeable.sol";
import "../interfaces/ISpoolAccessControl.sol";
import "./Roles.sol";

/**
 * @notice Spool access control management
 */
contract SpoolAccessControl is AccessControlUpgradeable, PausableUpgradeable, ISpoolAccessControl {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    mapping(address => address) public smartVaultOwner;
    mapping(address => address) public smartVaultOwnerPending;

    /* ========== CONSTRUCTOR ========== */

    constructor() {}

    function initialize() public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ROLE_STRATEGY, ADMIN_ROLE_STRATEGY);
        _setRoleAdmin(ROLE_SMART_VAULT_ALLOW_REDEEM, ADMIN_ROLE_SMART_VAULT_ALLOW_REDEEM);
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

    function grantSmartVaultOwnership(address smartVault, address owner)
        external
        onlyRole(ROLE_SMART_VAULT_INTEGRATOR)
    {
        if (smartVaultOwner[smartVault] != address(0)) {
            revert SmartVaultOwnerAlreadySet(smartVault);
        }

        smartVaultOwner[smartVault] = owner;
        _grantRole(_getSmartVaultRole(smartVault, ROLE_SMART_VAULT_ADMIN), owner);

        emit SmartVaultOwnershipGranted(smartVault, owner);
    }

    /**
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     */
    function transferSmartVaultOwnership(address smartVault, address newOwner) external {
        if (msg.sender != smartVaultOwner[smartVault]) revert OwnableUnauthorizedAccount(msg.sender);
        smartVaultOwnerPending[smartVault] = newOwner;
        emit SmartVaultOwnershipTransferStarted(smartVault, msg.sender, newOwner);
    }

    /**
     * @dev The new owner accepts the ownership transfer.
     */
    function acceptSmartVaultOwnership(address smartVault) external {
        address newOwner = msg.sender;
        if (newOwner != smartVaultOwnerPending[smartVault]) revert OwnableUnauthorizedAccount(newOwner);
        delete smartVaultOwnerPending[smartVault];
        address oldOwner = smartVaultOwner[smartVault];
        smartVaultOwner[smartVault] = newOwner;
        bytes32 smartVaultRole = _getSmartVaultRole(smartVault, ROLE_SMART_VAULT_ADMIN);
        _revokeRole(smartVaultRole, oldOwner);
        _grantRole(smartVaultRole, newOwner);
        emit SmartVaultOwnershipTransferred(smartVault, oldOwner, newOwner);
    }

    function grantSmartVaultRole(address smartVault, bytes32 role, address account)
        external
        onlyAdminOrVaultAdmin(smartVault, msg.sender)
    {
        _grantRole(_getSmartVaultRole(smartVault, role), account);
        emit SmartVaultRoleGranted(smartVault, role, account);
    }

    function revokeSmartVaultRole(address smartVault, bytes32 role, address account)
        external
        onlyAdminOrVaultAdmin(smartVault, msg.sender)
    {
        _revokeRole(_getSmartVaultRole(smartVault, role), account);
        emit SmartVaultRoleRevoked(smartVault, role, account);
    }

    function renounceSmartVaultRole(address smartVault, bytes32 role) external {
        renounceRole(_getSmartVaultRole(smartVault, role), msg.sender);
        emit SmartVaultRoleRenounced(smartVault, role, msg.sender);
    }

    function pause() external onlyRole(ROLE_PAUSER) {
        _pause();
    }

    function unpause() external onlyRole(ROLE_UNPAUSER) {
        _unpause();
    }

    function checkNonReentrant() public view {
        if (_status == _ENTERED) {
            revert ReentrantCall();
        }
    }

    function nonReentrantBefore() external {
        _checkRoleForReentrancy();
        checkNonReentrant();

        _status = _ENTERED;
    }

    function nonReentrantAfter() external {
        _checkRoleForReentrancy();

        _status = _NOT_ENTERED;
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

    function _checkRoleForReentrancy() internal view {
        if (!(hasRole(ROLE_STRATEGY_REGISTRY, msg.sender) || hasRole(ROLE_SMART_VAULT_MANAGER, msg.sender))) {
            revert NoReentrantRole();
        }
    }

    /* ========== MODIFIERS ========== */

    modifier onlyAdminOrVaultAdmin(address smartVault, address account) {
        _onlyAdminOrVaultAdmin(smartVault, account);
        _;
    }
}
