// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

interface IRiskManager {
    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Calculates allocation between strategies based on
     * - risk scores of strategies
     * - risk appetite
     * @param riskProvider Risk provider to use.
     * @param strategies Strategies.
     * @param riskAppetite Risk appetite.
     * @return allocation Calculated allocation.
     */
    function calculateAllocation(address riskProvider, address[] calldata strategies, uint256 riskAppetite)
        external
        view
        returns (uint256[] memory allocation);

    function riskScores(address riskProvider) external view returns (uint256[] memory riskScores);

    function getRiskScores(address riskProvider, address[] memory strategy)
        external
        view
        returns (uint256[] memory riskScores);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function setRiskScores(address riskProvider, uint256[] memory riskScores) external;
}
