// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/console.sol";
import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../src/access/SpoolAccessControl.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../../src/managers/AssetGroupRegistry.sol";
import "../../../src/strategies/curve/Curve3poolStrategy.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../../mocks/MockExchange.sol";
import "../EthereumForkConstants.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";

contract Curve3poolStrategyTest is TestFixture, ForkTestFixture {
    IERC20Metadata private tokenDai;
    IERC20Metadata private tokenUsdc;
    IERC20Metadata private tokenUsdt;
    uint256 tokenDaiMultiplier;
    uint256 tokenUsdcMultiplier;
    uint256 tokenUsdtMultiplier;

    ICurve3CoinPool curvePool;
    IERC20 curveLpToken;
    ICurveGauge curveGauge;

    uint16a16 assetMapping;

    Curve3poolStrategyHarness private curveStrategy;

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

        curvePool = ICurve3CoinPool(CURVE_3POOL_POOL);
        curveLpToken = IERC20(CURVE_3POOL_LP_TOKEN);
        curveGauge = ICurveGauge(CURVE_3POOL_GAUGE);

        curveStrategy = new Curve3poolStrategyHarness(
            assetGroupRegistry,
            accessControl,
            assetGroupId,
            swapper
        );

        assetMapping = Arrays.toUint16a16(0, 1, 2);

        curveStrategy.initialize(
            "curve-3pool-strategy",
            curvePool,
            assetMapping,
            curveGauge,
            int128(YIELD_FULL_PERCENT_INT),
            int128(-YIELD_FULL_PERCENT_INT)
        );

        vm.prank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(curveStrategy));
    }

    function test_assetRatio() public {
        // act
        uint256[] memory assetRatio = curveStrategy.assetRatio();

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
        deal(address(tokenDai), address(curveStrategy), toDepositDai, true);
        deal(address(tokenUsdc), address(curveStrategy), toDepositUsdc, true);
        deal(address(tokenUsdt), address(curveStrategy), toDepositUsdt, true);

        uint256 daiBalanceOfCurvePoolBefore = tokenDai.balanceOf(address(curvePool));
        uint256 usdcBalanceOfCurvePoolBefore = tokenUsdc.balanceOf(address(curvePool));
        uint256 usdtBalanceOfCurvePoolBefore = tokenUsdt.balanceOf(address(curvePool));

        // act
        uint256[] memory slippages = new uint256[](10);
        slippages[0] = 0;
        slippages[9] = 1;

        curveStrategy.exposed_depositToProtocol(
            assetGroup, Arrays.toArray(toDepositDai, toDepositUsdc, toDepositUsdt), slippages
        );

        // assert
        uint256 daiBalanceOfCurvePoolAfter = tokenDai.balanceOf(address(curvePool));
        uint256 usdcBalanceOfCurvePoolAfter = tokenUsdc.balanceOf(address(curvePool));
        uint256 usdtBalanceOfCurvePoolAfter = tokenUsdt.balanceOf(address(curvePool));
        uint256 gaugeBalanceOfStrategy = curveGauge.balanceOf(address(curveStrategy));

        assertGt(daiBalanceOfCurvePoolAfter, daiBalanceOfCurvePoolBefore);
        assertGt(usdcBalanceOfCurvePoolAfter, usdcBalanceOfCurvePoolBefore);
        assertGt(usdtBalanceOfCurvePoolAfter, usdtBalanceOfCurvePoolBefore);
        assertGt(gaugeBalanceOfStrategy, 0);
    }

    function test_depositToProtocol_shouldRevertWhenSlippageTooHigh() public {
        // arrange
        uint256 toDepositDai = 1000 * tokenDaiMultiplier;
        uint256 toDepositUsdc = 1000 * tokenUsdcMultiplier;
        uint256 toDepositUsdt = 1000 * tokenUsdtMultiplier;
        deal(address(tokenDai), address(curveStrategy), toDepositDai, true);
        deal(address(tokenUsdc), address(curveStrategy), toDepositUsdc, true);
        deal(address(tokenUsdt), address(curveStrategy), toDepositUsdt, true);

        tokenDai.balanceOf(address(curvePool));
        tokenUsdc.balanceOf(address(curvePool));
        tokenUsdt.balanceOf(address(curvePool));

        // act and assert
        uint256[] memory slippages = new uint256[](10);
        slippages[0] = 0;
        slippages[9] = type(uint256).max;

        uint256[] memory amounts = Arrays.toArray(toDepositDai, toDepositUsdc, toDepositUsdt);

        vm.expectRevert("Slippage screwed you");
        curveStrategy.exposed_depositToProtocol(assetGroup, amounts, slippages);
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 toDepositDai = 1000 * tokenDaiMultiplier;
        uint256 toDepositUsdc = 1000 * tokenUsdcMultiplier;
        uint256 toDepositUsdt = 1000 * tokenUsdtMultiplier;
        deal(address(tokenDai), address(curveStrategy), toDepositDai, true);
        deal(address(tokenUsdc), address(curveStrategy), toDepositUsdc, true);
        deal(address(tokenUsdt), address(curveStrategy), toDepositUsdt, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](10);
        slippages[0] = 0;
        slippages[9] = 1;
        curveStrategy.exposed_depositToProtocol(
            assetGroup, Arrays.toArray(toDepositDai, toDepositUsdc, toDepositUsdt), slippages
        );
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        curveStrategy.exposed_mint(100);

        uint256 daiBalanceOfCurvePoolBefore = tokenDai.balanceOf(address(curvePool));
        uint256 usdcBalanceOfCurvePoolBefore = tokenUsdc.balanceOf(address(curvePool));
        uint256 usdtBalanceOfCurvePoolBefore = tokenUsdt.balanceOf(address(curvePool));
        uint256 gaugeBalanceOfStrategyBefore = curveGauge.balanceOf(address(curveStrategy));

        // act
        slippages = new uint256[](12);
        slippages[0] = 1;
        slippages[9] = 1;
        slippages[10] = 1;
        slippages[11] = 1;

        curveStrategy.exposed_redeemFromProtocol(assetGroup, 60, slippages);

        // assert
        uint256 daiBalanceOfCurvePoolAfter = tokenDai.balanceOf(address(curvePool));
        uint256 usdcBalanceOfCurvePoolAfter = tokenUsdc.balanceOf(address(curvePool));
        uint256 usdtBalanceOfCurvePoolAfter = tokenUsdt.balanceOf(address(curvePool));
        uint256 daiBalanceOfStrategy = tokenDai.balanceOf(address(curveStrategy));
        uint256 usdcBalanceOfStrategy = tokenUsdc.balanceOf(address(curveStrategy));
        uint256 usdtBalanceOfStrategy = tokenUsdt.balanceOf(address(curveStrategy));
        uint256 gaugeBalanceOfStrategyAfter = curveGauge.balanceOf(address(curveStrategy));

        uint256 gaugeBalanceOfStrategyExpected = gaugeBalanceOfStrategyBefore * 40 / 100;

        assertApproxEqAbs(gaugeBalanceOfStrategyAfter, gaugeBalanceOfStrategyExpected, 10);
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
        deal(address(tokenDai), address(curveStrategy), toDepositDai, true);
        deal(address(tokenUsdc), address(curveStrategy), toDepositUsdc, true);
        deal(address(tokenUsdt), address(curveStrategy), toDepositUsdt, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](10);
        slippages[0] = 0;
        slippages[9] = 1;
        curveStrategy.exposed_depositToProtocol(
            assetGroup, Arrays.toArray(toDepositDai, toDepositUsdc, toDepositUsdt), slippages
        );
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        curveStrategy.exposed_mint(100);

        uint256 daiBalanceOfCurvePoolBefore = tokenDai.balanceOf(address(curvePool));
        uint256 usdcBalanceOfCurvePoolBefore = tokenUsdc.balanceOf(address(curvePool));
        uint256 usdtBalanceOfCurvePoolBefore = tokenUsdt.balanceOf(address(curvePool));

        // act
        slippages = new uint256[](4);
        slippages[0] = 3;
        slippages[1] = 1;
        slippages[2] = 1;
        slippages[3] = 1;

        curveStrategy.exposed_emergencyWithdrawImpl(slippages, emergencyWithdrawalRecipient);

        // assert
        uint256 daiBalanceOfCurvePoolAfter = tokenDai.balanceOf(address(curvePool));
        uint256 usdcBalanceOfCurvePoolAfter = tokenUsdc.balanceOf(address(curvePool));
        uint256 usdtBalanceOfCurvePoolAfter = tokenUsdt.balanceOf(address(curvePool));
        uint256 daiBalanceOfEmergencyWithdrawalRecipient = tokenDai.balanceOf(address(emergencyWithdrawalRecipient));
        uint256 usdcBalanceOfEmergencyWithdrawalRecipient = tokenUsdc.balanceOf(address(emergencyWithdrawalRecipient));
        uint256 usdtBalanceOfEmergencyWithdrawalRecipient = tokenUsdt.balanceOf(address(emergencyWithdrawalRecipient));
        uint256 gaugeBalanceOfStrategyAfter = curveGauge.balanceOf(address(curveStrategy));

        assertEq(gaugeBalanceOfStrategyAfter, 0);
        assertLt(daiBalanceOfCurvePoolAfter, daiBalanceOfCurvePoolBefore);
        assertLt(usdcBalanceOfCurvePoolAfter, usdcBalanceOfCurvePoolBefore);
        assertLt(usdtBalanceOfCurvePoolAfter, usdtBalanceOfCurvePoolBefore);
        assertEq(daiBalanceOfEmergencyWithdrawalRecipient, daiBalanceOfCurvePoolBefore - daiBalanceOfCurvePoolAfter);
        assertEq(usdcBalanceOfEmergencyWithdrawalRecipient, usdcBalanceOfCurvePoolBefore - usdcBalanceOfCurvePoolAfter);
        assertEq(usdtBalanceOfEmergencyWithdrawalRecipient, usdtBalanceOfCurvePoolBefore - usdtBalanceOfCurvePoolAfter);
    }

    function test_getProtocolRewards() public {
        // arrange
        address rewardToken = curveGauge.crv_token();

        uint256 toDepositDai = 1000 * tokenDaiMultiplier;
        uint256 toDepositUsdc = 1000 * tokenUsdcMultiplier;
        uint256 toDepositUsdt = 1000 * tokenUsdtMultiplier;
        deal(address(tokenDai), address(curveStrategy), toDepositDai, true);
        deal(address(tokenUsdc), address(curveStrategy), toDepositUsdc, true);
        deal(address(tokenUsdt), address(curveStrategy), toDepositUsdt, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](10);
        slippages[0] = 0;
        slippages[9] = 1;
        curveStrategy.exposed_depositToProtocol(
            assetGroup, Arrays.toArray(toDepositDai, toDepositUsdc, toDepositUsdt), slippages
        );

        // - yield is gathered over time
        skip(3600 * 24 * 30); // ~ 1 month

        // act
        vm.startPrank(address(0), address(0));
        (address[] memory rewardAddresses, uint256[] memory rewardAmounts) = curveStrategy.getProtocolRewards();
        vm.stopPrank();

        // assert
        assertEq(rewardAddresses.length, 1);
        assertEq(rewardAddresses[0], rewardToken);
        assertEq(rewardAmounts.length, rewardAddresses.length);
        assertEq(rewardAmounts[0], 1832285496982225999);
    }

    function test_compound() public {
        // arrange
        address rewardToken = curveGauge.crv_token();

        priceFeedManager.setExchangeRate(rewardToken, USD_DECIMALS_MULTIPLIER * 95 / 100);

        MockExchange exchange = new MockExchange(IERC20(rewardToken), tokenUsdt, priceFeedManager);
        deal(rewardToken, address(exchange), 1_000_000 * 10 ** IERC20Metadata(rewardToken).decimals(), true);
        deal(address(tokenUsdt), address(exchange), 1_000_000 * tokenUsdtMultiplier, true);
        swapper.updateExchangeAllowlist(Arrays.toArray(address(exchange)), Arrays.toArray(true));

        uint256 toDepositDai = 1000 * tokenDaiMultiplier;
        uint256 toDepositUsdc = 1000 * tokenUsdcMultiplier;
        uint256 toDepositUsdt = 1000 * tokenUsdtMultiplier;
        deal(address(tokenDai), address(curveStrategy), toDepositDai, true);
        deal(address(tokenUsdc), address(curveStrategy), toDepositUsdc, true);
        deal(address(tokenUsdt), address(curveStrategy), toDepositUsdt, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](10);
        slippages[0] = 0;
        slippages[9] = 1;
        curveStrategy.exposed_depositToProtocol(
            assetGroup, Arrays.toArray(toDepositDai, toDepositUsdc, toDepositUsdt), slippages
        );
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        curveStrategy.exposed_mint(100);

        // - yield is gathered over time
        skip(3600 * 24 * 30); // ~ 1 month

        uint256 lpTokensOfStrategyBefore = curveGauge.balanceOf(address(curveStrategy));

        // act
        SwapInfo[] memory compoundSwapInfo = new SwapInfo[](1);
        compoundSwapInfo[0] = SwapInfo({
            swapTarget: address(exchange),
            token: rewardToken,
            swapCallData: abi.encodeWithSelector(exchange.swap.selector, rewardToken, 1832285496982225999, address(swapper))
        });

        slippages = new uint256[](10);
        slippages[8] = 1;
        int256 compoundYieldPercentage = curveStrategy.exposed_compound(assetGroup, compoundSwapInfo, slippages);

        // assert
        uint256 lpTokensOfStrategyAfter = curveGauge.balanceOf(address(curveStrategy));
        int256 compoundYieldPercentageExpected =
            int256(YIELD_FULL_PERCENT * (lpTokensOfStrategyAfter - lpTokensOfStrategyBefore) / lpTokensOfStrategyBefore);

        assertGt(compoundYieldPercentage, 0);
        assertEq(compoundYieldPercentage, compoundYieldPercentageExpected);
    }

    function test_getYieldPercentage() public {
        // arrange
        int128 positiveLimit = int128(YIELD_FULL_PERCENT_INT / 100);
        int128 negativeLimit = int128(-YIELD_FULL_PERCENT_INT);

        curveStrategy.setPositiveYieldLimit(positiveLimit);
        curveStrategy.setNegativeYieldLimit(negativeLimit);

        // act / assert
        int256 zeroManualYield = 123;
        int256 yieldPercentage = curveStrategy.exposed_getYieldPercentage(zeroManualYield);
        assertEq(zeroManualYield, yieldPercentage);

        int256 tooBigYield = positiveLimit + 1;
        vm.expectRevert(abi.encodeWithSelector(ManualYieldTooBig.selector, int256(tooBigYield)));
        curveStrategy.exposed_getYieldPercentage(tooBigYield);

        int256 tooSmallYield = negativeLimit - 1;
        vm.expectRevert(abi.encodeWithSelector(ManualYieldTooSmall.selector, int256(tooSmallYield)));
        curveStrategy.exposed_getYieldPercentage(tooSmallYield);
    }

    function test_getUsdWorth() public {
        // arrange
        uint256 toDepositDai = 1000 * tokenDaiMultiplier;
        uint256 toDepositUsdc = 1000 * tokenUsdcMultiplier;
        uint256 toDepositUsdt = 1000 * tokenUsdtMultiplier;
        deal(address(tokenDai), address(curveStrategy), toDepositDai, true);
        deal(address(tokenUsdc), address(curveStrategy), toDepositUsdc, true);
        deal(address(tokenUsdt), address(curveStrategy), toDepositUsdt, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](10);
        slippages[0] = 0;
        slippages[9] = 1;
        curveStrategy.exposed_depositToProtocol(
            assetGroup, Arrays.toArray(toDepositDai, toDepositUsdc, toDepositUsdt), slippages
        );
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        curveStrategy.exposed_mint(100);

        // act
        uint256 usdWorth = curveStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        uint256 gaugeBalanceOfStrategy = curveGauge.balanceOf(address(curveStrategy));
        uint256 lpTotalSupply = curveLpToken.totalSupply();

        uint256 expectedValue;
        expectedValue += priceFeedManager.assetToUsd(
            address(tokenDai),
            ICurvePoolUint256(address(curvePool)).balances(0) * gaugeBalanceOfStrategy / lpTotalSupply
        );
        expectedValue += priceFeedManager.assetToUsd(
            address(tokenUsdc),
            ICurvePoolUint256(address(curvePool)).balances(1) * gaugeBalanceOfStrategy / lpTotalSupply
        );
        expectedValue += priceFeedManager.assetToUsd(
            address(tokenUsdt),
            ICurvePoolUint256(address(curvePool)).balances(2) * gaugeBalanceOfStrategy / lpTotalSupply
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
contract Curve3poolStrategyHarness is Curve3poolStrategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        uint256 assetGroupId_,
        ISwapper swapper_
    ) Curve3poolStrategy(assetGroupRegistry_, accessControl_, assetGroupId_, swapper_) {}
}
