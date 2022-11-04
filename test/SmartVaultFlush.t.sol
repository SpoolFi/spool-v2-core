// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/managers/SmartVaultManager.sol";
import "../src/interfaces/IRiskManager.sol";
import "../src/managers/RiskManager.sol";
import "../src/managers/StrategyRegistry.sol";
import "../src/SmartVault.sol";
import "./mocks/MockToken.sol";
import "../src/managers/GuardManager.sol";
import "../src/managers/ActionManager.sol";
import "../src/interfaces/IGuardManager.sol";
import "../src/interfaces/RequestType.sol";
import "../src/managers/UsdPriceFeedManager.sol";
import "./mocks/MockStrategy.sol";
import "./mocks/MockPriceFeedManager.sol";
import "../src/interfaces/ISmartVaultManager.sol";
import "./mocks/MockSwapper.sol";
import "../src/interfaces/ISmartVaultManager.sol";
import "../src/MasterWallet.sol";

contract SmartVaultFlushTest is Test {
    IStrategyRegistry strategyRegistry;
    MockPriceFeedManager priceFeedManager;
    ISmartVaultDeposits depositManager;
    MockToken token1;
    MockToken token2;
    IMasterWallet masterWallet;

    function setUp() public {
        masterWallet = new MasterWallet();
        strategyRegistry = new StrategyRegistry(masterWallet);
        strategyRegistry.initialize();

        priceFeedManager = new MockPriceFeedManager();
        depositManager = new SmartVaultDeposits(masterWallet);
        token1 = new MockToken("Token1", "T1");
        token2 = new MockToken("Token2", "T2");
    }

    function test_getDepositRatio() public {
        (address[] memory strategies, address[] memory assetGroup, uint256[][] memory ratios) = _createStrategies();
        _initializePriceFeeds();

        uint256[] memory allocations = new uint256[](3);
        allocations[0] = 600; // A
        allocations[1] = 300; // B
        allocations[2] = 100; // C

        uint256[] memory exchangeRates = new uint256[](2);
        exchangeRates[0] = priceFeedManager.assetToUsd(address(token1), 10 ** token1.decimals());
        exchangeRates[1] = priceFeedManager.assetToUsd(address(token2), 10 ** token2.decimals());

        DepositRatioQueryBag memory bag = DepositRatioQueryBag(
            address(0), assetGroup, strategies, allocations, exchangeRates, ratios, priceFeedManager.usdDecimals()
        );

        uint256[] memory ratio = depositManager.getDepositRatio(bag);

        assertEq(ratio.length, 2);
        assertEq(ratio[0] / ratio[0], 1);
        assertEq(ratio[1], 677973452615237513354);
    }

    function test_distributeVaultDeposits_exactDeposit() public {
        (address[] memory strategies, address[] memory assetGroup, uint256[][] memory ratios) = _createStrategies();
        _initializePriceFeeds();

        uint256[] memory allocations = new uint256[](3);
        allocations[0] = 600; // A
        allocations[1] = 300; // B
        allocations[2] = 100; // C

        uint256[] memory exchangeRates = new uint256[](2);
        exchangeRates[0] = priceFeedManager.assetToUsd(address(token1), 10 ** token1.decimals());
        exchangeRates[1] = priceFeedManager.assetToUsd(address(token2), 10 ** token2.decimals());

        uint256[] memory depositsIn = new uint256[](2);
        depositsIn[0] = 100 ether;
        depositsIn[1] = 6.779734526152375133 ether;

        SwapInfo[] memory swapInfo = new SwapInfo[](0);
        DepositRatioQueryBag memory bag = DepositRatioQueryBag(
            address(0), assetGroup, strategies, allocations, exchangeRates, ratios, priceFeedManager.usdDecimals()
        );

        uint256[][] memory distribution = depositManager.distributeVaultDeposits(bag, depositsIn, swapInfo);
        assertEq(distribution.length, 3);
        assertEq(distribution[0].length, 2);

        uint256 r = 10 ** 5;
        uint256[] memory deposits1 = distribution[0];
        assertEq(deposits1.length, 2);
        assertEq(deposits1[0] / r * r, 59.9104248817164 ether);
        assertEq(deposits1[1] / r * r, 4.0739088919567 ether);

        uint256[] memory deposits2 = distribution[1];
        assertEq(deposits2.length, 2);
        assertEq(deposits2[0] / r * r, 30.1775244829541 ether);
        assertEq(deposits2[1] / r * r, 2.0218941403579 ether);

        uint256[] memory deposits3 = distribution[2];
        assertEq(deposits3.length, 2);
        assertEq(deposits3[0] / r * r, 9.9120506353293 ether);
        assertEq(deposits3[1] / r * r, 0.6839314938377 ether);

        assertEq(deposits1[0] + deposits2[0] + deposits3[0], 100 ether);
        assertEq(deposits1[1] + deposits2[1] + deposits3[1], depositsIn[1]);
    }

    function test_distributeVaultDeposits_incorrectRatio() public {
        (address[] memory strategies, address[] memory assetGroup, uint256[][] memory ratios) = _createStrategies();
        _initializePriceFeeds();

        uint256[] memory allocations = new uint256[](3);
        allocations[0] = 600; // A
        allocations[1] = 300; // B
        allocations[2] = 100; // C

        uint256[] memory exchangeRates = new uint256[](2);
        exchangeRates[0] = priceFeedManager.assetToUsd(address(token1), 10 ** token1.decimals());
        exchangeRates[1] = priceFeedManager.assetToUsd(address(token2), 10 ** token2.decimals());

        uint256[] memory depositsIn = new uint256[](2);
        depositsIn[0] = 100 ether;
        depositsIn[1] = 7.779734526152375133 ether;

        SwapInfo[] memory swapInfo = new SwapInfo[](0);
        DepositRatioQueryBag memory bag = DepositRatioQueryBag(
            address(0), assetGroup, strategies, allocations, exchangeRates, ratios, priceFeedManager.usdDecimals()
        );

        vm.expectRevert(abi.encodeWithSelector(IncorrectDepositRatio.selector));
        depositManager.distributeVaultDeposits(bag, depositsIn, swapInfo);
    }

    function test_distributeVaultDeposits_withSwap() public {
        (address[] memory strategies, address[] memory assetGroup, uint256[][] memory ratios) = _createStrategies();
        _initializePriceFeeds();

        uint256[] memory allocations = new uint256[](3);
        allocations[0] = 600; // A
        allocations[1] = 300; // B
        allocations[2] = 100; // C

        uint256[] memory exchangeRates = new uint256[](2);
        exchangeRates[0] = priceFeedManager.assetToUsd(address(token1), 10 ** token1.decimals());
        exchangeRates[1] = priceFeedManager.assetToUsd(address(token2), 10 ** token2.decimals());

        uint256 swapFor = exchangeRates[0] * 10 ** token1.decimals() / exchangeRates[1];
        uint256[] memory depositsIn = new uint256[](2);
        depositsIn[0] = 100 ether + 1 ether;
        depositsIn[1] = 6.779734526152375133 ether - swapFor;

        token1.mint(address(masterWallet), depositsIn[0]);
        token2.mint(address(masterWallet), depositsIn[1]);

        MockSwapper swapper = _createSwapper();
        masterWallet.setWalletManager(address(depositManager), true);
        SwapInfo[] memory swapInfo = new SwapInfo[](1);
        swapInfo[0] = SwapInfo(
            address(swapper),
            address(token1),
            1000 ether,
            abi.encodeWithSelector(swapper.swap.selector, address(token1), 1 ether, address(masterWallet))
        );

        DepositRatioQueryBag memory bag = DepositRatioQueryBag(
            address(0), assetGroup, strategies, allocations, exchangeRates, ratios, priceFeedManager.usdDecimals()
        );

        uint256[][] memory distribution = depositManager.distributeVaultDeposits(bag, depositsIn, swapInfo);

        uint256 r = 10 ** 5;

        assertEq(distribution[0].length, 2);
        assertEq(distribution[0][0] / r * r, 59.9104248817164 ether);
        assertEq(distribution[0][1] / r * r, 4.0739088919567 ether);

        assertEq(distribution[1].length, 2);
        assertEq(distribution[1][0] / r * r, 30.1775244829541 ether);
        assertEq(distribution[1][1] / r * r, 2.0218941403579 ether);

        assertEq(distribution[2].length, 2);
        assertEq(distribution[2][0] / r * r, 9.9120506353293 ether);
        assertEq(distribution[2][1] / r * r, 0.6839314938377 ether);

        assertEq(distribution[0][0] + distribution[1][0] + distribution[2][0], 100 ether);
        assertEq(distribution[0][1] + distribution[1][1] + distribution[2][1], depositsIn[1] + swapFor);
    }

    function _createSwapper() private returns (MockSwapper) {
        MockSwapper swap = new MockSwapper(token1, token2, priceFeedManager);
        token1.mint(address(swap), 10000 ether);
        token2.mint(address(swap), 10000 ether);
        return swap;
    }

    function _createStrategies() private returns (address[] memory, address[] memory, uint256[][] memory) {
        MockStrategy strategy1 = new MockStrategy("A", strategyRegistry);
        MockStrategy strategy2 = new MockStrategy("B", strategyRegistry);
        MockStrategy strategy3 = new MockStrategy("C", strategyRegistry);

        address[] memory assetGroup = new address[](2);
        assetGroup[0] = address(token1);
        assetGroup[1] = address(token2);

        uint256[][] memory ratios = new uint256[][](3);
        ratios[0] = new uint256[](2);
        ratios[0][0] = 1000;
        ratios[0][1] = 68;
        strategy1.initialize(assetGroup, ratios[0]);

        ratios[1] = new uint256[](2);
        ratios[1][0] = 1000;
        ratios[1][1] = 67;
        strategy2.initialize(assetGroup, ratios[1]);

        ratios[2] = new uint256[](2);
        ratios[2][0] = 1000;
        ratios[2][1] = 69;
        strategy3.initialize(assetGroup, ratios[2]);

        address[] memory strategies = new address[](3);
        strategies[0] = address(strategy1);
        strategies[1] = address(strategy2);
        strategies[2] = address(strategy3);

        strategyRegistry.registerStrategy(address(strategy1));
        strategyRegistry.registerStrategy(address(strategy2));
        strategyRegistry.registerStrategy(address(strategy3));

        return (strategies, assetGroup, ratios);
    }

    function _initializePriceFeeds() private {
        priceFeedManager.setExchangeRate(address(token1), 1336.61 * 10 ** 26);
        priceFeedManager.setExchangeRate(address(token2), 19730.31 * 10 ** 26);
    }
}
