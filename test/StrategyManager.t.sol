// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/interfaces/IStrategyRegistry.sol";
import "../src/managers/StrategyRegistry.sol";
import "../src/MasterWallet.sol";
import "./libraries/Arrays.sol";
import "../src/Swapper.sol";
import "./mocks/MockPriceFeedManager.sol";

contract StrategyRegistryTest is Test {
    IStrategyRegistry strategyRegistry;

    function setUp() public {
        SpoolAccessControl accessControl = new SpoolAccessControl();
        accessControl.initialize();
        strategyRegistry =
            new StrategyRegistry(new MasterWallet(accessControl), accessControl, new MockPriceFeedManager());
    }

    function test_registerStrategy() public {
        address strategy = address(new MockStrategy());
        assertFalse(strategyRegistry.isStrategy(strategy));

        strategyRegistry.registerStrategy(strategy);
        assertTrue(strategyRegistry.isStrategy(strategy));

        vm.expectRevert(abi.encodeWithSelector(StrategyAlreadyRegistered.selector, strategy));
        strategyRegistry.registerStrategy(strategy);
    }

    function test_removeStrategy() public {
        address strategy = address(new MockStrategy());

        vm.expectRevert(abi.encodeWithSelector(InvalidStrategy.selector, strategy));
        strategyRegistry.removeStrategy(strategy);

        strategyRegistry.registerStrategy(strategy);
        assertTrue(strategyRegistry.isStrategy(strategy));

        strategyRegistry.removeStrategy(strategy);
        assertFalse(strategyRegistry.isStrategy(strategy));
    }
}

contract MockStrategy {
    function test_mock() external pure {}

    function assetRatio() external pure returns (uint256[] memory) {
        return Arrays.toArray(1, 2);
    }
}
