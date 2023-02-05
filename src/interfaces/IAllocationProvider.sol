// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

error ApysOrRiskScoresLengthMismatch(uint256, uint256);

struct AllocationCalculationInput {
    address[] strategies;
    uint16[] apys;
    uint8[] riskScores;
    int8 riskTolerance;
}

interface IAllocationProvider {
    function calculateAllocation(AllocationCalculationInput calldata data) external view returns (uint256[] memory);
}
