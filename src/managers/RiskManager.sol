// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../interfaces/IRiskManager.sol";

contract RiskManager is IRiskManager {
    mapping(address => bool) internal _riskProviders;
    mapping(address => address) internal _smartVaultRiskProviders;
    mapping(address => uint256[]) internal _smartVaultAllocations;
    mapping(address => uint256[]) internal _riskScores;
    mapping(address => int256) internal _riskTolerances;

    /**
     * @notice TODO
     */
    function registerRiskProvider(address riskProvider, bool isEnabled) external {
        _riskProviders[riskProvider] = isEnabled;
    }

    /**
     * @notice TODO
     */
    function setRiskScores(address riskProvider, uint256[] memory riskScores) external {
        revert("0");
    }

    /**
     * @notice TODO
     */
    function calculateAllocations(
        address riskProvider,
        address[] memory strategies,
        uint8 riskTolerance,
        uint256[] memory riskScores,
        uint256[] memory strategyApys
    ) external returns (uint256[][] memory) {
        revert("0");
    }

    /// TODO: where to put this? will pass to smart vault
    function reallocate(address smartVault) external {
        revert("0");
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
    function setRiskProvider(address smartVault, address riskProvider_) external {
        _smartVaultRiskProviders[smartVault] = riskProvider_;
    }

    /**
     * @notice TODO
     */
    function riskTolerance(address smartVault) external view returns (int256) {
        return _riskTolerances[smartVault];
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
    function allocations(address smartVault) external view returns (uint256[] memory) {
        return _smartVaultAllocations[smartVault];
    }
}
