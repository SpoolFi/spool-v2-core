// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../interfaces/IAllocationProvider.sol";
import "../interfaces/IRiskManager.sol";
import "../interfaces/Constants.sol";

contract LinearAllocationProvider is IAllocationProvider {
    uint256 private constant MULTIPLIER = 1e10;

    function calculateAllocation(AllocationCalculationInput calldata data) external pure returns (uint256[] memory) {
        uint256 allocationSum;
        uint256 apySum;
        uint256 riskSum;
        uint256[] memory allocations = new uint256[](data.apys.length);

        uint24[21] memory riskArray = [
            100000,
            95000,
            90000,
            85000,
            80000,
            75000,
            70000,
            65000,
            60000,
            55000,
            50000,
            45000,
            40000,
            35000,
            30000,
            25000,
            20000,
            15000,
            10000,
            5000,
            0
        ];

        for (uint256 i; i < data.apys.length; ++i) {
            apySum += (data.apys[i] > 0 ? uint256(data.apys[i]) : 0);
            riskSum += data.riskScores[i];
        }

        uint256 riskt = uint8(data.riskTolerance + 10); // from 0 to 20
        uint256 riskWeight = riskArray[riskt];
        uint256 apyWeight = riskArray[20 - riskt];

        for (uint256 i; i < data.apys.length; ++i) {
            uint256 normalizedApy;
            if (data.apys[i] > 0) {
                normalizedApy = (uint256(data.apys[i]) * MULTIPLIER) / apySum;
            }

            // riskSum should never be 0 by system design
            uint256 normalizedRisk = (MULTIPLIER - (data.riskScores[i] * MULTIPLIER) / riskSum) / (data.apys.length - 1);

            allocations[i] = normalizedApy * apyWeight + normalizedRisk * riskWeight;

            allocationSum += allocations[i];
        }

        if (allocationSum <= 0) {
            for (uint256 i; i < allocations.length; ++i) {
                allocations[i] = 1;
            }

            allocationSum = allocations.length;
        }

        uint256 residual = FULL_PERCENT;
        for (uint256 i; i < allocations.length; ++i) {
            allocations[i] = FULL_PERCENT * allocations[i] / allocationSum;
            residual -= allocations[i];
        }

        if (residual > 0) {
            for (uint256 i; i < allocations.length; ++i) {
                if (allocations[i] > 0) {
                    allocations[i] += residual;
                    break;
                }
            }
        }

        return allocations;
    }
}
