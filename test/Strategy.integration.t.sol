// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "./fixtures/IntegrationTestFixture.sol";
import "./libraries/Arrays.sol";
import "./mocks/MockExchange.sol";

contract StrategyIntegrationTest is TestFixture {
    event Deposited(
        uint256 mintedShares, uint256 usdWorthDeposited, uint256[] assetsBeforeSwap, uint256[] assetsDeposited
    );

    function setUp() public {
        super.setUpBase();
    }

    function test_depositFast_singleAsset() public {
        // arrange
        MockToken tokenA = new MockToken("TokenA", "TA");

        address[] memory assetGroup = Arrays.toArray(address(tokenA));
        uint256[] memory exchangeRates = Arrays.toArray(1 * USD_DECIMALS_MULTIPLIER);

        assetGroupRegistry.allowTokenBatch(assetGroup);
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        MockStrategy strategy = new MockStrategy(
            assetGroupRegistry,
            accessControl,
            swapper,
            assetGroupId
        );
        strategy.initialize("Strat", Arrays.toArray(1));
        strategyRegistry.registerStrategy(address(strategy), 0, ATOMIC_STRATEGY);

        // need to push some tokens to the strategy for deposit
        tokenA.mint(address(strategy), 1234 * 10 ** tokenA.decimals());

        uint256[] memory slippages = new uint256[](0);
        SwapInfo[] memory swapInfos = new SwapInfo[](0);

        // act
        uint256 expectedTotalMintedShares = 1234 * USD_DECIMALS_MULTIPLIER * INITIAL_SHARE_MULTIPLIER;
        uint256 expectedMinted = expectedTotalMintedShares - INITIAL_LOCKED_SHARES;
        uint256[] memory assetsBeforeSwap = Arrays.toArray(1234 * 10 ** tokenA.decimals());
        uint256[] memory assetsDeposited = Arrays.toArray(1234 * 10 ** tokenA.decimals());

        vm.expectEmit(true, true, true, true);
        emit Deposited(expectedMinted, 1234 * USD_DECIMALS_MULTIPLIER, assetsBeforeSwap, assetsDeposited);

        vm.startPrank(address(smartVaultManager));
        uint256 minted = strategy.depositFast(assetGroup, exchangeRates, priceFeedManager, slippages, swapInfos);
        vm.stopPrank();

        // assert
        // - assets were routed
        assertEq(tokenA.balanceOf(address(strategy)), 0, "strategy balance of tokenA");
        assertEq(tokenA.balanceOf(address(strategy.protocol())), assetsDeposited[0], "protocol balance of tokenA");
        // - shares were minted
        assertEq(strategy.totalSupply(), expectedTotalMintedShares, "SST total supply");
        assertEq(strategy.balanceOf(address(strategy)), expectedMinted, "strategy balance of SSTs");
        // - return value
        assertEq(minted, expectedMinted, "minted");
    }

    function test_depositFast_multiAsset() public {
        // arrange
        MockToken tokenA = new MockToken("TokenA", "TA");
        MockToken tokenB = new MockToken("TokenB", "TB");

        address[] memory assetGroup = Arrays.toArray(address(tokenA), address(tokenB));
        uint256[] memory exchangeRates = Arrays.toArray(1 * USD_DECIMALS_MULTIPLIER, 2 * USD_DECIMALS_MULTIPLIER);

        assetGroupRegistry.allowTokenBatch(assetGroup);
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        MockStrategy strategy = new MockStrategy(
            assetGroupRegistry,
            accessControl,
            swapper,
            assetGroupId
        );
        strategy.initialize("Strat", Arrays.toArray(1, 1));
        strategyRegistry.registerStrategy(address(strategy), 0, ATOMIC_STRATEGY);

        // need to push some tokens to the strategy for deposit
        tokenA.mint(address(strategy), 1111 * 10 ** tokenA.decimals());
        tokenB.mint(address(strategy), 1111 * 10 ** tokenB.decimals());

        uint256[] memory slippages = new uint256[](0);
        SwapInfo[] memory swapInfos = new SwapInfo[](0);

        // act
        uint256 expectedTotalMintedShares = 3333 * USD_DECIMALS_MULTIPLIER * INITIAL_SHARE_MULTIPLIER;
        uint256 expectedMinted = expectedTotalMintedShares - INITIAL_LOCKED_SHARES;
        uint256[] memory assetsBeforeSwap =
            Arrays.toArray(1111 * 10 ** tokenA.decimals(), 1111 * 10 ** tokenB.decimals());
        uint256[] memory assetsDeposited =
            Arrays.toArray(1111 * 10 ** tokenA.decimals(), 1111 * 10 ** tokenB.decimals());

        vm.expectEmit(true, true, true, true);
        emit Deposited(expectedMinted, 3333 * USD_DECIMALS_MULTIPLIER, assetsBeforeSwap, assetsDeposited);

        vm.startPrank(address(smartVaultManager));
        uint256 minted = strategy.depositFast(assetGroup, exchangeRates, priceFeedManager, slippages, swapInfos);
        vm.stopPrank();

        // assert
        // - assets were routed
        assertEq(tokenA.balanceOf(address(strategy)), 0, "strategy balance of tokenA");
        assertEq(tokenA.balanceOf(address(strategy.protocol())), assetsDeposited[0], "protocol balance of tokenA");
        assertEq(tokenB.balanceOf(address(strategy)), 0, "strategy balance of tokenB");
        assertEq(tokenB.balanceOf(address(strategy.protocol())), assetsDeposited[1], "protocol balance of tokenB");
        // - shares were minted
        assertEq(strategy.totalSupply(), expectedTotalMintedShares, "SST total supply");
        assertEq(strategy.balanceOf(address(strategy)), expectedMinted, "strategy balance of SSTs");
        // - return value
        assertEq(minted, expectedMinted, "minted");
    }

    function test_depositFast_multiAssetWithSwap() public {
        // arrange
        MockToken tokenA = new MockToken("TokenA", "TA");
        MockToken tokenB = new MockToken("TokenB", "TB");

        address[] memory assetGroup = Arrays.toArray(address(tokenA), address(tokenB));
        uint256[] memory exchangeRates = Arrays.toArray(1 * USD_DECIMALS_MULTIPLIER, 2 * USD_DECIMALS_MULTIPLIER);

        MockExchange exchangeAB = new MockExchange(tokenA, tokenB, priceFeedManager);
        tokenB.mint(address(exchangeAB), 10000 * 10 ** tokenB.decimals());

        swapper.updateExchangeAllowlist(Arrays.toArray(address(exchangeAB)), Arrays.toArray(true));

        assetGroupRegistry.allowTokenBatch(assetGroup);
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        for (uint256 i; i < assetGroup.length; ++i) {
            priceFeedManager.setExchangeRate(assetGroup[i], exchangeRates[i]);
        }

        MockStrategy strategy = new MockStrategy(
            assetGroupRegistry,
            accessControl,
            swapper,
            assetGroupId
        );
        strategy.initialize("Strat", Arrays.toArray(1, 1));
        strategyRegistry.registerStrategy(address(strategy), 0, ATOMIC_STRATEGY);

        // need to push some tokens to the strategy for deposit
        tokenA.mint(address(strategy), 3333 * 10 ** tokenA.decimals());

        uint256[] memory slippages = new uint256[](0);
        SwapInfo[] memory swapInfos = new SwapInfo[](1);
        swapInfos[0] = SwapInfo(
            address(exchangeAB),
            address(tokenA),
            abi.encodeWithSelector(
                exchangeAB.swap.selector, address(tokenA), 2222 * 10 ** tokenA.decimals(), address(strategy)
            )
        );

        // act
        uint256 expectedTotalMintedShares = 3333 * USD_DECIMALS_MULTIPLIER * INITIAL_SHARE_MULTIPLIER;
        uint256 expectedMinted = expectedTotalMintedShares - INITIAL_LOCKED_SHARES;
        uint256[] memory assetsBeforeSwap = Arrays.toArray(3333 * 10 ** tokenA.decimals(), 0 * 10 ** tokenB.decimals());
        uint256[] memory assetsDeposited =
            Arrays.toArray(1111 * 10 ** tokenA.decimals(), 1111 * 10 ** tokenB.decimals());

        vm.expectEmit(true, true, true, true);
        emit Deposited(expectedMinted, 3333 * USD_DECIMALS_MULTIPLIER, assetsBeforeSwap, assetsDeposited);

        vm.startPrank(address(smartVaultManager));
        uint256 minted = strategy.depositFast(assetGroup, exchangeRates, priceFeedManager, slippages, swapInfos);
        vm.stopPrank();

        // assert
        // - assets were routed
        assertEq(tokenA.balanceOf(address(strategy)), 0, "strategy balance of tokenA");
        assertEq(tokenA.balanceOf(address(strategy.protocol())), assetsDeposited[0], "protocol balance of tokenA");
        assertEq(tokenB.balanceOf(address(strategy)), 0, "strategy balance of tokenB");
        assertEq(tokenB.balanceOf(address(strategy.protocol())), assetsDeposited[1], "protocol balance of tokenB");
        // - shares were minted
        assertEq(strategy.totalSupply(), expectedTotalMintedShares, "SST total supply");
        assertEq(strategy.balanceOf(address(strategy)), expectedMinted, "strategy balance of SSTs");
        // - return value
        assertEq(minted, expectedMinted, "minted");
    }

    function test_depositFast_shouldRevertWhenNotCalledBySmartVaultManager() public {
        // arrange
        address alice = address(0xa);

        MockToken tokenA = new MockToken("TokenA", "TA");

        address[] memory assetGroup = Arrays.toArray(address(tokenA));
        uint256[] memory exchangeRates = Arrays.toArray(1 * USD_DECIMALS_MULTIPLIER);

        assetGroupRegistry.allowTokenBatch(assetGroup);
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        MockStrategy strategy = new MockStrategy(
            assetGroupRegistry,
            accessControl,
            swapper,
            assetGroupId
        );
        strategy.initialize("Strat", Arrays.toArray(1));
        strategyRegistry.registerStrategy(address(strategy), 0, ATOMIC_STRATEGY);

        // need to push some tokens to the strategy for deposit
        tokenA.mint(address(strategy), 1234 * 10 ** tokenA.decimals());

        uint256[] memory slippages = new uint256[](0);
        SwapInfo[] memory swapInfos = new SwapInfo[](0);

        // act and assert
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SMART_VAULT_MANAGER, alice));
        vm.startPrank(alice);
        strategy.depositFast(assetGroup, exchangeRates, priceFeedManager, slippages, swapInfos);
        vm.stopPrank();

        vm.startPrank(address(smartVaultManager));
        strategy.depositFast(assetGroup, exchangeRates, priceFeedManager, slippages, swapInfos);
        vm.stopPrank();
    }
}
