// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/managers/RiskManager.sol";

contract RiskManagerTest is Test, SpoolAccessRoles {
    IRiskManager riskManager;
    ISpoolAccessControl accessControl;
    address riskProvider = address(10);
    address smartVault = address(100);

    function setUp() public {
        accessControl = new SpoolAccessControl();
        riskManager = new RiskManager(accessControl);
    }

    function test_setRiskScore() public {
        uint256[] memory riskScores = riskManager.riskScores(riskProvider);
        assertEq(riskScores.length, 0);

        uint256[] memory riskScores2 = new uint256[](2);
        riskScores2[0] = 1;
        riskScores2[1] = 2;

        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_RISK_PROVIDER, riskProvider));
        riskManager.setRiskScores(riskProvider, riskScores2);

        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
        riskManager.setRiskScores(riskProvider, riskScores2);

        riskScores = riskManager.riskScores(riskProvider);
        assertEq(riskScores.length, 2);
    }
}
