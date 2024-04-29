// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../../src/interfaces/Constants.sol";
import "../../../../src/libraries/SpoolUtils.sol";
import "../../../../src/strategies/arbitrum/CompoundV3SwapStrategy.sol";
import "../../../external/interfaces/IUSDC.sol";
import "../../../fixtures/TestFixture.sol";
import "../../../libraries/Arrays.sol";
import "../../../libraries/Constants.sol";
import "../../../mocks/MockExchange.sol";
import "../../ForkTestFixture.sol";
import "../../StrategyHarness.sol";
import "../ArbitrumForkConstants.sol";

contract CompoundV3SwapStrategyTest is TestFixture, ForkTestFixture {
    IERC20Metadata private tokenUsdc;
    IERC20Metadata private tokenUsdce;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;
    uint24 private fee = 100;

    CompoundV3SwapStrategyHarness compoundV3Strategy;
    address[] smartVaultStrategies;

    uint256 TIME_TO_YIELD = 52 weeks;

    function setUp() public {
        setUpForkTestFixtureArbitrum();
        vm.selectFork(mainnetForkId);
        setUpBase();

        tokenUsdc = IERC20Metadata(USDC_ARB);
        tokenUsdce = IERC20Metadata(USDCE_ARB);

        priceFeedManager.setExchangeRate(address(tokenUsdc), USD_DECIMALS_MULTIPLIER * 1001 / 1000);
        priceFeedManager.setExchangeRate(address(tokenUsdce), USD_DECIMALS_MULTIPLIER * 1001 / 1000);

        assetGroup = Arrays.toArray(address(tokenUsdc));
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        assetGroupExchangeRates = SpoolUtils.getExchangeRates(assetGroup, priceFeedManager);

        compoundV3Strategy = new CompoundV3SwapStrategyHarness(
            assetGroupRegistry,
            accessControl,
            swapper,
            IERC20(COMP_ARB),
            IRewards(COMPOUND_V3_REWARDS),
            fee
        );

        compoundV3Strategy.initialize("compound-v3-strategy", assetGroupId, IComet(cUSDCE_ARB));

        vm.prank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(compoundV3Strategy));
    }

    function _deal(address token, address to, uint256 amount) private {
        if (token == USDC_ARB) {
            vm.prank(IUSDC(token).masterMinter());
            IUSDC(token).configureMinter(address(this), type(uint256).max);
            IUSDC(token).mint(to, amount);
        } else {
            deal(token, to, amount, true);
        }
    }

    function test_assetRatio() public {
        // act
        uint256[] memory assetRatio = compoundV3Strategy.assetRatio();

        // assert
        uint256[] memory expectedAssetRatio = new uint256[](1);
        expectedAssetRatio[0] = 1;

        for (uint256 i; i < assetRatio.length; ++i) {
            assertEq(assetRatio[i], expectedAssetRatio[i]);
        }
    }

    function test_depositToProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(compoundV3Strategy), toDeposit);

        uint256 usdceBalanceOfCTokenBefore = tokenUsdce.balanceOf(address(compoundV3Strategy.cToken()));

        // act
        uint256[] memory slippages = new uint256[](4);
        compoundV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // assert
        uint256 usdceBalanceOfCTokenAfter = tokenUsdce.balanceOf(address(compoundV3Strategy.cToken()));

        uint256 diff = 2e15; // .2%
        assertApproxEqRel(usdceBalanceOfCTokenAfter - usdceBalanceOfCTokenBefore, toDeposit, diff);
        assertApproxEqRel(compoundV3Strategy.cToken().balanceOf(address(compoundV3Strategy)), toDeposit, diff);
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        uint256 mintedShares = 100;
        uint256 withdrawnShares = 60;

        _deal(address(tokenUsdc), address(compoundV3Strategy), toDeposit);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](4);
        compoundV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        compoundV3Strategy.exposed_mint(mintedShares);

        uint256 strategyDepositBalanceBefore = compoundV3Strategy.cToken().balanceOf(address(compoundV3Strategy));

        // act
        slippages[0] = 1;
        compoundV3Strategy.exposed_redeemFromProtocol(assetGroup, withdrawnShares, slippages);

        // assert
        uint256 usdcBalanceOfStrategy = tokenUsdc.balanceOf(address(compoundV3Strategy));
        uint256 strategyDepositBalanceAfter = compoundV3Strategy.cToken().balanceOf(address(compoundV3Strategy));

        uint256 diff = 2e15; // .2%
        assertApproxEqRel(
            strategyDepositBalanceBefore - strategyDepositBalanceAfter, toDeposit * withdrawnShares / mintedShares, diff
        );
        assertApproxEqRel(usdcBalanceOfStrategy, toDeposit * withdrawnShares / mintedShares, diff);
        assertApproxEqRel(
            strategyDepositBalanceAfter, toDeposit * (mintedShares - withdrawnShares) / mintedShares, diff
        );
    }

    function test_emergencyWithdrawImpl() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        uint256 mintedShares = 100;
        _deal(address(tokenUsdc), address(compoundV3Strategy), toDeposit);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](4);
        compoundV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        compoundV3Strategy.exposed_mint(mintedShares);

        uint256 usdceBalanceOfCTokenBefore = tokenUsdce.balanceOf(address(compoundV3Strategy.cToken()));

        // act
        compoundV3Strategy.exposed_emergencyWithdrawImpl(new uint256[](0), emergencyWithdrawalRecipient);

        // assert
        uint256 usdceBalanceOfCTokenAfter = tokenUsdce.balanceOf(address(compoundV3Strategy.cToken()));
        uint256 usdceBalanceOfEmergencyWithdrawalRecipient = tokenUsdce.balanceOf(emergencyWithdrawalRecipient);

        uint256 cTokenBalanceOfStrategy = compoundV3Strategy.cToken().balanceOf(address(compoundV3Strategy));

        uint256 diff = 2e15; // .2%
        assertApproxEqRel(usdceBalanceOfCTokenBefore - usdceBalanceOfCTokenAfter, toDeposit, diff);
        assertApproxEqRel(usdceBalanceOfEmergencyWithdrawalRecipient, toDeposit, diff);
        assertEq(cTokenBalanceOfStrategy, 0);
    }

    // base yield
    function test_getYieldPercentage() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(compoundV3Strategy), toDeposit);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](4);
        compoundV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        uint256 balanceOfStrategyBefore = compoundV3Strategy.cToken().balanceOf(address(compoundV3Strategy));

        // - yield is gathered over time
        vm.warp(block.timestamp + TIME_TO_YIELD);

        // act
        int256 yieldPercentage = compoundV3Strategy.exposed_getYieldPercentage(0);

        // assert
        uint256 balanceOfStrategyAfter = compoundV3Strategy.cToken().balanceOf(address(compoundV3Strategy));
        uint256 calculatedYield = balanceOfStrategyBefore * uint256(yieldPercentage) / YIELD_FULL_PERCENT;
        uint256 expectedYield = balanceOfStrategyAfter - balanceOfStrategyBefore;

        assertGt(yieldPercentage, 0);
        assertApproxEqAbs(calculatedYield, expectedYield, 10e7);
    }

    function test_getProtocolRewards() public {
        // arrange
        IERC20 compToken = compoundV3Strategy.comp();

        uint256 toDeposit = 100000 * 10 ** tokenUsdce.decimals();
        _deal(address(tokenUsdc), address(compoundV3Strategy), toDeposit);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](4);
        compoundV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // - mint some reward tokens by skipping time
        vm.warp(block.timestamp + TIME_TO_YIELD);

        // act
        vm.startPrank(address(0), address(0));
        (address[] memory rewardAddresses, uint256[] memory rewardAmounts) = compoundV3Strategy.getProtocolRewards();
        vm.stopPrank();

        // assert
        assertEq(rewardAddresses.length, 1);
        assertEq(rewardAddresses[0], address(compToken));
        assertEq(rewardAmounts.length, rewardAddresses.length);

        // USDC.e not accruing rewards currently.
        assertEq(rewardAmounts[0], 0);
    }

    function test_getUsdWorth() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(compoundV3Strategy), toDeposit);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](4);
        compoundV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // act
        uint256 usdWorth = compoundV3Strategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertApproxEqRel(usdWorth, priceFeedManager.assetToUsd(address(tokenUsdc), toDeposit), 10 ** 15);
    }
}

// Exposes protocol-specific functions for unit-testing.
contract CompoundV3SwapStrategyHarness is CompoundV3SwapStrategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        IERC20 comp_,
        IRewards rewards_,
        uint24 fee_
    ) CompoundV3SwapStrategy(assetGroupRegistry_, accessControl_, swapper_, comp_, rewards_, fee_) {}
}
