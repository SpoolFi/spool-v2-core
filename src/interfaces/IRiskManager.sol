// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

interface IRiskManager {
    function registerRiskProvider(address riskProvider, bool isEnabled) external;

    function setRiskScores(address riskProvider, uint256[] memory riskScores) external;

    function calculateAllocations(
        address riskProvider,
        address[] memory strategies,
        uint8 riskTolerance,
        uint256[] memory riskScores,
        uint256[] memory strategyApys
    ) external returns (uint256[][] memory);

    /// TODO: where to put this? will pass to smart vault
    function reallocate(address smartVault) external;
}
