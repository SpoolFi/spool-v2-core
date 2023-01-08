// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/**
 * @dev Grants permission to:
 * - acts as a default admin for other roles,
 * - can whitelist an action with action manager.
 *
 * Is granted to the deployer of the SpoolAccessControl contract.
 *
 * Equals to the DEFAULT_ADMIN_ROLE of the OpenZeppelin AccessControl.
 */
bytes32 constant ROLE_SPOOL_ADMIN = 0x00;

/**
 * @dev Grants permission to manage the role ROLE_SMART_VAULT.
 *
 * Should be granted to smart vault factory contracts.
 */
bytes32 constant ADMIN_ROLE_SMART_VAULT = keccak256("ADMIN_SMART_VAULT");

/**
 * @dev Marks a contract as a smart vault.
 *
 * Is granted to all smart vaults deployed by a smart vault factory.
 */
bytes32 constant ROLE_SMART_VAULT = keccak256("SMART_VAULT");

/**
 * @dev Grants permission to integrate a new smart vault into the Spool ecosystem.
 *
 * Should be granted to smart vault factory contracts.
 */
bytes32 constant ROLE_SMART_VAULT_INTEGRATOR = keccak256("ROLE_SMART_VAULT_INTEGRATOR");

/**
 * @dev Grants permission to manage rewards on smart vaults.
 * TODO
 */
bytes32 constant ROLE_SMART_VAULT_ADMIN = keccak256("SMART_VAULT_ADMIN");

/**
 * @dev Grants permission to manage allowlists with AllowlistGuard for a smart vault.
 *
 * Should be granted to whoever is in charge of maintaining allowlists with AllowlistGuard for a smart vault.
 */
bytes32 constant ROLE_GUARD_ALLOWLIST_MANAGER = keccak256("GUARD_ALLOWLIST_MANAGER");

/**
 * @dev Grants permission to claim assets from strategies.
 *
 * Should be granted to the SmartVaultManager contract.
 */
bytes32 constant ROLE_STRATEGY_CLAIMER = keccak256("STRATEGY_CLAIMER");

/**
 * @dev Grants permission to manage assets on master wallet.
 *
 * Should be granted to:
 * - the SmartVaultManager contract,
 * - the StrategyRegistry contract.
 */
bytes32 constant ROLE_MASTER_WALLET_MANAGER = keccak256("MASTER_WALLET_MANAGER");

/**
 * @dev Marks a contract as a smart vault manager.
 *
 * Should be granted to the SmartVaultManager contract.
 */
bytes32 constant ROLE_SMART_VAULT_MANAGER = keccak256("SMART_VAULT_MANAGER");

/**
 * @dev Grants permission to act as a risk provider.
 *
 * Should be granted to whoever is allowed to provide risk scores.
 */
bytes32 constant ROLE_RISK_PROVIDER = keccak256("RISK_PROVIDER");
