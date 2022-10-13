// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IStrategyRegistry {
    function isStrategy(address strategy) external view returns (bool);
    function registerStrategy(address strategy) external;
    function removeStrategy(address strategy) external;
    function getLatestIndexes(address smartVault) external view returns (uint256[] memory);
}
