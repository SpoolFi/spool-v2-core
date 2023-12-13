// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/providers/ExponentialNormalizedAllocationProvider.sol";
import "./libraries/Arrays.sol";

contract ExponentialNormalizedAllocationProviderTest is Test {
    IAllocationProvider allocationProvider;

    function setUp() public {
        allocationProvider = new ExponentialNormalizedAllocationProvider();
    }

    function test_calculateAllocation_case01() public {
        address[] memory strategies = Arrays.toArray(address(11), address(12), address(13));
        int256[] memory apys = new int256[](3);
        apys[0] = 3_18 * YIELD_FULL_PERCENT_INT / 100_00; // 3.18%
        apys[1] = 4_19 * YIELD_FULL_PERCENT_INT / 100_00; // 4.19%
        apys[2] = 6_00 * YIELD_FULL_PERCENT_INT / 100_00; // 6.00%
        uint8[] memory riskScores = new uint8[](3);
        riskScores[0] = 2;
        riskScores[1] = 5;
        riskScores[2] = 5;
        int8 riskTolerance = -10;

        AllocationCalculationInput memory input =
            AllocationCalculationInput(strategies, apys, riskScores, riskTolerance);

        uint256[] memory allocation = allocationProvider.calculateAllocation(input);
        assertApproxEqAbs(allocation[0], 54_70, 2);
        assertApproxEqAbs(allocation[1], 22_34, 1);
        assertApproxEqAbs(allocation[2], 22_97, 1);

        uint256 allocationSum;
        for (uint256 i; i < allocation.length; ++i) {
            allocationSum += allocation[i];
        }
        assertEq(allocationSum, FULL_PERCENT);
    }

    function test_calculateAllocation_case02() public {
        address[] memory strategies = Arrays.toArray(address(11), address(12), address(13));
        int256[] memory apys = new int256[](3);
        apys[0] = 3_18 * YIELD_FULL_PERCENT_INT / 100_00; // 3.18%
        apys[1] = 4_19 * YIELD_FULL_PERCENT_INT / 100_00; // 4.19%
        apys[2] = 6_00 * YIELD_FULL_PERCENT_INT / 100_00; // 6.00%
        uint8[] memory riskScores = new uint8[](3);
        riskScores[0] = 2;
        riskScores[1] = 5;
        riskScores[2] = 5;
        int8 riskTolerance = 0;

        AllocationCalculationInput memory input =
            AllocationCalculationInput(strategies, apys, riskScores, riskTolerance);

        uint256[] memory allocation = allocationProvider.calculateAllocation(input);
        assertApproxEqAbs(allocation[0], 34_53, 2);
        assertApproxEqAbs(allocation[1], 21_00, 1);
        assertApproxEqAbs(allocation[2], 44_48, 1);

        uint256 allocationSum;
        for (uint256 i; i < allocation.length; ++i) {
            allocationSum += allocation[i];
        }
        assertEq(allocationSum, FULL_PERCENT);
    }

    function test_calculateAllocation_case03() public {
        address[] memory strategies = Arrays.toArray(address(11), address(12), address(13));
        int256[] memory apys = new int256[](3);
        apys[0] = 3_18 * YIELD_FULL_PERCENT_INT / 100_00; // 3.18%
        apys[1] = 4_19 * YIELD_FULL_PERCENT_INT / 100_00; // 4.19%
        apys[2] = 6_00 * YIELD_FULL_PERCENT_INT / 100_00; // 6.00%
        uint8[] memory riskScores = new uint8[](3);
        riskScores[0] = 2;
        riskScores[1] = 5;
        riskScores[2] = 5;
        int8 riskTolerance = 10;

        AllocationCalculationInput memory input =
            AllocationCalculationInput(strategies, apys, riskScores, riskTolerance);

        uint256[] memory allocation = allocationProvider.calculateAllocation(input);
        assertApproxEqAbs(allocation[0], 98, 2);
        assertApproxEqAbs(allocation[1], 1_99, 1);
        assertApproxEqAbs(allocation[2], 97_03, 1);

        uint256 allocationSum;
        for (uint256 i; i < allocation.length; ++i) {
            allocationSum += allocation[i];
        }
        assertEq(allocationSum, FULL_PERCENT);
    }

    function test_calculateAllocation_shouldGiveFullAllocationWhenSingleStrategy() public {
        address[] memory strategies = Arrays.toArray(address(11));
        int256[] memory apys = new int256[](1);
        apys[0] = 3_18 * YIELD_FULL_PERCENT_INT / 100_00; // 3.18%
        uint8[] memory riskScores = new uint8[](1);
        riskScores[0] = 2;
        int8 riskTolerance = 5;

        AllocationCalculationInput memory input =
            AllocationCalculationInput(strategies, apys, riskScores, riskTolerance);

        uint256[] memory allocation = allocationProvider.calculateAllocation(input);
        assertEq(allocation[0], 100_00);

        uint256 allocationSum;
        for (uint256 i; i < allocation.length; ++i) {
            allocationSum += allocation[i];
        }
        assertEq(allocationSum, FULL_PERCENT);
    }

    function test_calculateAllocation_shouldGiveZeroAllocationWhenStrategyHasNegativeApy() public {
        address[] memory strategies = Arrays.toArray(address(11), address(12), address(13));
        int256[] memory apys = new int256[](3);
        apys[0] = 3_18 * YIELD_FULL_PERCENT_INT / 100_00; // 3.18%
        apys[1] = -4_19 * YIELD_FULL_PERCENT_INT / 100_00; // -4.19%
        apys[2] = 6_00 * YIELD_FULL_PERCENT_INT / 100_00; // 6.00%
        uint8[] memory riskScores = new uint8[](3);
        riskScores[0] = 2;
        riskScores[1] = 5;
        riskScores[2] = 5;
        int8 riskTolerance = 0;

        AllocationCalculationInput memory input =
            AllocationCalculationInput(strategies, apys, riskScores, riskTolerance);

        uint256[] memory allocation = allocationProvider.calculateAllocation(input);
        assertApproxEqAbs(allocation[0], 31_28, 1);
        assertEq(allocation[1], 0);
        assertApproxEqAbs(allocation[2], 68_72, 1);

        uint256 allocationSum;
        for (uint256 i; i < allocation.length; ++i) {
            allocationSum += allocation[i];
        }
        assertEq(allocationSum, FULL_PERCENT);
    }

    function test_calculateAllocation_shouldGiveUniformAllocationWhenAllStrategiesHaveNegativeApy() public {
        address[] memory strategies = Arrays.toArray(address(11), address(12), address(13));
        int256[] memory apys = new int256[](3);
        apys[0] = -3_18 * YIELD_FULL_PERCENT_INT / 100_00; // -3.18%
        apys[1] = -4_19 * YIELD_FULL_PERCENT_INT / 100_00; // -4.19%
        apys[2] = -6_00 * YIELD_FULL_PERCENT_INT / 100_00; // -6.00%
        uint8[] memory riskScores = new uint8[](3);
        riskScores[0] = 2;
        riskScores[1] = 5;
        riskScores[2] = 5;
        int8 riskTolerance = 0;

        AllocationCalculationInput memory input =
            AllocationCalculationInput(strategies, apys, riskScores, riskTolerance);

        uint256[] memory allocation = allocationProvider.calculateAllocation(input);
        assertApproxEqAbs(allocation[0], 33_33, 2);
        assertApproxEqAbs(allocation[1], 33_33, 1);
        assertApproxEqAbs(allocation[2], 33_33, 1);

        uint256 allocationSum;
        for (uint256 i; i < allocation.length; ++i) {
            allocationSum += allocation[i];
        }
        assertEq(allocationSum, FULL_PERCENT);
    }
}
