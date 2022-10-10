// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/interfaces/IStrategyManager.sol";
import "../src/managers/StrategyManager.sol";

contract StrategyManagerTest is Test {
    IStrategyManager strategyManager;

    function setUp() public {
        strategyManager = new StrategyManager();
    }

    function test_registerStrategy() public {
        address strategy = address(1);
        assertFalse(strategyManager.isStrategy(strategy));

        strategyManager.registerStrategy(strategy);
        assertTrue(strategyManager.isStrategy(strategy));

        vm.expectRevert("StrategyManager::registerStrategy: Strategy already registered.");
        strategyManager.registerStrategy(strategy);
    }

    function test_removeStrategy() public {
        address strategy = address(1);

        vm.expectRevert("StrategyManager::registerStrategy: Strategy not registered.");
        strategyManager.removeStrategy(strategy);

        strategyManager.registerStrategy(strategy);
        assertTrue(strategyManager.isStrategy(strategy));

        strategyManager.removeStrategy(strategy);
        assertFalse(strategyManager.isStrategy(strategy));
    }

    function test_setStrategies() public {
        address[] memory strategies = new address[](2);
        strategies[0] = address(10);
        strategies[1] = address(11);

        address smartVault = address(20);

        vm.expectRevert("StrategyManager::setStrategies: Smart vault 0");
        strategyManager.setStrategies(address(0), strategies);

        vm.expectRevert("StrategyManager::setStrategies: Strategy array empty");
        strategyManager.setStrategies(smartVault, new address[](0));

        vm.expectRevert("StrategyManager::registerStrategy: Strategy not registered.");
        strategyManager.setStrategies(smartVault, strategies);

        address[] memory vaultStrategies = strategyManager.strategies(smartVault);
        assertEq(vaultStrategies.length, 0);

        strategyManager.registerStrategy(address(10));
        strategyManager.registerStrategy(address(11));
        strategyManager.setStrategies(smartVault, strategies);

        vaultStrategies = strategyManager.strategies(smartVault);
        assertEq(vaultStrategies.length, 2);
        assertEq(vaultStrategies[0], address(10));
    }
}
