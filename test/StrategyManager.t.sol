// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/interfaces/IStrategyRegistry.sol";
import "../src/managers/StrategyRegistry.sol";
import "../src/MasterWallet.sol";

contract StrategyRegistryTest is Test {
    IStrategyRegistry strategyRegistry;

    function setUp() public {
        ISpoolAccessControl accessControl = new SpoolAccessControl();
        strategyRegistry = new StrategyRegistry(new MasterWallet(accessControl), accessControl);
    }

    function test_registerStrategy() public {
        address strategy = address(1);
        assertFalse(strategyRegistry.isStrategy(strategy));

        strategyRegistry.registerStrategy(strategy);
        assertTrue(strategyRegistry.isStrategy(strategy));

        vm.expectRevert(abi.encodeWithSelector(StrategyAlreadyRegistered.selector, strategy));
        strategyRegistry.registerStrategy(strategy);
    }

    function test_removeStrategy() public {
        address strategy = address(1);

        vm.expectRevert(abi.encodeWithSelector(InvalidStrategy.selector, strategy));
        strategyRegistry.removeStrategy(strategy);

        strategyRegistry.registerStrategy(strategy);
        assertTrue(strategyRegistry.isStrategy(strategy));

        strategyRegistry.removeStrategy(strategy);
        assertFalse(strategyRegistry.isStrategy(strategy));
    }
}
