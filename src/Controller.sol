// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/access/AccessControl.sol";
import "./interfaces/IStrategyManager.sol";
import "./interfaces/IRiskManager.sol";

contract Controller is IStrategyManager, IRiskManager, AccessControl {
    constructor() {}

    function isStrategy(address strategy) external view returns (bool) {
        revert("0");
    }

    function registerStrategy(address strategy) external {
        revert("0");
    }

    function removeStrategy(address strategy) external {
        revert("0");
    }

    function getLatestIndexes(address[] memory strategy) external view returns (uint256[] memory) {
        revert("0");
    }

    function registerRiskProvider(address riskProvider, bool isEnabled) external { revert("0"); }

    function setRiskScores(address riskProvider, uint256[] memory riskScores) external { revert("0"); }

    function calculateAllocations(
        address riskProvider, 
        address[] memory strategies, 
        uint8 riskTolerance, 
        uint256[] memory riskScores,
        uint256[] memory strategyApys
    ) external returns (uint256[][] memory) { revert("0"); }

    /// TODO: where to put this? will pass to smart vault
    function reallocate(address smartVault) external { revert("0"); }
}
