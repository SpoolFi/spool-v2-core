// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IStrategyManager {
    function isStrategy(address strategy) external view returns (bool);
    function registerStrategy(address strategy) external;
    function removeStrategy(address strategy) external;
    function getLatestIndexes(address smartVault) external view returns (uint256[] memory);
    function strategies(address smartVault) external view returns (address[] memory strategyAddresses);
    function setStrategies(address smartVault, address[] memory strategies) external;
    function addStrategyDeposits(
        address smartVault,
        uint256[] memory allocations,
        uint256[] memory amounts,
        address[] memory tokens
    ) external;
}
