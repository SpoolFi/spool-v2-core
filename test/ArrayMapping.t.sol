// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Test} from "forge-std/Test.sol";
import {ArrayMapping} from "../src/libraries/ArrayMapping.sol";
import {Arrays} from "./libraries/Arrays.sol";

contract ArrayMappingTest is Test {
    TestArrayMappingUsage testArrayMappingUsage;

    function setUp() public {
        testArrayMappingUsage = new TestArrayMappingUsage();
    }

    function test_toArray_shouldRetrieveMappingValuesAsArray() public {
        uint256[] memory values = Arrays.toArray(1, 2, 4, 8);

        testArrayMappingUsage.setFirstLevelValue(0, values[0]);
        testArrayMappingUsage.setFirstLevelValue(1, values[1]);
        testArrayMappingUsage.setFirstLevelValue(2, values[2]);
        testArrayMappingUsage.setFirstLevelValue(3, values[3]);

        assertEq(testArrayMappingUsage.batchGetFirstLevelValues(4), values);
    }

    function test_toArray_shouldWorkOnNestedMappings() public {
        uint256[] memory values1 = Arrays.toArray(1, 2, 4);
        uint256[] memory values2 = Arrays.toArray(1, 3, 9);

        testArrayMappingUsage.setSecondLevelValue(1, 0, values1[0]);
        testArrayMappingUsage.setSecondLevelValue(1, 1, values1[1]);
        testArrayMappingUsage.setSecondLevelValue(1, 2, values1[2]);
        testArrayMappingUsage.setSecondLevelValue(2, 0, values2[0]);
        testArrayMappingUsage.setSecondLevelValue(2, 1, values2[1]);
        testArrayMappingUsage.setSecondLevelValue(2, 2, values2[2]);

        assertEq(testArrayMappingUsage.batchGetSecondLevelValues(1, 3), values1);
        assertEq(testArrayMappingUsage.batchGetSecondLevelValues(2, 3), values2);
    }

    function test_toArray_shouldHandleZeroAndNonSetValues() public {
        uint256[] memory values = Arrays.toArray(0, 2, 0, 8);

        testArrayMappingUsage.setFirstLevelValue(0, values[0]);
        testArrayMappingUsage.setFirstLevelValue(1, values[1]);
        testArrayMappingUsage.setFirstLevelValue(3, values[3]);

        assertEq(testArrayMappingUsage.batchGetFirstLevelValues(4), values);
    }

    function test_toArray_shouldHangleZeroLength() public {
        uint256[] memory values = Arrays.toArray(1, 2, 4, 8);

        testArrayMappingUsage.setFirstLevelValue(0, values[0]);

        assertEq(testArrayMappingUsage.batchGetFirstLevelValues(0), new uint256[](0));
    }

    function test_setValues_shouldSetValuesAsMapping() public {
        uint256[] memory values = Arrays.toArray(1, 2, 4, 8);

        testArrayMappingUsage.batchSetFirstLevelValues(values);

        assertEq(testArrayMappingUsage.getFirstLevelValue(0), values[0]);
        assertEq(testArrayMappingUsage.getFirstLevelValue(1), values[1]);
        assertEq(testArrayMappingUsage.getFirstLevelValue(2), values[2]);
        assertEq(testArrayMappingUsage.getFirstLevelValue(3), values[3]);
    }

    function test_setValues_shouldWorkOnNestedMappings() public {
        uint256[] memory values1 = Arrays.toArray(1, 2, 4);
        uint256[] memory values2 = Arrays.toArray(1, 3, 9);

        testArrayMappingUsage.batchSetSecondLevelValues(1, values1);
        testArrayMappingUsage.batchSetSecondLevelValues(2, values2);

        assertEq(testArrayMappingUsage.getSecondLevelValue(1, 0), values1[0]);
        assertEq(testArrayMappingUsage.getSecondLevelValue(1, 1), values1[1]);
        assertEq(testArrayMappingUsage.getSecondLevelValue(1, 2), values1[2]);
        assertEq(testArrayMappingUsage.getSecondLevelValue(2, 0), values2[0]);
        assertEq(testArrayMappingUsage.getSecondLevelValue(2, 1), values2[1]);
        assertEq(testArrayMappingUsage.getSecondLevelValue(2, 2), values2[2]);
    }

    function test_setValues_shouldHandleZeroValues() public {
        uint256[] memory values = Arrays.toArray(0, 2, 0, 8);

        testArrayMappingUsage.batchSetFirstLevelValues(values);

        assertEq(testArrayMappingUsage.getFirstLevelValue(0), values[0]);
        assertEq(testArrayMappingUsage.getFirstLevelValue(1), values[1]);
        assertEq(testArrayMappingUsage.getFirstLevelValue(2), values[2]);
        assertEq(testArrayMappingUsage.getFirstLevelValue(3), values[3]);
    }

    function test_setValues_shouldHandleZeroLengthArray() public {
        uint256[] memory values = new uint256[](0);

        testArrayMappingUsage.batchSetFirstLevelValues(values);
    }

    function test_setValues_shouldOverwriteExistingValues() public {
        uint256[] memory values1 = Arrays.toArray(1);
        uint256[] memory values2 = Arrays.toArray(2, 3, 4);
        uint256[] memory values3 = Arrays.toArray(5, 6);

        testArrayMappingUsage.batchSetFirstLevelValues(values1);

        assertEq(testArrayMappingUsage.getFirstLevelValue(0), values1[0]);

        testArrayMappingUsage.batchSetFirstLevelValues(values2);
        assertEq(testArrayMappingUsage.getFirstLevelValue(0), values2[0]);
        assertEq(testArrayMappingUsage.getFirstLevelValue(1), values2[1]);
        assertEq(testArrayMappingUsage.getFirstLevelValue(2), values2[2]);

        testArrayMappingUsage.batchSetFirstLevelValues(values3);
        assertEq(testArrayMappingUsage.getFirstLevelValue(0), values3[0]);
        assertEq(testArrayMappingUsage.getFirstLevelValue(1), values3[1]);
        // will not delete already set values when overwriting
        assertEq(testArrayMappingUsage.getFirstLevelValue(2), values2[2]);
    }
}

