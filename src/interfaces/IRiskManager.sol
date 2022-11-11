// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

interface IRiskManager {
    function setRiskScores(address riskProvider, uint256[] memory riskScores) external;

    function calculateAllocations(
        address riskProvider,
        address[] memory strategies,
        uint8 riskTolerance,
        uint256[] memory riskScores,
        uint256[] memory strategyApys
    ) external returns (uint256[][] memory);

    /**
     * @notice TODO
     */
    function riskScores(address riskProvider) external view returns (uint256[] memory);
}
