// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../src/SpoolLens.sol";
import "../src/providers/LinearAllocationProvider.sol";
import "../src/interfaces/IStrategyRegistry.sol";
import "../src/interfaces/IStrategy.sol";
import "../src/interfaces/ISpoolAccessControl.sol";
import "../src/interfaces/IRiskManager.sol";
import "./fixtures/TestFixture.sol";

contract SpoolLensTest is TestFixture {
    function setUp() public {
        setUpBase();

        vm.mockCall(
            address(accessControl),
            abi.encodeWithSelector(accessControl.hasRole.selector, ROLE_STRATEGY_REGISTRY, strategyRegistry),
            abi.encode(true)
        );
    }

    function test_getSmartVaultAllocations() public {
        address[] memory strategies = new address[](2);
        strategies[0] = address(100);
        strategies[1] = address(101);

        for (uint8 i; i < strategies.length; ++i) {
            vm.mockCall(
                address(accessControl),
                abi.encodeCall(accessControl.hasRole, (ROLE_STRATEGY, strategies[i])),
                abi.encode(true)
            );
        }

        for (uint256 i; i < strategies.length; ++i) {
            vm.mockCall(
                address(IStrategy(strategies[i])),
                abi.encodeWithSelector(IStrategy.assetGroupId.selector),
                abi.encode(1)
            );
        }

        // address riskProvider = address(200);

        uint8[] memory riskScores = new uint8[](strategies.length);
        riskScores[0] = 10;
        riskScores[1] = 20;

        vm.mockCall(
            address(riskManager),
            abi.encodeCall(IRiskManager.getRiskScores, (address(riskProvider), strategies)),
            abi.encode(riskScores)
        );

        int256[] memory apyList = new int256[](strategies.length);
        apyList[0] = YIELD_FULL_PERCENT_INT / 50;
        apyList[1] = YIELD_FULL_PERCENT_INT / 100;

        vm.mockCall(
            address(strategyRegistry), abi.encodeCall(IStrategyRegistry.strategyAPYs, (strategies)), abi.encode(apyList)
        );

        uint256[] memory allocations = new uint256[](strategies.length);
        allocations[0] = 4000;
        allocations[1] = 6000;
        vm.mockCall(
            address(allocationProvider),
            abi.encodeWithSelector(LinearAllocationProvider.calculateAllocation.selector),
            abi.encode(allocations)
        );

        vm.mockCall(
            address(accessControl),
            abi.encodeCall(accessControl.hasRole, (ROLE_ALLOCATION_PROVIDER, address(allocationProvider))),
            abi.encode(true)
        );

        vm.mockCall(
            address(accessControl),
            abi.encodeCall(accessControl.hasRole, (ROLE_RISK_PROVIDER, address(riskProvider))),
            abi.encode(true)
        );

        uint256[][] memory allocationsList =
            spoolLens.getSmartVaultAllocations(strategies, riskProvider, address(allocationProvider));

        assertEq(allocationsList.length, 21, "Length mismatch");

        for (uint256 i; i < allocationsList.length; ++i) {
            assertEq(allocationsList[i].length, 2, "Subarray length mismatch");
            assertEq(allocationsList[i][0], uint256(4000), "Element mismatch");
            assertEq(allocationsList[i][1], uint256(6000), "Element mismatch");
        }
    }
}
