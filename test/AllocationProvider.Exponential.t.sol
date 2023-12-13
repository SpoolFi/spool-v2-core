// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/providers/ExponentialAllocationProvider.sol";
import "./libraries/Arrays.sol";

contract ExponentialAllocationProviderTest is Test {
    IAllocationProvider allocationProvider;

    function setUp() public {
        allocationProvider = new ExponentialAllocationProvider();
    }

    function test_case_01() public {
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
        assertApproxEqAbs(allocation[0], 54_65, 2);
        assertApproxEqAbs(allocation[1], 22_34, 1);
        assertApproxEqAbs(allocation[2], 23_01, 1);

        uint256 allocationSum;
        for (uint256 i; i < allocation.length; ++i) {
            allocationSum += allocation[i];
        }
        assertEq(allocationSum, FULL_PERCENT);
    }

    function test_case_02() public {
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
        assertApproxEqAbs(allocation[0], 21_60, 2);
        assertApproxEqAbs(allocation[1], 17_40, 1);
        assertApproxEqAbs(allocation[2], 61_00, 1);

        uint256 allocationSum;
        for (uint256 i; i < allocation.length; ++i) {
            allocationSum += allocation[i];
        }
        assertEq(allocationSum, FULL_PERCENT);
    }

    function test_case_03() public {
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
        assertApproxEqAbs(allocation[0], 0, 2);
        assertApproxEqAbs(allocation[1], 0, 1);
        assertApproxEqAbs(allocation[2], 100_00, 1);

        uint256 allocationSum;
        for (uint256 i; i < allocation.length; ++i) {
            allocationSum += allocation[i];
        }
        assertEq(allocationSum, FULL_PERCENT);
    }
}
