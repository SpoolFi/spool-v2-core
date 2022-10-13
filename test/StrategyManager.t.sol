// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/interfaces/IStrategyRegistry.sol";
import "../src/managers/StrategyRegistry.sol";

contract StrategyRegistryTest is Test {
    IStrategyRegistry strategyRegistry;

    function setUp() public {
        strategyRegistry = new StrategyRegistry();
    }

    function test_registerStrategy() public {
        address strategy = address(1);
        assertFalse(strategyRegistry.isStrategy(strategy));

        strategyRegistry.registerStrategy(strategy);
        assertTrue(strategyRegistry.isStrategy(strategy));

        vm.expectRevert("StrategyRegistry::registerStrategy: Strategy already registered.");
        strategyRegistry.registerStrategy(strategy);
    }

    function test_removeStrategy() public {
        address strategy = address(1);

        vm.expectRevert("StrategyRegistry::registerStrategy: Strategy not registered.");
        strategyRegistry.removeStrategy(strategy);

        strategyRegistry.registerStrategy(strategy);
        assertTrue(strategyRegistry.isStrategy(strategy));

        strategyRegistry.removeStrategy(strategy);
        assertFalse(strategyRegistry.isStrategy(strategy));
    }
}
