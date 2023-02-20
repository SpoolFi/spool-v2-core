// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../src/strategies/Strategy.sol";
import "./mocks/MockStrategy.sol";

contract StrategyHarness is MockStrategy {
    constructor(
        string memory name_,
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_
    ) MockStrategy(name_, assetGroupRegistry_, accessControl_, swapper_) {}

    function exposed_calculateYieldPercentage(uint256 previousValue, uint256 currentValue)
        external
        pure
        returns (int256)
    {
        return _calculateYieldPercentage(previousValue, currentValue);
    }
}

contract StrategyTest is Test {
    function test_calculateYieldPercentage() public {
        StrategyHarness strategy = new StrategyHarness(
            "Strat",
            IAssetGroupRegistry(address(0x001)),
            ISpoolAccessControl(address(0x002)),
            ISwapper(address(0x003))
        );
        strategy.initialize(0, new uint256[](0));

        assertEq(strategy.exposed_calculateYieldPercentage(100, 120), YIELD_FULL_PERCENT_INT * 20 / 100);
        assertEq(strategy.exposed_calculateYieldPercentage(100, 80), YIELD_FULL_PERCENT_INT * (-20) / 100);
        assertEq(strategy.exposed_calculateYieldPercentage(100, 100), 0);
    }
}
