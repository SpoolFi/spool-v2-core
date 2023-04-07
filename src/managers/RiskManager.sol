// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../interfaces/IAllocationProvider.sol";
import "../interfaces/IRiskManager.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/Constants.sol";
import "../access/SpoolAccessControllable.sol";
import "../libraries/uint16a16Lib.sol";

contract RiskManager is IRiskManager, SpoolAccessControllable {
    using uint16a16Lib for uint16a16;

    /* ========== STATE VARIABLES ========== */

    /// @notice Association of a risk provider to a strategy and finally to a risk score [1, 100]
    mapping(address => mapping(address => uint8)) private _riskScores;

    /// @notice Smart Vault risk providers
    mapping(address => address) private _smartVaultRiskProviders;

    /// @notice Smart Vault risk appetite
    mapping(address => int8) private _smartVaultRiskTolerance;

    /// @notice Smart Vault allocation providers
    mapping(address => address) private _smartVaultAllocationProviders;

    address private immutable _ghostStrategy;

    /// @notice Strategy registry address
    IStrategyRegistry private immutable _strategyRegistry;

    constructor(ISpoolAccessControl accessControl, IStrategyRegistry strategyRegistry_, address ghostStrategy)
        SpoolAccessControllable(accessControl)
    {
        if (address(strategyRegistry_) == address(0)) revert ConfigurationAddressZero();
        if (address(ghostStrategy) == address(0)) revert ConfigurationAddressZero();

        _ghostStrategy = ghostStrategy;
        _strategyRegistry = strategyRegistry_;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function calculateAllocation(address smartVault, address[] calldata strategies)
        public
        view
        returns (uint16a16 allocations)
    {
        // Strategies that are not ghost strategies, their risk scores, and indexes to map to original arrays
        address[] memory validStrategies;
        uint256[] memory indexes;
        (validStrategies, indexes) = _getValidStrategies(strategies);

        uint8[] memory riskScores = getRiskScores(_smartVaultRiskProviders[smartVault], validStrategies);

        int256[] memory apyList = _strategyRegistry.strategyAPYs(validStrategies);
        uint256[] memory allocations_ = IAllocationProvider(_smartVaultAllocationProviders[smartVault])
            .calculateAllocation(
            AllocationCalculationInput({
                strategies: validStrategies,
                apys: apyList,
                riskScores: riskScores,
                riskTolerance: _smartVaultRiskTolerance[smartVault]
            })
        );

        uint256 allocationsSum;
        // allocations_ array might have less values than the number of incoming strategies due to ghost strategies
        for (uint256 i; i < strategies.length; ++i) {
            if (strategies[i] != _ghostStrategy) {
                allocations = allocations.set(i, allocations_[indexes[i]]);
                allocationsSum += allocations_[indexes[i]];
            }
        }

        // Allocations should sum up to FULL_PERCENT
        if (allocationsSum != FULL_PERCENT) {
            revert InvalidAllocationSum(allocationsSum);
        }

        return allocations;
    }

    function getRiskScores(address riskProvider, address[] memory strategies) public view returns (uint8[] memory) {
        uint8[] memory riskScores = new uint8[](strategies.length);
        for (uint256 i; i < strategies.length; ++i) {
            riskScores[i] =
                riskProvider == STATIC_RISK_PROVIDER ? STATIC_RISK_SCORE : _riskScores[riskProvider][strategies[i]];

            if (strategies[i] != _ghostStrategy && riskScores[i] == 0) {
                revert InvalidRiskScores(riskProvider, strategies[i]);
            }
        }

        return riskScores;
    }

    function getRiskProvider(address smartVault) external view returns (address) {
        return _smartVaultRiskProviders[smartVault];
    }

    function getAllocationProvider(address smartVault) external view returns (address) {
        return _smartVaultAllocationProviders[smartVault];
    }

    function getRiskTolerance(address smartVault) external view returns (int8) {
        return _smartVaultRiskTolerance[smartVault];
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function setRiskTolerance(address smartVault, int8 riskTolerance)
        external
        onlyRole(ROLE_SMART_VAULT_INTEGRATOR, msg.sender)
    {
        if (riskTolerance > MAX_RISK_TOLERANCE || riskTolerance < MIN_RISK_TOLERANCE) {
            revert RiskToleranceValueOutOfBounds(riskTolerance);
        }

        _smartVaultRiskTolerance[smartVault] = riskTolerance;
        emit RiskToleranceSet(smartVault, riskTolerance);
    }

    function setRiskProvider(address smartVault, address riskProvider)
        external
        onlyRole(ROLE_RISK_PROVIDER, riskProvider)
        onlyRole(ROLE_SMART_VAULT_INTEGRATOR, msg.sender)
    {
        _smartVaultRiskProviders[smartVault] = riskProvider;
        emit RiskProviderSet(smartVault, riskProvider);
    }

    function setAllocationProvider(address smartVault, address allocationProvider)
        external
        onlyRole(ROLE_ALLOCATION_PROVIDER, allocationProvider)
        onlyRole(ROLE_SMART_VAULT_INTEGRATOR, msg.sender)
    {
        _smartVaultAllocationProviders[smartVault] = allocationProvider;
        emit AllocationProviderSet(smartVault, allocationProvider);
    }

    function setRiskScores(uint8[] calldata riskScores, address[] calldata strategies)
        external
        onlyRole(ROLE_RISK_PROVIDER, msg.sender)
    {
        if (strategies.length != riskScores.length) {
            revert InvalidRiskInputLength();
        }

        for (uint256 i; i < riskScores.length; ++i) {
            // Risk scores have to be within boundaries, except for ghost strategies, where they should be set to 0
            if (riskScores[i] > MAX_RISK_SCORE || riskScores[i] < MIN_RISK_SCORE && strategies[i] != _ghostStrategy) {
                revert RiskScoreValueOutOfBounds(riskScores[i]);
            }

            // Ghost strategy risk score should be set to 0
            if (strategies[i] == _ghostStrategy && riskScores[i] > 0) {
                revert CannotSetRiskScoreForGhostStrategy(riskScores[i]);
            }

            _riskScores[msg.sender][strategies[i]] = riskScores[i];
        }

        emit RiskScoresUpdated(msg.sender, strategies, riskScores);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @notice Filter strategies and their risk scores to exclude ghost strategies
     */
    function _getValidStrategies(address[] calldata strategies)
        private
        view
        returns (address[] memory strategies_, uint256[] memory indexes)
    {
        uint256 validStrategies;
        for (uint256 i; i < strategies.length; ++i) {
            if (strategies[i] != _ghostStrategy) {
                validStrategies += 1;
            }
        }

        strategies_ = new address[](validStrategies);
        indexes = new uint256[](strategies.length);

        uint256 j;
        for (uint256 i; i < strategies.length; ++i) {
            if (strategies[i] != _ghostStrategy) {
                strategies_[j] = strategies[i];
                indexes[i] = j;
                ++j;
            }
        }
    }
}
