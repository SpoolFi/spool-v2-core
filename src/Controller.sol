// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/access/AccessControl.sol";
import "./managers/StrategyManager.sol";
import "./managers/RiskManager.sol";

contract Controller is StrategyManager, RiskManager, AccessControl {
    constructor() {}
}
