// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/managers/SmartVaultManager.sol";
import "../src/interfaces/IRiskManager.sol";
import "../src/managers/RiskManager.sol";
import "../src/managers/StrategyRegistry.sol";
import "../src/SmartVault.sol";
import "../src/mocks/MockToken.sol";
import "../src/managers/GuardManager.sol";
import "../src/managers/ActionManager.sol";
import "../src/interfaces/IGuardManager.sol";
import "../src/interfaces/RequestType.sol";

contract SmartVaultManagerTest is Test {
    ISmartVaultManager smartVaultManager;
    IStrategyRegistry strategyRegistry;
    IRiskManager riskManager;
    address riskProvider = address(10);
    address smartVault = address(100);
    MockToken token1;
    MockToken token2;

    function setUp() public {
        strategyRegistry = new StrategyRegistry();
        riskManager = new RiskManager();
        smartVaultManager = new SmartVaultManager(strategyRegistry, riskManager);
        smartVaultManager.registerSmartVault(smartVault);

        token1 = new MockToken("Token1", "T1");
        token2 = new MockToken("Token2", "T2");
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

    function createVault() public returns (ISmartVault) {
        IGuardManager guardManager = new GuardManager();
        IActionManager actionManager = new ActionManager();

        address strategy1 = address(10001);
        address strategy2 = address(10002);

        address[] memory strategies = new address[](2);
        strategies[0] = strategy1;
        strategies[1] = strategy2;

        strategyRegistry.registerStrategy(strategy1);
        strategyRegistry.registerStrategy(strategy2);

        address[] memory assetGroup = new address[](2);
        assetGroup[0] = address(token1);
        assetGroup[1] = address(token2);

        ISmartVault smartVault_ = new SmartVault(
            "TestVault",
            assetGroup,
            guardManager,
            actionManager,
            strategyRegistry,
            smartVaultManager
        );

        guardManager.setGuards(address(smartVault_), new GuardDefinition[](0));
        actionManager.setActions(address(smartVault_), new IAction[](0), new RequestType[](0));

        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 25;
        allocations[1] = 75;

        smartVaultManager.registerSmartVault(address(smartVault_));
        smartVaultManager.setStrategies(address(smartVault_), strategies);
        smartVaultManager.setAllocations(address(smartVault_), allocations);
        return smartVault_;
    }

    function test_addDepositsAndFlush() public {
        ISmartVault smartVault_ = createVault();

        address user = address(123);
        token1.mint(user, 200 ether);
        token2.mint(user, 200 ether);

        uint256[] memory assets = new uint256[](2);
        assets[0] = 10 ether;
        assets[1] = 15 ether;

        vm.prank(user);
        token1.approve(address(smartVault_), 100 ether);

        vm.prank(user);
        token2.approve(address(smartVault_), 100 ether);

        vm.prank(user);
        smartVault_.deposit(assets, user);

        uint256 flushIdx = smartVaultManager.getLatestFlushIndex(address(smartVault_));
        assertEq(flushIdx, 0);

        uint256[] memory deposits = smartVaultManager.smartVaultDeposits(address(smartVault_), flushIdx);
        assertEq(deposits.length, 2);
        assertEq(deposits[0], 10 ether);
        assertEq(deposits[1], 15 ether);

        smartVaultManager.flushSmartVault(address(smartVault_));

        flushIdx = smartVaultManager.getLatestFlushIndex(address(smartVault_));
        assertEq(flushIdx, 1);

        address strategy1 = address(10001);
        address strategy2 = address(10002);

        uint256 dhwIndex = strategyRegistry.currentIndex(strategy1);
        deposits = strategyRegistry.strategyDeposits(strategy1, dhwIndex);

        assertEq(deposits.length, 2);
        assertEq(deposits[0], 10 * 0.25 ether);
        assertEq(deposits[1], 15 * 0.25 ether);

        deposits = strategyRegistry.strategyDeposits(strategy2, dhwIndex);

        assertEq(deposits.length, 2);
        assertEq(deposits[0], 10 * 0.75 ether);
        assertEq(deposits[1], 15 * 0.75 ether);
    }
}
