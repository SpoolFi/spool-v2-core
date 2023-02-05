// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/managers/RiskManager.sol";
import "./libraries/Arrays.sol";

contract RiskManagerTest is Test {
    IRiskManager riskManager;
    SpoolAccessControl accessControl;
    address riskProvider = address(10);
    address allocationProvider = address(11);
    address smartVault = address(100);
    address actor = actor;

    function setUp() public {
        accessControl = new SpoolAccessControl();
        accessControl.initialize();
        riskManager = new RiskManager(accessControl);
    }

    function test_setRiskScore_success() public {
        address[] memory strategies = Arrays.toArray(address(1), address(2));
        uint8[] memory riskScores = new uint8[](2);
        riskScores[0] = 1_0;
        riskScores[1] = 2_0;

        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);

        vm.prank(riskProvider);
        riskManager.setRiskScores(riskScores, strategies);

        riskScores = riskManager.getRiskScores(riskProvider, strategies);
        assertEq(riskScores.length, 2);
        assertEq(riskScores[0], 1_0);
        assertEq(riskScores[1], 2_0);
    }

    function test_setRiskScore_missingRole() public {
        address[] memory strategies = Arrays.toArray(address(1), address(2));
        uint8[] memory riskScores = new uint8[](2);
        riskScores[0] = 1_0;
        riskScores[1] = 2_0;

        vm.prank(riskProvider);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_RISK_PROVIDER, riskProvider));
        riskManager.setRiskScores(riskScores, strategies);
    }

    function test_setRiskScore_revertOutOfBounds() public {
        address[] memory strategies = Arrays.toArray(address(1), address(2));
        uint8[] memory riskScores = new uint8[](2);
        riskScores[0] = 150;
        riskScores[1] = 200;

        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
        vm.prank(riskProvider);
        vm.expectRevert(abi.encodeWithSelector(RiskScoreValueOutOfBounds.selector, 150));
        riskManager.setRiskScores(riskScores, strategies);
    }

    function test_setRiskScore_revertInvalidInputLength() public {
        address[] memory strategies = Arrays.toArray(address(1));
        uint8[] memory riskScores = new uint8[](2);
        riskScores[0] = 150;
        riskScores[1] = 200;

        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
        vm.prank(riskProvider);
        vm.expectRevert(abi.encodeWithSelector(InvalidRiskInputLength.selector));
        riskManager.setRiskScores(riskScores, strategies);
    }

    function test_setRiskProvider_success() public {
        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, actor);
        vm.prank(actor);
        riskManager.setRiskProvider(smartVault, riskProvider);

        assertEq(riskManager.getRiskProvider(smartVault), riskProvider);
    }

    function test_setRiskProvider_revertMissingRole() public {
        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
        vm.prank(actor);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SMART_VAULT_MANAGER, actor));
        riskManager.setRiskProvider(smartVault, riskProvider);
    }

    function test_setRiskProvider_revertInvalidProvider() public {
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, actor);
        vm.prank(actor);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_RISK_PROVIDER, riskProvider));
        riskManager.setRiskProvider(smartVault, riskProvider);
    }

    function test_setAllocationProvider_success() public {
        accessControl.grantRole(ROLE_ALLOCATION_PROVIDER, allocationProvider);
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, actor);
        vm.prank(actor);
        riskManager.setAllocationProvider(smartVault, allocationProvider);

        assertEq(riskManager.getAllocationProvider(smartVault), allocationProvider);
    }

    function test_setAllocationProvider_revertMissingRole() public {
        accessControl.grantRole(ROLE_ALLOCATION_PROVIDER, allocationProvider);
        vm.prank(actor);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SMART_VAULT_MANAGER, actor));
        riskManager.setAllocationProvider(smartVault, allocationProvider);
    }

    function test_setAllocationProvider_revertInvalidProvider() public {
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, actor);
        vm.prank(actor);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_ALLOCATION_PROVIDER, allocationProvider));
        riskManager.setAllocationProvider(smartVault, allocationProvider);
    }

    function test_setRiskTolerance_success() public {
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, actor);
        vm.prank(actor);
        riskManager.setRiskTolerance(smartVault, 1_0);

        assertEq(riskManager.getRiskTolerance(smartVault), 1_0);
    }

    function test_setRiskTolerance_revertMissingRole() public {
        vm.prank(actor);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SMART_VAULT_MANAGER, actor));
        riskManager.setRiskTolerance(smartVault, 1_0);
    }

    function test_setRiskTolerance_revertRiskToleranceOutOfBounds() public {
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, actor);
        vm.prank(actor);
        vm.expectRevert(abi.encodeWithSelector(RiskToleranceValueOutOfBounds.selector, 12));
        riskManager.setRiskTolerance(smartVault, 12);
    }
}
