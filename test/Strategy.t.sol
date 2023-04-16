// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../src/access/SpoolAccessControl.sol";
import "../src/managers/AssetGroupRegistry.sol";
import "../src/strategies/Strategy.sol";
import "./libraries/Arrays.sol";
import "./mocks/MockToken.sol";
import "./mocks/MockStrategy.sol";

contract StrategyTest is Test {
    function test_calculateYieldPercentage() public {
        vm.mockCall(
            address(0x001), abi.encodeWithSelector(IAssetGroupRegistry.validateAssetGroup.selector), abi.encode(true)
        );
        StrategyHarness strategy = new StrategyHarness(
            IAssetGroupRegistry(address(0x001)),
            ISpoolAccessControl(address(0x002)),
            ISwapper(address(0x003)),
            1
        );
        strategy.initialize("Strat", new uint256[](0));

        assertEq(strategy.exposed_calculateYieldPercentage(100, 120), YIELD_FULL_PERCENT_INT * 20 / 100);
        assertEq(strategy.exposed_calculateYieldPercentage(100, 80), YIELD_FULL_PERCENT_INT * (-20) / 100);
        assertEq(strategy.exposed_calculateYieldPercentage(100, 100), 0);
    }

    function test_assetGroupIdInitialization() public {
        MockToken token = new MockToken("Token", "T");

        SpoolAccessControl accessControl = new SpoolAccessControl();
        accessControl.initialize();

        AssetGroupRegistry assetGroupRegistry = new AssetGroupRegistry(accessControl);
        assetGroupRegistry.initialize(Arrays.toArray(address(token)));

        address[] memory assetGroup = Arrays.toArray(address(token));
        uint256 assetGroupIdValid = assetGroupRegistry.registerAssetGroup(assetGroup);
        uint256 assetGroupIdInvalid = 5;

        // asset group ID not initialized - should revert
        StrategyHarness2 strategyA = new StrategyHarness2(
            assetGroupRegistry,
            accessControl,
            ISwapper(address(0x003)),
            NULL_ASSET_GROUP_ID
        );
        vm.expectRevert(InvalidAssetGroupIdInitialization.selector);
        strategyA.initializeAlt(NULL_ASSET_GROUP_ID);

        // asset group ID initialized twice - should revert
        StrategyHarness2 strategyB = new StrategyHarness2(
            assetGroupRegistry,
            accessControl,
            ISwapper(address(0x003)),
            assetGroupIdValid
        );
        vm.expectRevert(InvalidAssetGroupIdInitialization.selector);
        strategyB.initializeAlt(assetGroupIdValid);

        // asset group ID initialized in constructor - should work
        StrategyHarness2 strategyC = new StrategyHarness2(
            assetGroupRegistry,
            accessControl,
            ISwapper(address(0x003)),
            assetGroupIdValid
        );
        strategyC.initializeAlt(NULL_ASSET_GROUP_ID);

        // asset group ID initialized in initializer - should work
        StrategyHarness2 strategyD = new StrategyHarness2(
            assetGroupRegistry,
            accessControl,
            ISwapper(address(0x003)),
            NULL_ASSET_GROUP_ID
        );
        strategyD.initializeAlt(assetGroupIdValid);

        // asset group ID initialized in constructor with invalid ID - should revert
        StrategyHarness2 strategyE = new StrategyHarness2(
            assetGroupRegistry,
            accessControl,
            ISwapper(address(0x003)),
            assetGroupIdInvalid
        );
        vm.expectRevert(abi.encodeWithSelector(InvalidAssetGroup.selector, assetGroupIdInvalid));
        strategyE.initializeAlt(NULL_ASSET_GROUP_ID);

        // asset group ID initialized in initializer with invalid ID - should revert
        StrategyHarness2 strategyF = new StrategyHarness2(
            assetGroupRegistry,
            accessControl,
            ISwapper(address(0x003)),
            NULL_ASSET_GROUP_ID
        );
        vm.expectRevert(abi.encodeWithSelector(InvalidAssetGroup.selector, assetGroupIdInvalid));
        strategyF.initializeAlt(assetGroupIdInvalid);
    }
}

contract StrategyHarness is MockStrategy {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        uint256 assetGroupId_
    ) MockStrategy(assetGroupRegistry_, accessControl_, swapper_, assetGroupId_) {}

    function exposed_calculateYieldPercentage(uint256 previousValue, uint256 currentValue)
        external
        pure
        returns (int256)
    {
        return _calculateYieldPercentage(previousValue, currentValue);
    }
}

contract StrategyHarness2 is MockStrategy {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        uint256 assetGroupId_
    ) MockStrategy(assetGroupRegistry_, accessControl_, swapper_, assetGroupId_) {}

    function initializeAlt(uint256 assetGroupId_) external initializer {
        __Strategy_init("strat", assetGroupId_);
    }
}
