// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/interfaces/IRiskManager.sol";

contract MockRiskManager is IRiskManager {
    function test_mock() external pure {}

    function registerRiskProvider(address, bool) external pure {
        revert("0");
    }

    function setRiskScores(address, uint256[] memory) external pure {
        revert("0");
    }

    function setRiskProvider(address, address) external pure {
        revert("0");
    }

    function calculateAllocations(
        address,
        address[] memory,
        uint8,
        uint256[] memory,
        uint256[] memory
    ) external pure returns (uint256[][] memory) {
        revert("0");
    }

    function reallocate(address) external pure {
        revert("0");
    }

    function setAllocations(address, uint256[] memory) external pure {
        revert("0");
    }

    function riskScores(address) external pure returns (uint256[] memory) {
        revert("0");
    }

    function riskTolerance(address) external pure returns (int256) {
        revert("0");
    }

    function riskProvider(address) external pure returns (address) {
        revert("0");
    }

    function isRiskProvider(address) external pure returns (bool) {
        revert("0");
    }

    function allocations(address) external pure returns (uint256[] memory) {
        revert("0");
    }

    function getRiskScores(address, address[] memory)
        external
        view
        virtual
        returns (uint256[] memory)
    {
        revert("0");
    }
}
