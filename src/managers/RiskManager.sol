// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {console} from "forge-std/console.sol";
import "../interfaces/IRiskManager.sol";

contract RiskManager is IRiskManager {
    /* ========== STATE VARIABLES ========== */

    /// @notice TODO
    mapping(address => bool) internal _riskProviders;

    /// @notice TODO
    mapping(address => address) internal _smartVaultRiskProviders;

    /// @notice TODO
    mapping(address => uint256[]) internal _smartVaultAllocations;

    /// @notice TODO
    mapping(address => uint256[]) internal _riskScores;

    /// @notice TODO
    mapping(address => int256) internal _riskTolerances;

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice TODO
     */
    function riskTolerance(address smartVault) external view returns (int256) {
        return _riskTolerances[smartVault];
    }

    /**
     * @notice TODO
     */
    function isRiskProvider(address riskProvider_) external view returns (bool) {
        return _riskProviders[riskProvider_];
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
    function riskScores(address riskProvider_) external view returns (uint256[] memory) {
        return _riskScores[riskProvider_];
    }

    /**
     * @notice TODO
     */
    function allocations(address smartVault) external view returns (uint256[] memory) {
        return _smartVaultAllocations[smartVault];
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice TODO
     */
    function registerRiskProvider(address riskProvider_, bool isEnabled) external {
        require(_riskProviders[riskProvider_] != isEnabled, "RiskManager::registerRiskProvider: Flag already set.");
        _riskProviders[riskProvider_] = isEnabled;
    }

    /**
     * @notice TODO
     */
    function setRiskScores(address riskProvider_, uint256[] memory riskScores)
        external
        validRiskProvider(riskProvider_)
    {
        _riskScores[riskProvider_] = riskScores;
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

    /* ========== INTERNAL FUNCTIONS ========== */

    function _validRiskProvider(address riskProvider_) internal view {
        require(_riskProviders[riskProvider_], "RiskManager::_validRiskProvider: Invalid risk provider");
    }

    /* ========== MODIFIERS ========== */

    modifier validRiskProvider(address riskProvider_) {
        _validRiskProvider(riskProvider_);
        _;
    }
}
