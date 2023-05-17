// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../../src/interfaces/Constants.sol";
import "../../src/interfaces/IAllocationProvider.sol";

error WeightNotSet(address strategy);

contract MockAllocationProvider is IAllocationProvider {
    mapping(address => uint256) public strategyWeights;
    mapping(address => bool) public weightSet;

    function setWeight(address strategy, uint256 weight) external {
        strategyWeights[strategy] = weight;
        weightSet[strategy] = true;
    }

    function calculateAllocation(AllocationCalculationInput calldata data)
        external
        view
        returns (uint256[] memory allocation)
    {
        uint256 totalAllocation = FULL_PERCENT;
        uint256 totalWeights;

        for (uint256 i; i < data.strategies.length; ++i) {
            if (!weightSet[data.strategies[i]]) {
                revert WeightNotSet(data.strategies[i]);
            }

            totalWeights += strategyWeights[data.strategies[i]];
        }

        allocation = new uint256[](data.strategies.length);
        for (uint256 i; i < data.strategies.length; ++i) {
            uint256 strategyWeight = strategyWeights[data.strategies[i]];
            uint256 strategyAllocation = totalAllocation * strategyWeight / totalWeights;

            totalAllocation -= strategyAllocation;
            totalWeights -= strategyWeight;

            allocation[i] = strategyAllocation;
        }
    }
}
