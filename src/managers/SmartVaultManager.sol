// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/ISmartVaultManager.sol";
import "../interfaces/IRiskManager.sol";
import "../interfaces/ISmartVault.sol";

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

contract SmartVaultManager is SmartVaultRegistry, ISmartVaultManager {
    /* ========== STATE VARIABLES ========== */

    uint256 constant PRECISION = 100_00;

    /// @notice TODO
    IStrategyRegistry private immutable _strategyRegistry;

    /// @notice TODO
    IRiskManager private immutable _riskManager;

    /// @notice TODO
    mapping(address => address[]) internal _smartVaultStrategies;

    /// @notice TODO
    mapping(address => address) internal _smartVaultRiskProviders;

    /// @notice TODO
    mapping(address => uint256[]) internal _smartVaultAllocations;

    /// @notice TODO
    mapping(address => int256) internal _riskTolerances;

    /// @notice Current flush index for given Smart Vault
    mapping(address => uint256) internal _flushIndexes;

    /// @notice DHW indexes for given Smart Vault and flush index
    mapping(address => mapping(uint256 => uint256[])) internal _dhwIndexes;

    /// @notice TODO smartVault => flushIdx => depositAmounts
    mapping(address => mapping(uint256 => uint256[])) _vaultDeposits;

    constructor(IStrategyRegistry strategyRegistry_, IRiskManager riskManager_) {
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

    function getLatestFlushIndex(address smartVault) external view returns (uint256) {
        return _flushIndexes[smartVault];
    }

    /**
     * @notice Smart vault deposits for given flush index.
     */
    function smartVaultDeposits(address smartVault, uint256 flushIdx) external returns (uint256[] memory) {
        return _vaultDeposits[smartVault][flushIdx];
    }

    /**
     * @notice DHW indexes that were active at given flush index
     */
    function dhwIndexes(address smartVault, uint256 flushIndex) external view returns (uint256[] memory) {
        return _dhwIndexes[smartVault][flushIndex];
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
    function setAllocations(address smartVault, uint256[] memory allocations_) validSmartVault(smartVault) external {
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
     * @notice Accumulate Smart Vault deposits before pushing to strategies
     * @param smartVault Smart Vault address
     * @param amounts Deposit amounts
     */
    function addDeposits(address smartVault, uint256[] memory amounts)
        external
        validSmartVault(smartVault)
        returns (uint256)
    {
        address[] memory tokens = ISmartVault(smartVault).asset();
        if (tokens.length != amounts.length) revert InvalidAssetLengths();

        uint256 flushIdx = _flushIndexes[smartVault];
        bool initialized = _vaultDeposits[smartVault][flushIdx].length > 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            if (amounts[i] == 0) revert InvalidDepositAmount({smartVault: smartVault});

            if (initialized) {
                _vaultDeposits[smartVault][flushIdx][i] += amounts[i];
            } else {
                _vaultDeposits[smartVault][flushIdx].push(amounts[i]);
            }
        }

        return _flushIndexes[smartVault];
    }

    /**
     * @notice Transfer all pending deposits from the SmartVault to strategies
     * @param smartVault Smart Vault address
     */
    function flushSmartVault(address smartVault) external validSmartVault(smartVault) {
        uint256 flushIdx = _flushIndexes[smartVault];
        address[] memory tokens = ISmartVault(smartVault).asset();
        uint256[] memory amounts = _vaultDeposits[smartVault][flushIdx];

        if (tokens.length != amounts.length) revert InvalidAssetLengths();

        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        uint256[] memory allocations_ = _smartVaultAllocations[smartVault];

        if (strategies_.length != allocations_.length) revert InvalidArrayLength();

        uint256[][] memory depositAmounts = new uint256[][](strategies_.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 accum = 0;

            for (uint256 j = 0; j < strategies_.length; j++) {
                uint256 amount = amounts[i] * allocations_[j] / 100;
                accum += amount;

                if (depositAmounts[j].length == 0) {
                    depositAmounts[j] = new uint256[](tokens.length);
                }

                // Last strategy takes dust
                if (j == strategies_.length - 1) {
                    amount += (amounts[i] - accum);
                }

                depositAmounts[j][i] = amount;
                if (depositAmounts[j][i] == 0) revert InvalidFlushAmount({smartVault: smartVault});
            }
        }

        uint256[] memory dhwIndexes = _strategyRegistry.addDeposits(strategies_, depositAmounts, tokens);
        emit SmartVaultFlushed(smartVault, flushIdx);
        _flushIndexes[smartVault] = flushIdx + 1;
    }

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
