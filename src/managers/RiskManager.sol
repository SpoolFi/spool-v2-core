// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../interfaces/IRiskManager.sol";

contract RiskManager is IRiskManager {
    /* ========== STATE VARIABLES ========== */

    /// @notice Risk provider registry
    mapping(address => bool) internal _riskProviders;

    /// @notice Risk score registry
    mapping(address => uint256[]) internal _riskScores;

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice TODO
     */
    function isRiskProvider(address riskProvider_) external view returns (bool) {
        return _riskProviders[riskProvider_];
    }

    /**
     * @notice TODO
     */
    function riskScores(address riskProvider_) external view returns (uint256[] memory) {
        return _riskScores[riskProvider_];
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
    function calculateAllocations(
        address riskProvider,
        address[] memory strategies,
        uint8 riskTolerance,
        uint256[] memory riskScores,
        uint256[] memory strategyApys
    ) external returns (uint256[][] memory) {
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
