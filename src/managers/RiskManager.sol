// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "../interfaces/IRiskManager.sol";
import "../interfaces/Constants.sol";
import "../access/SpoolAccessControl.sol";
import "../interfaces/IAllocationProvider.sol";

contract RiskManager is IRiskManager, SpoolAccessControllable {
    /* ========== STATE VARIABLES ========== */

    /// @notice Association of a risk provider to a strategy and finally to a risk score [1, 100]
    mapping(address => mapping(address => uint8)) private _riskScores;

    /// @notice Smart Vault risk providers
    mapping(address => address) private _smartVaultRiskProviders;

    /// @notice Smart Vault risk appetite
    mapping(address => int8) private _smartVaultRiskTolerance;

    /// @notice Smart Vault allocation providers
    mapping(address => address) private _smartVaultAllocationProviders;

    constructor(ISpoolAccessControl accessControl) SpoolAccessControllable(accessControl) {}

    /* ========== VIEW FUNCTIONS ========== */

    function calculateAllocation(address smartVault, address[] calldata strategies, uint16[] calldata apys)
        external
        view
        returns (uint256[] memory)
    {
        IAllocationProvider allocationProvider = IAllocationProvider(_smartVaultAllocationProviders[smartVault]);
        return allocationProvider.calculateAllocation(
            AllocationCalculationInput({
                strategies: strategies,
                apys: apys,
                riskScores: getRiskScores(_smartVaultRiskProviders[smartVault], strategies),
                riskTolerance: _smartVaultRiskTolerance[smartVault]
            })
        );
    }

    function getRiskScores(address riskProvider, address[] memory strategies) public view returns (uint8[] memory) {
        uint8[] memory riskScores = new uint8[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            riskScores[i] =
                riskProvider == STATIC_RISK_PROVIDER ? STATIC_RISK_SCORE : _riskScores[riskProvider][strategies[i]];
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
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
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
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
    {
        _smartVaultRiskProviders[smartVault] = riskProvider;
        emit RiskProviderSet(smartVault, riskProvider);
    }

    function setAllocationProvider(address smartVault, address allocationProvider)
        external
        onlyRole(ROLE_ALLOCATION_PROVIDER, allocationProvider)
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
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

        for (uint256 i = 0; i < riskScores.length; i++) {
            if (riskScores[i] > MAX_RISK_SCORE || riskScores[i] < MIN_RISK_SCORE) {
                revert RiskScoreValueOutOfBounds(riskScores[i]);
            }

            _riskScores[msg.sender][strategies[i]] = riskScores[i];
        }

        emit RiskScoresUpdated(msg.sender, strategies, riskScores);
    }
}
