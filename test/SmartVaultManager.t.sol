// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/managers/SmartVaultManager.sol";
import "../src/interfaces/IRiskManager.sol";
import "../src/managers/RiskManager.sol";
import "../src/managers/StrategyRegistry.sol";

contract SmartVaultManagerTest is Test {
    ISmartVaultManager smartVaultManager;
    IStrategyRegistry strategyRegistry;
    IRiskManager riskManager;
    address riskProvider = address(10);
    address smartVault = address(100);

    function setUp() public {
        strategyRegistry = new StrategyRegistry();
        riskManager = new RiskManager();
        smartVaultManager = new SmartVaultManager(strategyRegistry, riskManager);
        smartVaultManager.registerSmartVault(smartVault);
    }

    function test_setAllocations() public {
        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 10;
        allocations[1] = 20;

        uint256[] memory vaultAlloc = smartVaultManager.allocations(smartVault);
        assertEq(vaultAlloc.length, 0);

        smartVaultManager.setAllocations(smartVault, allocations);

        vaultAlloc = smartVaultManager.allocations(smartVault);
        assertEq(vaultAlloc.length, 2);
        assertEq(vaultAlloc[0], 10);
    }

    function test_setRiskProvider() public {
        address riskProvider_ = smartVaultManager.riskProvider(smartVault);
        assertEq(riskProvider_, address(0));

        riskManager.registerRiskProvider(riskProvider, true);
        smartVaultManager.setRiskProvider(smartVault, riskProvider);

        riskProvider_ = smartVaultManager.riskProvider(smartVault);
        assertEq(riskProvider_, riskProvider);
    }

    function test_setStrategies() public {
        address[] memory strategies = new address[](2);
        strategies[0] = address(10);
        strategies[1] = address(11);

        address smartVault = address(20);
        smartVaultManager.registerSmartVault(smartVault);

        vm.expectRevert(abi.encodeWithSelector(InvalidSmartVault.selector, address(0)));
        smartVaultManager.setStrategies(address(0), strategies);

        vm.expectRevert(abi.encodeWithSelector(EmptyStrategyArray.selector));
        smartVaultManager.setStrategies(smartVault, new address[](0));

        vm.expectRevert(abi.encodeWithSelector(InvalidStrategy.selector, address(10)));
        smartVaultManager.setStrategies(smartVault, strategies);

        address[] memory vaultStrategies = smartVaultManager.strategies(smartVault);
        assertEq(vaultStrategies.length, 0);

        strategyRegistry.registerStrategy(address(10));
        strategyRegistry.registerStrategy(address(11));
        smartVaultManager.setStrategies(smartVault, strategies);

        vaultStrategies = smartVaultManager.strategies(smartVault);
        assertEq(vaultStrategies.length, 2);
        assertEq(vaultStrategies[0], address(10));
    }
}
