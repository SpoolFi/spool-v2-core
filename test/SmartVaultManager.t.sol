// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/interfaces/RequestType.sol";
import "../src/managers/ActionManager.sol";
import "../src/managers/AssetGroupRegistry.sol";
import "../src/managers/GuardManager.sol";
import "../src/managers/RiskManager.sol";
import "../src/managers/SmartVaultManager.sol";
import "../src/managers/StrategyRegistry.sol";
import "../src/managers/UsdPriceFeedManager.sol";
import "../src/MasterWallet.sol";
import "../src/SmartVault.sol";
import "./mocks/MockPriceFeedManager.sol";
import "./mocks/MockStrategy.sol";
import "./mocks/MockSwapper.sol";
import "./mocks/MockToken.sol";

contract SmartVaultManagerTest is Test, SpoolAccessRoles {
    ISmartVaultManager smartVaultManager;
    ISpoolAccessControl accessControl;
    IStrategyRegistry strategyRegistry;
    MockPriceFeedManager priceFeedManager;
    IAssetGroupRegistry assetGroupRegistry;

    address riskProvider = address(10);
    address smartVault = address(100);

    IMasterWallet masterWallet;
    MockToken token1;
    MockToken token2;

    function setUp() public {
        accessControl = new SpoolAccessControl();
        masterWallet = new MasterWallet(accessControl);
        assetGroupRegistry = new AssetGroupRegistry();
        strategyRegistry = new StrategyRegistry(masterWallet, accessControl);
        priceFeedManager = new MockPriceFeedManager();
        ISmartVaultDeposits depositManager = new SmartVaultDeposits(masterWallet);
        IGuardManager guardManager = new GuardManager();
        IActionManager actionManager = new ActionManager();

        smartVaultManager = new SmartVaultManager(
            accessControl,
            strategyRegistry,
            depositManager,
            priceFeedManager,
            assetGroupRegistry,
            masterWallet,
            actionManager,
            guardManager
        );
        accessControl.grantRole(ROLE_SMART_VAULT, smartVault);
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(smartVaultManager));

        token1 = new MockToken("Token1", "T1");
        token2 = new MockToken("Token2", "T2");
    }

    function test_setAllocations() public {
        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 10;
        allocations[1] = 20;

        address[] memory strategies = new address[](2);
        strategies[0] = address(10);
        strategies[1] = address(11);

        uint256[] memory vaultAlloc = smartVaultManager.allocations(smartVault);
        assertEq(vaultAlloc.length, 0);

        strategyRegistry.registerStrategy(address(10));
        strategyRegistry.registerStrategy(address(11));
        smartVaultManager.setStrategies(smartVault, strategies);
        smartVaultManager.setAllocations(smartVault, allocations);

        vaultAlloc = smartVaultManager.allocations(smartVault);
        assertEq(vaultAlloc.length, 2);
        assertEq(vaultAlloc[0], 10);
    }

    function test_setRiskProvider() public {
        address riskProvider_ = smartVaultManager.riskProvider(smartVault);
        assertEq(riskProvider_, address(0));

        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
        smartVaultManager.setRiskProvider(smartVault, riskProvider);

        riskProvider_ = smartVaultManager.riskProvider(smartVault);
        assertEq(riskProvider_, riskProvider);
    }

    function test_setStrategies() public {
        address[] memory strategies = new address[](2);
        strategies[0] = address(10);
        strategies[1] = address(11);

        address smartVault_ = address(20);
        accessControl.grantRole(ROLE_SMART_VAULT, smartVault_);

        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SMART_VAULT, address(0)));
        smartVaultManager.setStrategies(address(0), strategies);

        vm.expectRevert(abi.encodeWithSelector(EmptyStrategyArray.selector));
        smartVaultManager.setStrategies(smartVault_, new address[](0));

        vm.expectRevert(abi.encodeWithSelector(InvalidStrategy.selector, address(10)));
        smartVaultManager.setStrategies(smartVault_, strategies);

        address[] memory vaultStrategies = smartVaultManager.strategies(smartVault_);
        assertEq(vaultStrategies.length, 0);

        strategyRegistry.registerStrategy(address(10));
        strategyRegistry.registerStrategy(address(11));
        smartVaultManager.setStrategies(smartVault_, strategies);

        vaultStrategies = smartVaultManager.strategies(smartVault_);
        assertEq(vaultStrategies.length, 2);
        assertEq(vaultStrategies[0], address(10));
    }

    function test_getDepositRatio() public {
        (address[] memory strategies, uint256 assetGroupId) = _createStrategies();
        ISmartVault smartVault_ = _createVault(strategies, assetGroupId);
        _initializePriceFeeds();

        uint256[] memory ratio = smartVaultManager.getDepositRatio(address(smartVault_));

        assertEq(ratio[0] / ratio[0], 1);
        assertEq(ratio[1], 677973452615237513354);
    }

    function test_addDepositsAndFlush() public {
        (address[] memory strategies, uint256 assetGroupId) = _createStrategies();
        ISmartVault smartVault_ = _createVault(strategies, assetGroupId);
        _initializePriceFeeds();

        address user = address(123);
        token1.mint(user, 200 ether);
        token2.mint(user, 200 ether);

        uint256[] memory assets = new uint256[](2);
        assets[0] = 100 ether;
        assets[1] = 6.779734526152375133 ether;

        vm.prank(user);
        token1.approve(address(smartVaultManager), 100 ether);

        vm.prank(user);
        token2.approve(address(smartVaultManager), 100 ether);

        vm.prank(user);
        smartVaultManager.deposit(address(smartVault_), assets, user);

        uint256 flushIdx = smartVaultManager.getLatestFlushIndex(address(smartVault_));
        assertEq(flushIdx, 0);

        uint256[] memory deposits = smartVaultManager.smartVaultDeposits(address(smartVault_), flushIdx);
        assertEq(deposits.length, 2);
        assertEq(deposits[0], 100 ether);
        assertEq(deposits[1], 6.779734526152375133 ether);

        SwapInfo[] memory swapInfo = new SwapInfo[](0);
        smartVaultManager.flushSmartVault(address(smartVault_), swapInfo);

        flushIdx = smartVaultManager.getLatestFlushIndex(address(smartVault_));
        assertEq(flushIdx, 1);

        uint256 dhwIndex = strategyRegistry.currentIndex(strategies[0]);
        uint256 r = 10 ** 5;

        uint256[] memory deposits1 = strategyRegistry.strategyDeposits(strategies[0], dhwIndex);
        assertEq(deposits1.length, 2);
        assertEq(deposits1[0] / r * r, 59.9104248817164 ether);
        assertEq(deposits1[1] / r * r, 4.0739088919567 ether);

        uint256[] memory deposits2 = strategyRegistry.strategyDeposits(strategies[1], dhwIndex);
        assertEq(deposits2.length, 2);
        assertEq(deposits2[0] / r * r, 30.1775244829541 ether);
        assertEq(deposits2[1] / r * r, 2.0218941403579 ether);

        uint256[] memory deposits3 = strategyRegistry.strategyDeposits(strategies[2], dhwIndex);
        assertEq(deposits3.length, 2);
        assertEq(deposits3[0] / r * r, 9.9120506353293 ether);
        assertEq(deposits3[1] / r * r, 0.6839314938377 ether);

        assertEq(deposits1[0] + deposits2[0] + deposits3[0], 100 ether);
        assertEq(deposits1[1] + deposits2[1] + deposits3[1], deposits[1]);
    }

    function _createStrategies() private returns (address[] memory, uint256) {
        MockStrategy strategy1 = new MockStrategy("A", strategyRegistry, assetGroupRegistry);
        MockStrategy strategy2 = new MockStrategy("B", strategyRegistry, assetGroupRegistry);
        MockStrategy strategy3 = new MockStrategy("C", strategyRegistry, assetGroupRegistry);

        address[] memory assetGroup = new address[](2);
        assetGroup[0] = address(token1);
        assetGroup[1] = address(token2);
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        uint256[] memory ratios = new uint256[](2);
        ratios[0] = 1000;

        ratios[1] = 68;
        strategy1.initialize(assetGroupId, ratios);

        ratios[1] = 67;
        strategy2.initialize(assetGroupId, ratios);

        ratios[1] = 69;
        strategy3.initialize(assetGroupId, ratios);

        address[] memory strategies = new address[](3);
        strategies[0] = address(strategy1);
        strategies[1] = address(strategy2);
        strategies[2] = address(strategy3);

        strategyRegistry.registerStrategy(address(strategy1));
        strategyRegistry.registerStrategy(address(strategy2));
        strategyRegistry.registerStrategy(address(strategy3));

        return (strategies, assetGroupId);
    }

    function _createVault(address[] memory strategies, uint256 assetGroupId) private returns (ISmartVault) {
        IGuardManager guardManager = new GuardManager();
        IActionManager actionManager = new ActionManager();
        SmartVault smartVault_ = new SmartVault(
            "TestVault",
            accessControl
        );

        smartVault_.initialize(assetGroupId);

        guardManager.setGuards(address(smartVault_), new GuardDefinition[](0));
        actionManager.setActions(address(smartVault_), new IAction[](0), new RequestType[](0));

        uint256[] memory allocations = new uint256[](3);
        allocations[0] = 600; // A
        allocations[1] = 300; // B
        allocations[2] = 100; // C

        accessControl.grantRole(ROLE_SMART_VAULT, address(smartVault_));
        smartVaultManager.setStrategies(address(smartVault_), strategies);
        smartVaultManager.setAllocations(address(smartVault_), allocations);

        return smartVault_;
    }

    function _initializePriceFeeds() private {
        priceFeedManager.setExchangeRate(address(token1), 1336.61 * 10 ** 26);
        priceFeedManager.setExchangeRate(address(token2), 19730.31 * 10 ** 26);
    }
}
