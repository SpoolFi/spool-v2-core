// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../interfaces/ISmartVault.sol";

/* ========== ERRORS ========== */

error CallerNotAllowlistManager(address caller, address smartVault);

/* ========== CONTRACTS ========== */

contract AllowlistGuard {
    /* ========== EVENTS ========== */

    event AddedToAllowlist(address indexed smartVault, uint256 indexed allowlistId, address[] addresses);

    event RemovedFromAllowlist(address indexed smartVault, uint256 indexed allowlistId, address[] addresses);

    /* ========== STATE VARIABLES ========== */

    bytes32 public constant ALLOWLIST_MANAGER_ROLE = keccak256("ALLOWLIST_MANAGER_ROLE");

    // vault => allowlist ID => address => allowed
    mapping(address => mapping(uint256 => mapping(address => bool))) private allowlists;

    /* ========== CONSTRUCTOR ========== */

    constructor() {}

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function isAllowed(address smartVault, uint256 allowlistId, address address_) external view returns (bool) {
        return allowlists[smartVault][allowlistId][address_];
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function addToAllowlist(address smartVault, uint256 allowlistId, address[] calldata addresses)
        external
        onlyAllowlistManager(smartVault)
    {
        for (uint256 i = 0; i < addresses.length; i++) {
            allowlists[smartVault][allowlistId][addresses[i]] = true;
        }

        emit AddedToAllowlist(smartVault, allowlistId, addresses);
    }

    function removeFromAllowlist(address smartVault, uint256 allowlistId, address[] calldata addresses)
        external
        onlyAllowlistManager(smartVault)
    {
        for (uint256 i = 0; i < addresses.length; i++) {
            allowlists[smartVault][allowlistId][addresses[i]] = false;
        }

        emit RemovedFromAllowlist(smartVault, allowlistId, addresses);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _onlyAllowlistManager(address smartVault) private view {
        if (!ISmartVault(smartVault).hasRole(ALLOWLIST_MANAGER_ROLE, msg.sender)) {
            revert CallerNotAllowlistManager(msg.sender, smartVault);
        }
    }

    /* ========== MODIFIERS ========== */

    modifier onlyAllowlistManager(address smartVault) {
        _onlyAllowlistManager(smartVault);
        _;
    }
}
