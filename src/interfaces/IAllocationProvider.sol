// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

struct AllocationCalculationInput {
    address[] strategies;
    uint16[] apys;
    address riskProvider;
    int8 riskTolerance;
}

interface IAllocationProvider {
    function calculateAllocationProvider(AllocationCalculationInput calldata data)
        external
        view
        returns (uint256[] memory);
}
