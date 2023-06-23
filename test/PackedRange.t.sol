// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "@openzeppelin/utils/Strings.sol";
import "../src/libraries/PackedRange.sol";
import "./libraries/Arrays.sol";

struct TestCase {
    uint256 low;
    uint256 high;
    uint256 val;
    bool expected;
}

contract RackedRangeTest is Test {
    function test_isWithinRange() public {
        TestCase[] memory testCases = new TestCase[](20);

        testCases[0] = TestCase(1, 3, 2, true); // normal case
        testCases[1] = TestCase(1, 3, 1, true); // value on lower range
        testCases[2] = TestCase(1, 3, 3, true); // value on upper range
        testCases[3] = TestCase(1, 3, 0, false); // value too low
        testCases[4] = TestCase(1, 3, 4, false); // value too high
        testCases[5] = TestCase(1, 1, 1, true); // lower and upper range equal
        testCases[6] = TestCase(1, 1, 0, false);
        testCases[7] = TestCase(1, 1, 2, false);
        testCases[8] = TestCase(3, 1, 2, false); // impossible ranges
        testCases[9] = TestCase(3, 1, 4, false);
        testCases[10] = TestCase(3, 1, 0, false);
        testCases[11] = TestCase(0, PackedRange.MAX, 0, true); // limit values
        testCases[12] = TestCase(0, PackedRange.MAX, PackedRange.MAX, true);
        testCases[13] = TestCase(0, PackedRange.MAX, 834765, true);
        testCases[14] = TestCase(0, 0, 0, true);
        testCases[15] = TestCase(0, 0, 1, false);
        testCases[16] = TestCase(PackedRange.MAX, PackedRange.MAX, PackedRange.MAX, true);
        testCases[17] = TestCase(PackedRange.MAX, PackedRange.MAX, 1, false);
        testCases[18] = TestCase(0, PackedRange.MAX, PackedRange.MAX + 1, false); // value out of bounds
        testCases[19] = TestCase(0, PackedRange.MAX, type(uint256).max, false);

        for (uint256 i; i < testCases.length; ++i) {
            TestCase memory testCase = testCases[i];

            uint256 range = Arrays.toPackedRange(testCase.low, testCase.high);

            assertEq(
                PackedRange.isWithinRange(range, testCase.val),
                testCase.expected,
                string.concat("case: ", Strings.toString(i))
            );
        }
    }
}
