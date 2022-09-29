// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IStrategyManager {
    function isStrategy(address strategy) external view returns (bool);
    function registerStrategy(address strategy) external;
    function removeStrategy(address strategy) external;
}
