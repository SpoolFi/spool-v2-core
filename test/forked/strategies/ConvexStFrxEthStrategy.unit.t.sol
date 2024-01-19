// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/console.sol";
import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../src/access/SpoolAccessControl.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../../src/managers/AssetGroupRegistry.sol";
import "../../../src/strategies/convex/ConvexStFrxEthStrategy.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../../mocks/MockExchange.sol";
import "../EthereumForkConstants.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";

contract ConvexStFrxEthStrategyTest is TestFixture, ForkTestFixture {
    IERC20Metadata private tokenWeth;
    uint256 private tokenWethMultiplier;

    IERC20Metadata private tokenStEth;
    IERC20Metadata private tokenFrxEth;
    uint256 tokenStEthMultiplier;
    uint256 tokenFrxEthMultiplier;

    IBooster booster;
    uint96 pid;

    IBaseRewardPool crvRewards;

    ICurve2CoinPool curvePool;
    uint16a16 assetMapping;

    ConvexStFrxEthStrategyHarness private convexStrategy;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    uint256 toDepositWeth;

    function setUpForkTestFixture() internal override {
        mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK_EXTENDED);
    }

    function setUp() public {
        setUpForkTestFixture();
        vm.selectFork(mainnetForkId);
        setUpBase();

        tokenWeth = IERC20Metadata(WETH);
        tokenWethMultiplier = 10 ** IERC20Metadata(WETH).decimals();

        tokenStEth = IERC20Metadata(LIDO);
        tokenFrxEth = IERC20Metadata(FRXETH_TOKEN);
        tokenStEthMultiplier = 10 ** tokenStEth.decimals();
        tokenFrxEthMultiplier = 10 ** tokenFrxEth.decimals();

        priceFeedManager.setExchangeRate(address(tokenWeth), USD_DECIMALS_MULTIPLIER * 1003 / 1000);
        priceFeedManager.setExchangeRate(address(tokenStEth), USD_DECIMALS_MULTIPLIER * 1002 / 1000);
        priceFeedManager.setExchangeRate(address(tokenFrxEth), USD_DECIMALS_MULTIPLIER * 1001 / 1000);

        assetGroup = Arrays.toArray(address(tokenWeth));
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        assetGroupExchangeRates = SpoolUtils.getExchangeRates(assetGroup, priceFeedManager);

        booster = IBooster(CONVEX_BOOSTER);
        pid = CONVEX_STFRXETH_PID;

        crvRewards = IBaseRewardPool(booster.poolInfo(pid).crvRewards);

        curvePool = ICurve2CoinPool(CURVE_STFRXETH_POOL);

        convexStrategy = new ConvexStFrxEthStrategyHarness(
            assetGroupRegistry,
            accessControl,
            assetGroupId,
            swapper
        );

        convexStrategy.initialize(
            "convex-stfrxeth-strategy", int128(YIELD_FULL_PERCENT_INT), int128(-YIELD_FULL_PERCENT_INT)
        );

        vm.prank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(convexStrategy));

        toDepositWeth = 10 * tokenWethMultiplier;
        vm.deal(address(convexStrategy), toDepositWeth);
        vm.prank(address(convexStrategy));
        IWETH9(WETH).deposit{value: toDepositWeth}();
    }

    function test_assetRatio() public {
        // act
        uint256[] memory assetRatio = convexStrategy.assetRatio();

        // assert
        uint256[] memory expectedAssetRatio = new uint256[](1);
        expectedAssetRatio[0] = 1;

        for (uint256 i; i < assetRatio.length; ++i) {
            assertEq(assetRatio[i], expectedAssetRatio[i]);
        }
    }

    function test_depositToProtocol() public {
        // arrange
        uint256 stEthBalanceOfCurvePoolBefore = tokenStEth.balanceOf(address(curvePool));
        uint256 frxEthBalanceOfCurvePoolBefore = tokenFrxEth.balanceOf(address(curvePool));

        // act
        uint256[] memory slippages = new uint256[](11);

        convexStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDepositWeth), slippages);

        // assert
        uint256 stEthBalanceOfCurvePoolAfter = tokenStEth.balanceOf(address(curvePool));
        uint256 frxEthBalanceOfCurvePoolAfter = tokenFrxEth.balanceOf(address(curvePool));
        uint256 crvRewardsBalanceOfStrategy = crvRewards.balanceOf(address(convexStrategy));

        assertGt(stEthBalanceOfCurvePoolAfter, stEthBalanceOfCurvePoolBefore);
        assertGt(frxEthBalanceOfCurvePoolAfter, frxEthBalanceOfCurvePoolBefore);
        assertGt(crvRewardsBalanceOfStrategy, 0);
    }

    function test_redeemFromProtocol() public {
        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](10);

        convexStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDepositWeth), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        convexStrategy.exposed_mint(100);

        uint256 stEthBalanceOfCurvePoolBefore = tokenStEth.balanceOf(address(curvePool));
        uint256 frxEthBalanceOfCurvePoolBefore = tokenFrxEth.balanceOf(address(curvePool));
        uint256 crvRewardsBalanceOfStrategyBefore = crvRewards.balanceOf(address(convexStrategy));

        // act
        slippages = new uint256[](10);
        slippages[0] = 1;

        convexStrategy.exposed_redeemFromProtocol(assetGroup, 60, slippages);

        // assert
        uint256 stEthBalanceOfCurvePoolAfter = tokenStEth.balanceOf(address(curvePool));
        uint256 frxEthBalanceOfCurvePoolAfter = tokenFrxEth.balanceOf(address(curvePool));
        uint256 wethBalanceOfStrategy = tokenWeth.balanceOf(address(convexStrategy));
        uint256 crvRewardsBalanceOfStrategyAfter = crvRewards.balanceOf(address(convexStrategy));

        uint256 crvRewardsBalanceOfStrategyExpected = crvRewardsBalanceOfStrategyBefore * 40 / 100;

        assertApproxEqAbs(crvRewardsBalanceOfStrategyAfter, crvRewardsBalanceOfStrategyExpected, 10);
        assertLt(stEthBalanceOfCurvePoolAfter, stEthBalanceOfCurvePoolBefore);
        assertLt(frxEthBalanceOfCurvePoolAfter, frxEthBalanceOfCurvePoolBefore);
        assertApproxEqAbs(wethBalanceOfStrategy, toDepositWeth * 60 / 100, 1e18); // .1% tolerance
    }

    function test_emergencyWithdrawImpl() public {
        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](10);

        convexStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDepositWeth), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        convexStrategy.exposed_mint(100);

        uint256 stEthBalanceOfCurvePoolBefore = tokenStEth.balanceOf(address(curvePool));
        uint256 frxEthBalanceOfCurvePoolBefore = tokenFrxEth.balanceOf(address(curvePool));

        // act
        slippages = new uint256[](3);
        slippages[0] = 3;

        convexStrategy.exposed_emergencyWithdrawImpl(slippages, emergencyWithdrawalRecipient);

        // assert
        uint256 stEthBalanceOfCurvePoolAfter = tokenStEth.balanceOf(address(curvePool));
        uint256 frxEthBalanceOfCurvePoolAfter = tokenFrxEth.balanceOf(address(curvePool));
        uint256 stEthBalanceOfEmergencyWithdrawalRecipient = tokenStEth.balanceOf(address(emergencyWithdrawalRecipient));
        uint256 frxEthBalanceOfEmergencyWithdrawalRecipient =
            tokenFrxEth.balanceOf(address(emergencyWithdrawalRecipient));
        uint256 crvRewardsBalanceOfStrategyAfter = crvRewards.balanceOf(address(convexStrategy));

        assertEq(crvRewardsBalanceOfStrategyAfter, 0);

        assertLt(stEthBalanceOfCurvePoolAfter, stEthBalanceOfCurvePoolBefore);
        assertLt(frxEthBalanceOfCurvePoolAfter, frxEthBalanceOfCurvePoolBefore);

        assertApproxEqAbs(
            stEthBalanceOfEmergencyWithdrawalRecipient, stEthBalanceOfCurvePoolBefore - stEthBalanceOfCurvePoolAfter, 2
        );
        assertApproxEqAbs(
            frxEthBalanceOfEmergencyWithdrawalRecipient,
            frxEthBalanceOfCurvePoolBefore - frxEthBalanceOfCurvePoolAfter,
            2
        );
    }

    function test_getProtocolRewards() public {
        // arrange
        address crvRewardToken = crvRewards.rewardToken();
        address cvxRewardToken = booster.minter();

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](10);

        convexStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDepositWeth), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        convexStrategy.exposed_mint(100);

        // - yield is gathered over time
        skip(3600 * 24 * 30); // ~ 1 month

        // act
        vm.startPrank(address(0), address(0));
        (address[] memory rewardAddresses, uint256[] memory rewardAmounts) = convexStrategy.getProtocolRewards();
        vm.stopPrank();

        // assert
        assertEq(rewardAddresses.length, 2);
        assertEq(rewardAddresses[0], address(crvRewardToken));
        assertEq(rewardAddresses[1], address(cvxRewardToken));
        assertEq(rewardAmounts.length, rewardAddresses.length);
        assertEq(rewardAmounts[0], 19223498639520525616);
        assertEq(rewardAmounts[1], 153787989116164204);
    }

    function test_compound() public {
        // arrange
        address crvRewardToken = crvRewards.rewardToken();
        address cvxRewardToken = booster.minter();

        priceFeedManager.setExchangeRate(crvRewardToken, USD_DECIMALS_MULTIPLIER * 95 / 100);
        priceFeedManager.setExchangeRate(cvxRewardToken, USD_DECIMALS_MULTIPLIER * 585 / 100);

        MockExchange crvExchange = new MockExchange(IERC20(crvRewardToken), tokenFrxEth, priceFeedManager);
        deal(crvRewardToken, address(crvExchange), 10_000 * 10 ** IERC20Metadata(crvRewardToken).decimals(), true);
        deal(address(tokenFrxEth), address(crvExchange), 10_000 * tokenFrxEthMultiplier, true);
        MockExchange cvxExchange = new MockExchange(IERC20(cvxRewardToken), tokenFrxEth, priceFeedManager);
        deal(cvxRewardToken, address(cvxExchange), 10_000 * 10 ** IERC20Metadata(cvxRewardToken).decimals(), true);
        deal(address(tokenFrxEth), address(cvxExchange), 10_000 * tokenFrxEthMultiplier, true);
        swapper.updateExchangeAllowlist(
            Arrays.toArray(address(crvExchange), address(cvxExchange)), Arrays.toArray(true, true)
        );

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](10);
        convexStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDepositWeth), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        convexStrategy.exposed_mint(100);

        // - yield is gathered over time
        skip(3600 * 24 * 30); // ~ 1 month

        uint256 crvRewardsOfStrategyBefore = crvRewards.balanceOf(address(convexStrategy));

        // act
        SwapInfo[] memory compoundSwapInfo = new SwapInfo[](2);
        compoundSwapInfo[0] = SwapInfo({
            swapTarget: address(crvExchange),
            token: crvRewardToken,
            swapCallData: abi.encodeWithSelector(
                crvExchange.swap.selector, crvRewardToken, 19223498639520525616, address(swapper)
                )
        });
        compoundSwapInfo[1] = SwapInfo({
            swapTarget: address(cvxExchange),
            token: cvxRewardToken,
            swapCallData: abi.encodeWithSelector(
                cvxExchange.swap.selector, cvxRewardToken, 153787989116164204, address(swapper)
                )
        });

        slippages = new uint256[](12);
        int256 compoundYieldPercentage = convexStrategy.exposed_compound(assetGroup, compoundSwapInfo, slippages);

        // assert
        uint256 crvRewardsOfStrategyAfter = crvRewards.balanceOf(address(convexStrategy));
        int256 compoundYieldPercentageExpected = int256(
            YIELD_FULL_PERCENT * (crvRewardsOfStrategyAfter - crvRewardsOfStrategyBefore) / crvRewardsOfStrategyBefore
        );

        assertGt(compoundYieldPercentage, 0);
        assertEq(compoundYieldPercentage, compoundYieldPercentageExpected);
    }

    function test_getYieldPercentage() public {
        // arrange
        int128 positiveLimit = int128(YIELD_FULL_PERCENT_INT / 100);
        int128 negativeLimit = int128(-YIELD_FULL_PERCENT_INT);

        convexStrategy.setPositiveYieldLimit(positiveLimit);
        convexStrategy.setNegativeYieldLimit(negativeLimit);

        // act / assert
        int256 zeroManualYield = 123;
        int256 yieldPercentage = convexStrategy.exposed_getYieldPercentage(zeroManualYield);
        assertEq(zeroManualYield, yieldPercentage);

        int256 tooBigYield = positiveLimit + 1;
        vm.expectRevert(abi.encodeWithSelector(ManualYieldTooBig.selector, int256(tooBigYield)));
        convexStrategy.exposed_getYieldPercentage(tooBigYield);

        int256 tooSmallYield = negativeLimit - 1;
        vm.expectRevert(abi.encodeWithSelector(ManualYieldTooSmall.selector, int256(tooSmallYield)));
        convexStrategy.exposed_getYieldPercentage(tooSmallYield);
    }

    function test_getUsdWorth() public {
        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](10);
        slippages[6] = type(uint256).max;
        slippages[7] = type(uint256).max;

        convexStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDepositWeth), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        convexStrategy.exposed_mint(100);

        // act
        uint256 usdWorthDeposited = priceFeedManager.assetToUsdCustomPriceBulk(
            convexStrategy.assets(), Arrays.toArray(toDepositWeth), assetGroupExchangeRates
        );
        uint256 usdWorth = convexStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertApproxEqAbs(usdWorthDeposited, priceFeedManager.assetToUsd(address(tokenWeth), toDepositWeth), 1e4);
        assertApproxEqAbs(usdWorth, priceFeedManager.assetToUsd(address(tokenWeth), toDepositWeth), 1e4);
    }

    function test_getUnderlyingAssetAmounts() public {
        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](10);
        slippages[6] = type(uint256).max;
        slippages[7] = type(uint256).max;

        convexStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDepositWeth), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        convexStrategy.exposed_mint(100);

        // act
        uint256[] memory getUnderlyingAssetAmounts = convexStrategy.getUnderlyingAssetAmounts();
        uint256 getUnderlyingAssetAmount = getUnderlyingAssetAmounts[0];

        // assert
        assertApproxEqAbs(getUnderlyingAssetAmount, toDepositWeth, 1e4);
    }
}

// Exposes protocol-specific functions for unit-testing.
contract ConvexStFrxEthStrategyHarness is ConvexStFrxEthStrategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        uint256 assetGroupId_,
        ISwapper swapper_
    ) ConvexStFrxEthStrategy(assetGroupRegistry_, accessControl_, assetGroupId_, swapper_) {}
}
