// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/managers/RiskManager.sol";

contract RiskManagerTest is Test {
    IRiskManager riskManager;
    address riskProvider = address(10);
    address smartVault = address(100);

    function setUp() public {
        riskManager = new RiskManager();
    }

    function test_registerRiskProvider() public {
        vm.expectRevert("RiskManager::registerRiskProvider: Flag already set.");
        riskManager.registerRiskProvider(riskProvider, false);
        assertFalse(riskManager.isRiskProvider(riskProvider));

        riskManager.registerRiskProvider(riskProvider, true);
        assertTrue(riskManager.isRiskProvider(riskProvider));
    }

    function test_setRiskScore() public {
        uint256[] memory riskScores = riskManager.riskScores(riskProvider);
        assertEq(riskScores.length, 0);

        uint256[] memory riskScores2 = new uint256[](2);
        riskScores2[0] = 1;
        riskScores2[1] = 2;

        vm.expectRevert("RiskManager::_validRiskProvider: Invalid risk provider");
        riskManager.setRiskScores(riskProvider, riskScores2);

        riskManager.registerRiskProvider(riskProvider, true);
        riskManager.setRiskScores(riskProvider, riskScores2);

        riskScores = riskManager.riskScores(riskProvider);
        assertEq(riskScores.length, 2);
    }
}
