// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "./mocks/MockRiskManager.sol";
import "../src/interfaces/IAllocationProvider.sol";
import "../src/providers/AllocationProvider.sol";

contract FixedRM is MockRiskManager {
    function test_mock_() external pure {}

    function getRiskScores(address riskProvider, address[] memory strategy)
        external
        pure
        override
        returns (uint256[] memory)
    {
        uint256[] memory results = new uint256[](strategy.length);

        if (riskProvider == address(100)) {
            for (uint8 i = 0; i < strategy.length; i++) {
                address str = strategy[i];
                if (str == address(101)) {
                    results[0] = 342;
                }
                if (str == address(102)) {
                    results[1] = 112;
                }
                if (str == address(103)) {
                    results[2] = 400;
                }
            }
        } else {
            revert("FixedRM::getRiskScore");
        }
        return results;
    }
}

contract ActionManagerTest is Test {
    function test_allocationProvider() public {
        address strategy1 = address(101);
        address strategy2 = address(102);
        address strategy3 = address(103);

        uint16 apy_strategy1 = 124; // 1.24%
        uint16 apy_strategy2 = 220; // 2.20%
        uint16 apy_strategy3 = 400; // 4.0%

        address riskProvider = address(100);

        int8 riskTolerance = 0; // [0, 20]

        address[] memory strategies = new address[](3);
        strategies[0] = strategy1;
        strategies[1] = strategy2;
        strategies[2] = strategy3;

        uint16[] memory apys = new uint16[](3);
        apys[0] = apy_strategy1;
        apys[1] = apy_strategy2;
        apys[2] = apy_strategy3;

        AllocationCalculationInput memory input =
            AllocationCalculationInput(strategies, apys, riskProvider, riskTolerance);
        FixedRM rm = new FixedRM();

        AllocationProvider ap = new AllocationProvider(rm);

        uint256[] memory results = ap.calculateAllocationProvider(input);

        uint256 sum = 0;
        for (uint8 i = 0; i < results.length; i++) {
            sum += results[i];
            console.log(results[i]);
        }
    }
}
