// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/ISmartVaultManager.sol";

contract SmartVaultManager is ISmartVaultManager {
    /* ========== STATE VARIABLES ========== */

    /// @notice TODO
    IStrategyRegistry internal immutable _strategyRegistry;

    /// @notice TODO
    mapping(address => address[]) internal _smartVaultStrategies;

    /// @notice TODO
    mapping(address => bool) internal _smartVaults;

    /// @notice TODO
    mapping(address => uint256) internal _flushIndexes;

    /// @notice TODO
    mapping(address => address) internal _smartVaultRiskProviders;

    /// @notice TODO
    mapping(address => uint256[]) internal _smartVaultAllocations;

    /// @notice TODO
    mapping(address => int256) internal _riskTolerances;

    /// @notice TODO smartVault => flushIndex => asset => depositAmount
    mapping(address => mapping(uint256 => mapping(address => uint256))) _vaultDeposits;

    constructor(IStrategyRegistry StrategyRegistry_) {
        _strategyRegistry = StrategyRegistry_;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice TODO
     */
    function isSmartVault(address address_) external view returns (bool) {
        return _smartVaults[address_];
    }

    /**
     * @notice TODO
     */
    function getLatestFlushIndex(address smartVault) external view returns (uint256) {
        return _flushIndexes[smartVault];
    }

    /**
     * @notice TODO
     */
    function strategies(address smartVault) external view returns (address[] memory) {
        return _smartVaultStrategies[smartVault];
    }

    /**
     * @notice TODO
     */
    function allocations(address smartVault) external view returns (uint256[] memory) {
        return _smartVaultAllocations[smartVault];
    }

    /**
     * @notice TODO
     */
    function riskProvider(address smartVault) external view returns (address) {
        return _smartVaultRiskProviders[smartVault];
    }

    /**
     * @notice TODO
     */
    function riskTolerance(address smartVault) external view returns (int256) {
        return _riskTolerances[smartVault];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Gets total value (in USD) of assets managed by the vault.
     */
    function getVaultTotalUsdValue(address smartVault) external view returns (uint256) {
        address[] memory strategyAddresses = _smartVaultStrategies[smartVault];

        uint256 totalUsdValue = 0;

        for (uint256 i = 0; i < strategyAddresses.length; i++) {
            IStrategy strategy = IStrategy(strategyAddresses[i]);
            totalUsdValue =
                totalUsdValue + strategy.totalUsdValue() * strategy.balanceOf(smartVault) / strategy.totalSupply();
        }

        return totalUsdValue;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice TODO
     */
    function registerSmartVault(address smartVault) external {
        require(!_smartVaults[smartVault], "SmartVaultManager::registerSmartVault: Address already registered.");
        _smartVaults[smartVault] = true;
    }

    /**
     * @notice TODO
     */
    function removeSmartVault(address smartVault) external validSmartVault(smartVault) {
        _smartVaults[smartVault] = false;
    }

    /**
     * @notice TODO
     */
    function setStrategies(address smartVault, address[] memory strategies_) external validSmartVault(smartVault) {
        require(strategies_.length > 0, "SmartVaultManager::setStrategies: Strategy array empty");

        for (uint256 i = 0; i < strategies_.length; i++) {
            address strategy = strategies_[i];
            require(
                _strategyRegistry.isStrategy(strategy), "SmartVaultManager::registerStrategy: Strategy not registered."
            );
        }

        _smartVaultStrategies[smartVault] = strategies_;
    }

    /**
     * @notice TODO
     */
    function addDeposits(
        address smartVault,
        uint256[] memory allocations,
        uint256[] memory amounts,
        address[] memory tokens
    ) external validSmartVault(smartVault) returns (uint256) {
        require(tokens.length == amounts.length, "SmartVaultManager::addDeposits: Invalid length");
        return 0;
    }

    /**
     * @notice TODO
     */
    function setAllocations(address smartVault, uint256[] memory allocations_) external {
        _smartVaultAllocations[smartVault] = allocations_;
    }

    /**
     * @notice TODO
     */
    function setRiskProvider(address smartVault, address riskProvider_) external validRiskProvider(riskProvider_) {
        _smartVaultRiskProviders[smartVault] = riskProvider_;
    }

    /**
     * @notice TODO
     */
    function syncSmartVault(address smartVault) external {}

    /**
     * @notice TODO
     */
    function flushSmartVault(address smartVault) external {}

    /**
     * @notice TODO
     */
    function reallocate() external {}

    /* ========== PRIVATE/INTERNAL FUNCTIONS ========== */

    function _validRiskProvider(address riskProvider_) internal view {
        // TODO: check if valid risk provider
    }

    /* ========== MODIFIERS ========== */

    modifier validRiskProvider(address riskProvider_) {
        _validRiskProvider(riskProvider_);
        _;
    }

    modifier validSmartVault(address address_) {
        require(_smartVaults[address_], "SmartVaultManager::validSmartVault: Address not Smart Vault.");
        _;
    }
}
