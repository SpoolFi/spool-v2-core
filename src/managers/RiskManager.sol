// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "../interfaces/IRiskManager.sol";
import "../access/SpoolAccessControl.sol";

contract RiskManager is IRiskManager, SpoolAccessControllable {
    /* ========== STATE VARIABLES ========== */

    /// @notice Risk score registry
    mapping(address => uint256[]) internal _riskScores;

    constructor(ISpoolAccessControl accessControl) SpoolAccessControllable(accessControl) {}

    /* ========== VIEW FUNCTIONS ========== */

    function riskScores(address riskProvider_) external view returns (uint256[] memory) {
        return _riskScores[riskProvider_];
    }

    // TODO: implement
    function getRiskScores(address, address[] memory) external pure returns (uint256[] memory) {
        revert("0");
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function setRiskScores(address riskProvider_, uint256[] memory riskScores_)
        external
        onlyRole(ROLE_RISK_PROVIDER, riskProvider_)
    {
        _riskScores[riskProvider_] = riskScores_;
    }

     // TODO: implement
    function calculateAllocations(
        address,
        address[] memory,
        uint8,
        uint256[] memory,
        uint256[] memory
    ) external pure returns (uint256[][] memory) {
        revert("0");
    }
}
