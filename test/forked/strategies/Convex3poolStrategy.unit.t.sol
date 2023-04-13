// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/console.sol";
import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../src/access/SpoolAccessControl.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../../src/managers/AssetGroupRegistry.sol";
import "../../../src/strategies/convex/Convex3poolStrategy.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../../mocks/MockExchange.sol";
import "../EthereumForkConstants.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";

contract Convex3poolStrategyTest is TestFixture, ForkTestFixture {
    IERC20Metadata private tokenDai;
    IERC20Metadata private tokenUsdc;
    IERC20Metadata private tokenUsdt;
    uint256 tokenDaiMultiplier;
    uint256 tokenUsdcMultiplier;
    uint256 tokenUsdtMultiplier;

    IBooster booster;
    uint96 pid;

    IBaseRewardPool crvRewards;

    ICurve3CoinPool curvePool;
    IERC20 curveLpToken;
    uint16a16 assetMapping;

    Convex3poolStrategyHarness private convexStrategy;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    function setUp() public {
        setUpForkTestFixture();
        vm.selectFork(mainnetForkId);
        setUpBase();

        tokenDai = IERC20Metadata(DAI);
        tokenUsdc = IERC20Metadata(USDC);
        tokenUsdt = IERC20Metadata(USDT);
        tokenDaiMultiplier = 10 ** tokenDai.decimals();
        tokenUsdcMultiplier = 10 ** tokenUsdc.decimals();
        tokenUsdtMultiplier = 10 ** tokenUsdt.decimals();

        priceFeedManager.setExchangeRate(address(tokenDai), USD_DECIMALS_MULTIPLIER * 1002 / 1000);
        priceFeedManager.setExchangeRate(address(tokenUsdc), USD_DECIMALS_MULTIPLIER * 1001 / 1000);
        priceFeedManager.setExchangeRate(address(tokenUsdt), USD_DECIMALS_MULTIPLIER * 1003 / 1000);

        assetGroup = Arrays.toArray(address(tokenDai), address(tokenUsdc), address(tokenUsdt));
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        assetGroupExchangeRates = SpoolUtils.getExchangeRates(assetGroup, priceFeedManager);

        booster = IBooster(CONVEX_BOOSTER);
        pid = CONVEX_3POOL_PID;

        crvRewards = IBaseRewardPool(booster.poolInfo(pid).crvRewards);

        curvePool = ICurve3CoinPool(CURVE_3POOL_POOL);
        curveLpToken = IERC20(CURVE_3POOL_LP_TOKEN);

        convexStrategy = new Convex3poolStrategyHarness(
            assetGroupRegistry,
            accessControl,
            assetGroupId,
            swapper,
            booster
        );

        assetMapping = Arrays.toUint16a16(0, 1, 2);

        convexStrategy.initialize("convex-3pool-strategy", curvePool, curveLpToken, assetMapping, pid, false, int128(YIELD_FULL_PERCENT_INT), int128(-YIELD_FULL_PERCENT_INT));
    }

    function test_assetRatio() public {
        // act
        uint256[] memory assetRatio = convexStrategy.assetRatio();

        // assert
        uint256[] memory expectedAssetRatio = new uint256[](3);
        expectedAssetRatio[0] = ICurvePoolUint256(address(curvePool)).balances(0);
        expectedAssetRatio[1] = ICurvePoolUint256(address(curvePool)).balances(1);
        expectedAssetRatio[2] = ICurvePoolUint256(address(curvePool)).balances(2);

        for (uint256 i; i < 3; ++i) {
            assertEq(assetRatio[i], expectedAssetRatio[i]);
        }
    }

    function test_depositToProtocol() public {
        // arrange
        uint256 toDepositDai = 1000 * tokenDaiMultiplier;
        uint256 toDepositUsdc = 1000 * tokenUsdcMultiplier;
        uint256 toDepositUsdt = 1000 * tokenUsdtMultiplier;
        deal(address(tokenDai), address(convexStrategy), toDepositDai, true);
        deal(address(tokenUsdc), address(convexStrategy), toDepositUsdc, true);
        deal(address(tokenUsdt), address(convexStrategy), toDepositUsdt, true);

        uint256 daiBalanceOfCurvePoolBefore = tokenDai.balanceOf(address(curvePool));
        uint256 usdcBalanceOfCurvePoolBefore = tokenUsdc.balanceOf(address(curvePool));
        uint256 usdtBalanceOfCurvePoolBefore = tokenUsdt.balanceOf(address(curvePool));

        // act
        uint256[] memory slippages = new uint256[](11);
        slippages[0] = 0;
        slippages[10] = 1;

        convexStrategy.exposed_depositToProtocol(
            assetGroup, Arrays.toArray(toDepositDai, toDepositUsdc, toDepositUsdt), slippages
        );

        // assert
        uint256 daiBalanceOfCurvePoolAfter = tokenDai.balanceOf(address(curvePool));
        uint256 usdcBalanceOfCurvePoolAfter = tokenUsdc.balanceOf(address(curvePool));
        uint256 usdtBalanceOfCurvePoolAfter = tokenUsdt.balanceOf(address(curvePool));
        uint256 crvRewardsBalanceOfStrategy = crvRewards.balanceOf(address(convexStrategy));

        assertGt(daiBalanceOfCurvePoolAfter, daiBalanceOfCurvePoolBefore);
        assertGt(usdcBalanceOfCurvePoolAfter, usdcBalanceOfCurvePoolBefore);
        assertGt(usdtBalanceOfCurvePoolAfter, usdtBalanceOfCurvePoolBefore);
        assertGt(crvRewardsBalanceOfStrategy, 0);
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 toDepositDai = 1000 * tokenDaiMultiplier;
        uint256 toDepositUsdc = 1000 * tokenUsdcMultiplier;
        uint256 toDepositUsdt = 1000 * tokenUsdtMultiplier;
        deal(address(tokenDai), address(convexStrategy), toDepositDai, true);
        deal(address(tokenUsdc), address(convexStrategy), toDepositUsdc, true);
        deal(address(tokenUsdt), address(convexStrategy), toDepositUsdt, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](11);
        slippages[0] = 0;
        slippages[10] = 1;
        convexStrategy.exposed_depositToProtocol(
            assetGroup, Arrays.toArray(toDepositDai, toDepositUsdc, toDepositUsdt), slippages
        );
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        convexStrategy.exposed_mint(100);

        uint256 daiBalanceOfCurvePoolBefore = tokenDai.balanceOf(address(curvePool));
        uint256 usdcBalanceOfCurvePoolBefore = tokenUsdc.balanceOf(address(curvePool));
        uint256 usdtBalanceOfCurvePoolBefore = tokenUsdt.balanceOf(address(curvePool));
        uint256 crvRewardsBalanceOfStrategyBefore = crvRewards.balanceOf(address(convexStrategy));

        // act
        slippages = new uint256[](13);
        slippages[0] = 1;
        slippages[10] = 1;
        slippages[11] = 1;
        slippages[12] = 1;

        convexStrategy.exposed_redeemFromProtocol(assetGroup, 60, slippages);

        // assert
        uint256 daiBalanceOfCurvePoolAfter = tokenDai.balanceOf(address(curvePool));
        uint256 usdcBalanceOfCurvePoolAfter = tokenUsdc.balanceOf(address(curvePool));
        uint256 usdtBalanceOfCurvePoolAfter = tokenUsdt.balanceOf(address(curvePool));
        uint256 daiBalanceOfStrategy = tokenDai.balanceOf(address(convexStrategy));
        uint256 usdcBalanceOfStrategy = tokenUsdc.balanceOf(address(convexStrategy));
        uint256 usdtBalanceOfStrategy = tokenUsdt.balanceOf(address(convexStrategy));
        uint256 crvRewardsBalanceOfStrategyAfter = crvRewards.balanceOf(address(convexStrategy));

        uint256 crvRewardsBalanceOfStrategyExpected = crvRewardsBalanceOfStrategyBefore * 40 / 100;

        assertApproxEqAbs(crvRewardsBalanceOfStrategyAfter, crvRewardsBalanceOfStrategyExpected, 10);
        assertLt(daiBalanceOfCurvePoolAfter, daiBalanceOfCurvePoolBefore);
        assertLt(usdcBalanceOfCurvePoolAfter, usdcBalanceOfCurvePoolBefore);
        assertLt(usdtBalanceOfCurvePoolAfter, usdtBalanceOfCurvePoolBefore);
        assertEq(daiBalanceOfStrategy, daiBalanceOfCurvePoolBefore - daiBalanceOfCurvePoolAfter);
        assertEq(usdcBalanceOfStrategy, usdcBalanceOfCurvePoolBefore - usdcBalanceOfCurvePoolAfter);
        assertEq(usdtBalanceOfStrategy, usdtBalanceOfCurvePoolBefore - usdtBalanceOfCurvePoolAfter);
    }

    function test_emergencyWithdrawImpl() public {
        // arrange
        uint256 toDepositDai = 1000 * tokenDaiMultiplier;
        uint256 toDepositUsdc = 1000 * tokenUsdcMultiplier;
        uint256 toDepositUsdt = 1000 * tokenUsdtMultiplier;
        deal(address(tokenDai), address(convexStrategy), toDepositDai, true);
        deal(address(tokenUsdc), address(convexStrategy), toDepositUsdc, true);
        deal(address(tokenUsdt), address(convexStrategy), toDepositUsdt, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](11);
        slippages[0] = 0;
        slippages[10] = 1;
        convexStrategy.exposed_depositToProtocol(
            assetGroup, Arrays.toArray(toDepositDai, toDepositUsdc, toDepositUsdt), slippages
        );
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        convexStrategy.exposed_mint(100);

        uint256 daiBalanceOfCurvePoolBefore = tokenDai.balanceOf(address(curvePool));
        uint256 usdcBalanceOfCurvePoolBefore = tokenUsdc.balanceOf(address(curvePool));
        uint256 usdtBalanceOfCurvePoolBefore = tokenUsdt.balanceOf(address(curvePool));

        // act
        slippages = new uint256[](4);
        slippages[0] = 3;
        slippages[1] = 1;
        slippages[2] = 1;
        slippages[3] = 1;

        convexStrategy.exposed_emergencyWithdrawImpl(slippages, emergencyWithdrawalRecipient);

        // assert
        uint256 daiBalanceOfCurvePoolAfter = tokenDai.balanceOf(address(curvePool));
        uint256 usdcBalanceOfCurvePoolAfter = tokenUsdc.balanceOf(address(curvePool));
        uint256 usdtBalanceOfCurvePoolAfter = tokenUsdt.balanceOf(address(curvePool));
        uint256 daiBalanceOfEmergencyWithdrawalRecipient = tokenDai.balanceOf(address(emergencyWithdrawalRecipient));
        uint256 usdcBalanceOfEmergencyWithdrawalRecipient = tokenUsdc.balanceOf(address(emergencyWithdrawalRecipient));
        uint256 usdtBalanceOfEmergencyWithdrawalRecipient = tokenUsdt.balanceOf(address(emergencyWithdrawalRecipient));
        uint256 crvRewardsBalanceOfStrategyAfter = crvRewards.balanceOf(address(convexStrategy));

        assertEq(crvRewardsBalanceOfStrategyAfter, 0);
        assertLt(daiBalanceOfCurvePoolAfter, daiBalanceOfCurvePoolBefore);
        assertLt(usdcBalanceOfCurvePoolAfter, usdcBalanceOfCurvePoolBefore);
        assertLt(usdtBalanceOfCurvePoolAfter, usdtBalanceOfCurvePoolBefore);
        assertEq(daiBalanceOfEmergencyWithdrawalRecipient, daiBalanceOfCurvePoolBefore - daiBalanceOfCurvePoolAfter);
        assertEq(usdcBalanceOfEmergencyWithdrawalRecipient, usdcBalanceOfCurvePoolBefore - usdcBalanceOfCurvePoolAfter);
        assertEq(usdtBalanceOfEmergencyWithdrawalRecipient, usdtBalanceOfCurvePoolBefore - usdtBalanceOfCurvePoolAfter);
    }

    function test_compound() public {
        // arrange
        address crvRewardToken = crvRewards.rewardToken();
        address cvxRewardToken = booster.minter();

        priceFeedManager.setExchangeRate(crvRewardToken, USD_DECIMALS_MULTIPLIER * 95 / 100);
        priceFeedManager.setExchangeRate(cvxRewardToken, USD_DECIMALS_MULTIPLIER * 585 / 100);

        MockExchange crvExchange = new MockExchange(IERC20(crvRewardToken), tokenUsdt, priceFeedManager);
        deal(crvRewardToken, address(crvExchange), 1_000_000 * 10 ** IERC20Metadata(crvRewardToken).decimals(), true);
        deal(address(tokenUsdt), address(crvExchange), 1_000_000 * tokenUsdtMultiplier, true);
        MockExchange cvxExchange = new MockExchange(IERC20(cvxRewardToken), tokenUsdt, priceFeedManager);
        deal(cvxRewardToken, address(cvxExchange), 1_000_000 * 10 ** IERC20Metadata(cvxRewardToken).decimals(), true);
        deal(address(tokenUsdt), address(cvxExchange), 1_000_000 * tokenUsdtMultiplier, true);
        swapper.updateExchangeAllowlist(
            Arrays.toArray(address(crvExchange), address(cvxExchange)), Arrays.toArray(true, true)
        );

        uint256 toDepositDai = 1000 * tokenDaiMultiplier;
        uint256 toDepositUsdc = 1000 * tokenUsdcMultiplier;
        uint256 toDepositUsdt = 1000 * tokenUsdtMultiplier;
        deal(address(tokenDai), address(convexStrategy), toDepositDai, true);
        deal(address(tokenUsdc), address(convexStrategy), toDepositUsdc, true);
        deal(address(tokenUsdt), address(convexStrategy), toDepositUsdt, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](11);
        slippages[0] = 0;
        slippages[10] = 1;
        convexStrategy.exposed_depositToProtocol(
            assetGroup, Arrays.toArray(toDepositDai, toDepositUsdc, toDepositUsdt), slippages
        );
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        convexStrategy.exposed_mint(100);

        // - add new rewards
        vm.startPrank(crvRewards.operator());
        uint256 rewardsToAdd = 1_000_000 * 10 ** IERC20Metadata(crvRewards.rewardToken()).decimals();
        crvRewards.queueNewRewards(rewardsToAdd);
        vm.stopPrank();

        // - yield is gathered over time
        skip(3600 * 24 * 30); // ~ 1 month

        uint256 crvRewardsOfStrategyBefore = crvRewards.balanceOf(address(convexStrategy));

        // act
        SwapInfo[] memory compoundSwapInfo = new SwapInfo[](2);
        compoundSwapInfo[0] = SwapInfo({
            swapTarget: address(crvExchange),
            token: crvRewardToken,
            amountIn: 102524279220335671371, // ~97.4 USD
            swapCallData: abi.encodeWithSelector(
                crvExchange.swap.selector, crvRewardToken, 102524279220335671371, address(swapper)
                )
        });
        compoundSwapInfo[1] = SwapInfo({
            swapTarget: address(cvxExchange),
            token: cvxRewardToken,
            amountIn: 1640388467525370741, // ~9.6 USD
            swapCallData: abi.encodeWithSelector(
                cvxExchange.swap.selector, cvxRewardToken, 1640388467525370741, address(swapper)
                )
        });

        slippages = new uint256[](11);
        slippages[9] = 1;
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
        // arrange
        uint256 toDepositDai = 1000 * tokenDaiMultiplier;
        uint256 toDepositUsdc = 1000 * tokenUsdcMultiplier;
        uint256 toDepositUsdt = 1000 * tokenUsdtMultiplier;
        deal(address(tokenDai), address(convexStrategy), toDepositDai, true);
        deal(address(tokenUsdc), address(convexStrategy), toDepositUsdc, true);
        deal(address(tokenUsdt), address(convexStrategy), toDepositUsdt, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](11);
        slippages[0] = 0;
        slippages[10] = 1;
        convexStrategy.exposed_depositToProtocol(
            assetGroup, Arrays.toArray(toDepositDai, toDepositUsdc, toDepositUsdt), slippages
        );
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        convexStrategy.exposed_mint(100);

        // act
        uint256 usdWorth = convexStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        uint256 crvRewardsBalanceOfStrategy = crvRewards.balanceOf(address(convexStrategy));
        uint256 lpTotalSupply = curveLpToken.totalSupply();

        uint256 expectedValue;
        expectedValue += priceFeedManager.assetToUsd(
            address(tokenDai),
            ICurvePoolUint256(address(curvePool)).balances(0) * crvRewardsBalanceOfStrategy / lpTotalSupply
        );
        expectedValue += priceFeedManager.assetToUsd(
            address(tokenUsdc),
            ICurvePoolUint256(address(curvePool)).balances(1) * crvRewardsBalanceOfStrategy / lpTotalSupply
        );
        expectedValue += priceFeedManager.assetToUsd(
            address(tokenUsdt),
            ICurvePoolUint256(address(curvePool)).balances(2) * crvRewardsBalanceOfStrategy / lpTotalSupply
        );

        uint256 expectedValue2;
        expectedValue2 += priceFeedManager.assetToUsd(address(tokenDai), toDepositDai);
        expectedValue2 += priceFeedManager.assetToUsd(address(tokenUsdc), toDepositUsdc);
        expectedValue2 += priceFeedManager.assetToUsd(address(tokenUsdt), toDepositUsdt);

        assertEq(usdWorth, expectedValue);
        assertApproxEqRel(usdWorth, expectedValue2, 1e15); // to 1 permil
    }
}

// Exposes protocol-specific functions for unit-testing.
contract Convex3poolStrategyHarness is Convex3poolStrategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        uint256 assetGroupId_,
        ISwapper swapper_,
        IBooster booster_
    ) Convex3poolStrategy(assetGroupRegistry_, accessControl_, assetGroupId_, swapper_, booster_) {}
}
