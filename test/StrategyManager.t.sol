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
import "../src/strategies/GhostStrategy.sol";
import "../src/access/SpoolAccessControl.sol";

contract StrategyRegistryTest is Test {
    StrategyRegistry strategyRegistry;
    SpoolAccessControl accessControl;

    function setUp() public {
        accessControl = new SpoolAccessControl();
        accessControl.initialize();
        strategyRegistry =
        new StrategyRegistry(new MasterWallet(accessControl), accessControl, new MockPriceFeedManager(), address(new GhostStrategy()));

        accessControl.grantRole(ADMIN_ROLE_STRATEGY, address(strategyRegistry));
    }

    function test_registerStrategy() public {
        address strategy = address(new MockStrategy());
        assertFalse(accessControl.hasRole(ROLE_STRATEGY, strategy));

        strategyRegistry.registerStrategy(strategy);
        assertTrue(accessControl.hasRole(ROLE_STRATEGY, strategy));

        vm.expectRevert(abi.encodeWithSelector(StrategyAlreadyRegistered.selector, strategy));
        strategyRegistry.registerStrategy(strategy);
    }

    function test_removeStrategy_revertNotVaultManager() public {
        address strategy = address(new MockStrategy());

        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SMART_VAULT_MANAGER, address(this)));
        strategyRegistry.removeStrategy(strategy);
    }

    function test_removeStrategy_revertInvalidStrategy() public {
        address strategy = address(new MockStrategy());
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(this));

        vm.expectRevert(abi.encodeWithSelector(InvalidStrategy.selector, strategy));
        strategyRegistry.removeStrategy(strategy);
    }

    function test_removeStrategy_success() public {
        address strategy = address(new MockStrategy());
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(this));

        strategyRegistry.registerStrategy(strategy);
        assertTrue(accessControl.hasRole(ROLE_STRATEGY, strategy));

        strategyRegistry.removeStrategy(strategy);
        assertFalse(accessControl.hasRole(ROLE_STRATEGY, strategy));
    }

    function test_setEmergencyWithdrawalWallet_revertMissingRole() public {
        vm.prank(address(0xa));
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SPOOL_ADMIN, address(0xa)));
        strategyRegistry.setEmergencyWithdrawalWallet(address(0xb));
    }

    function test_setEmergencyWithdrawalWallet_revertAddressZero() public {
        accessControl.grantRole(ROLE_SPOOL_ADMIN, address(0xa));
        vm.prank(address(0xa));
        vm.expectRevert(abi.encodeWithSelector(AddressZero.selector));
        strategyRegistry.setEmergencyWithdrawalWallet(address(0));
    }

    function test_setEmergencyWithdrawalWallet_ok() public {
        accessControl.grantRole(ROLE_SPOOL_ADMIN, address(0xa));
        vm.prank(address(0xa));
        strategyRegistry.setEmergencyWithdrawalWallet(address(0xb));

        assertEq(strategyRegistry.emergencyWithdrawalWallet(), address(0xb));
    }
}

contract MockStrategy {
    function test_mock() external pure {}

    function assetRatio() external pure returns (uint256[] memory) {
        return Arrays.toArray(1, 2);
    }
}