contract TestArrayMappingUsage {
    using ArrayMapping for mapping(uint256 => uint256);

    mapping(uint256 => uint256) firstLevelMapping;
    mapping(uint256 => mapping(uint256 => uint256)) secondLevelMapping;

    function test_mock() external pure {}

    function getFirstLevelValue(uint256 index) external view returns (uint256) {
        return firstLevelMapping[index];
    }

    function setFirstLevelValue(uint256 index, uint256 value) external {
        firstLevelMapping[index] = value;
    }

    function getSecondLevelValue(uint256 firstLevelIndex, uint256 secondLevelIndex) external view returns (uint256) {
        return secondLevelMapping[firstLevelIndex][secondLevelIndex];
    }

    function setSecondLevelValue(uint256 firstLevelIndex, uint256 secondLevelIndex, uint256 value) external {
        secondLevelMapping[firstLevelIndex][secondLevelIndex] = value;
    }

    function batchGetFirstLevelValues(uint256 length) external view returns (uint256[] memory) {
        return firstLevelMapping.toArray(length);
    }

    function batchSetFirstLevelValues(uint256[] calldata values) external {
        firstLevelMapping.setValues(values);
    }

    function batchGetSecondLevelValues(uint256 firstLevelIndex, uint256 length)
        external
        view
        returns (uint256[] memory)
    {
        return secondLevelMapping[firstLevelIndex].toArray(length);
    }

    function batchSetSecondLevelValues(uint256 firstLevelIndex, uint256[] calldata values) external {
        secondLevelMapping[firstLevelIndex].setValues(values);
    }
}
