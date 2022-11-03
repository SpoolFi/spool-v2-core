// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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
