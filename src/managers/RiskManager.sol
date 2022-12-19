// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "../interfaces/IRiskManager.sol";
import "../access/SpoolAccessControl.sol";

contract RiskManager is IRiskManager, SpoolAccessControllable {
    /* ========== STATE VARIABLES ========== */

    // TODO: this should probably be address(riskProvder) => address(strategy) => uint256(riskScore) instead
    /// @notice Risk score registry
    mapping(address => uint256[]) internal _riskScores;

    constructor(ISpoolAccessControl accessControl) SpoolAccessControllable(accessControl) {}

    /* ========== VIEW FUNCTIONS ========== */

    // TODO: implement
    function calculateAllocation(address, address[] calldata, uint256) external pure returns (uint256[] memory) {
        revert("0");
    }

    function riskScores(address riskProvider_) external view returns (uint256[] memory) {
        return _riskScores[riskProvider_];
    }

    // TODO: implement
    function getRiskScores(address, address[] memory) external pure returns (uint256[] memory) {
        revert("0");
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    // TODO: check that caller can set risk scores for risk provider
    function setRiskScores(address riskProvider_, uint256[] memory riskScores_)
        external
        onlyRole(ROLE_RISK_PROVIDER, riskProvider_)
    {
        _riskScores[riskProvider_] = riskScores_;
    }
}
