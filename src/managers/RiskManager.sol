// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "../interfaces/IRiskManager.sol";
import "../access/SpoolAccessControl.sol";

contract RiskManager is IRiskManager, SpoolAccessControllable {
    /* ========== STATE VARIABLES ========== */

    /// @notice Risk score registry
    mapping(address => uint256[]) internal _riskScores;

    constructor(ISpoolAccessControl accessControl) SpoolAccessControllable(accessControl) {}

    /* ========== VIEW FUNCTIONS ========== */

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
    function setRiskScores(address riskProvider_, uint256[] memory riskScores)
        external
        onlyRole(ROLE_RISK_PROVIDER, riskProvider_)
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
}
