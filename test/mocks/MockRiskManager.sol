// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/interfaces/IRiskManager.sol";

contract MockRiskManager is IRiskManager {
    function registerRiskProvider(address riskProvider, bool isEnabled) external {
        revert("0");
    }

    function setRiskScores(address riskProvider, uint256[] memory riskScores) external {
        revert("0");
    }

    function setRiskProvider(address smartVault, address riskProvider_) external {
        revert("0");
    }

    function calculateAllocations(
        address riskProvider,
        address[] memory strategies,
        uint8 riskTolerance,
        uint256[] memory riskScores,
        uint256[] memory strategyApys
    ) external returns (uint256[][] memory) {
        revert("0");
    }

    /// TODO: where to put this? will pass to smart vault
    function reallocate(address smartVault) external {
        revert("0");
    }

    function setAllocations(address smartVault, uint256[] memory allocations) external {
        revert("0");
    }

    /**
     * @notice TODO
     */
    function riskScores(address riskProvider) external view returns (uint256[] memory) {
        revert("0");
    }

    /**
     * @notice TODO
     * @return riskTolerance
     */
    function riskTolerance(address smartVault) external view returns (int256 riskTolerance) {
        revert("0");
    }

    /**
     * @notice TODO
     * @return riskProviderAddress
     */
    function riskProvider(address smartVault) external view returns (address riskProviderAddress) {
        revert("0");
    }

    /**
     * @notice TODO
     */
    function isRiskProvider(address riskProvider) external view returns (bool) {
        revert("0");
    }

    /**
     * @notice TODO
     * @return allocations
     */
    function allocations(address smartVault) external view returns (uint256[] memory allocations) {
        revert("0");
    }

    /**
     * @notice TODO
     * @return riskScore
     */
    function getRiskScores(address riskProvider, address[] memory strategy)
        external
        view
        virtual
        returns (uint256[] memory)
    {
        revert("0");
    }
}
