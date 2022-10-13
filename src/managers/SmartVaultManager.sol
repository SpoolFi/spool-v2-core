// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/ISmartVaultManager.sol";
import "../interfaces/IRiskManager.sol";

contract SmartVaultRegistry is ISmartVaultRegistry {
    /// @notice TODO
    mapping(address => bool) internal _smartVaults;

    /**
     * @notice TODO
     */
    function isSmartVault(address address_) external view returns (bool) {
        return _smartVaults[address_];
    }

    /**
     * @notice TODO
     */
    function registerSmartVault(address smartVault) external {
        if (_smartVaults[smartVault]) revert SmartVaultAlreadyRegistered({address_: smartVault});
        _smartVaults[smartVault] = true;
    }

    /**
     * @notice TODO
     */
    function removeSmartVault(address smartVault) external validSmartVault(smartVault) {
        _smartVaults[smartVault] = false;
    }

    /* ========== MODIFIERS ========== */

    modifier validSmartVault(address address_) {
        if (!_smartVaults[address_]) revert InvalidSmartVault({address_: address_});
        _;
    }
}

contract SmartVaultFlusher is SmartVaultRegistry, ISmartVaultFlusher {
    /// @notice TODO
    IStrategyRegistry private immutable _strategyRegistry;

    /// @notice TODO
    mapping(address => uint256) internal _flushIndexes;

    /// @notice TODO smartVault => flushIndex => asset => depositAmount
    mapping(address => mapping(uint256 => mapping(address => uint256))) _vaultDeposits;

    constructor(IStrategyRegistry strategyRegistry_) {
        _strategyRegistry = strategyRegistry_;
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
    function smartVaultDeposits(address smartVault) external returns (uint256[] memory) {
        revert("0");
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
        if (tokens.length != amounts.length) revert InvalidAssetLengths();
        return 0;
    }

    /**
     * @notice TODO
     */
    function flushSmartVault(address smartVault) external validSmartVault(smartVault) {}
}

contract SmartVaultManager is SmartVaultRegistry, SmartVaultFlusher, ISmartVaultManager {
    /* ========== STATE VARIABLES ========== */

    /// @notice TODO
    IStrategyRegistry private immutable _strategyRegistry;

    IRiskManager private immutable _riskManager;

    /// @notice TODO
    mapping(address => address[]) internal _smartVaultStrategies;

    /// @notice TODO
    mapping(address => address) internal _smartVaultRiskProviders;

    /// @notice TODO
    mapping(address => uint256[]) internal _smartVaultAllocations;

    /// @notice TODO
    mapping(address => int256) internal _riskTolerances;

    constructor(IStrategyRegistry strategyRegistry_, IRiskManager riskManager_) SmartVaultFlusher(strategyRegistry_) {
        _strategyRegistry = strategyRegistry_;
        _riskManager = riskManager_;
    }

    /* ========== VIEW FUNCTIONS ========== */

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
    function setStrategies(address smartVault, address[] memory strategies_) external validSmartVault(smartVault) {
        if (strategies_.length == 0) revert EmptyStrategyArray();

        for (uint256 i = 0; i < strategies_.length; i++) {
            address strategy = strategies_[i];
            if (!_strategyRegistry.isStrategy(strategy)) revert InvalidStrategy({address_: strategy});
        }

        _smartVaultStrategies[smartVault] = strategies_;
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
    function reallocate() external {}

    /* ========== PRIVATE/INTERNAL FUNCTIONS ========== */

    /* ========== MODIFIERS ========== */

    modifier validRiskProvider(address address_) {
        if (!_riskManager.isRiskProvider(address_)) revert InvalidRiskProvider({address_: address_});
        _;
    }
}
