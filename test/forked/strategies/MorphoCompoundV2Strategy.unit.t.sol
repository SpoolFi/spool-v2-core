// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../src/strategies/MorphoCompoundV2Strategy.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";
import "../EthereumForkConstants.sol";
import "../../mocks/MockExchange.sol";

contract MorphoCompoundV2StrategyTest is TestFixture, ForkTestFixture {
    IERC20Metadata private tokenUsdc;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    ILens private lens;

    MorphoCompoundV2StrategyHarness morphoCompoundV2Strategy;
    address[] smartVaultStrategies;

    uint256 rewardsPerSecond;

    function setUp() public {
        setUpForkTestFixture();
        vm.selectFork(mainnetForkId);
        setUpBase();

        tokenUsdc = IERC20Metadata(USDC);

        priceFeedManager.setExchangeRate(address(tokenUsdc), USD_DECIMALS_MULTIPLIER * 1001 / 1000);

        assetGroup = Arrays.toArray(address(tokenUsdc));
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        assetGroupExchangeRates = SpoolUtils.getExchangeRates(assetGroup, priceFeedManager);

        lens = ILens(MORPHO_COMPOUND_V2_LENS);

        morphoCompoundV2Strategy = new MorphoCompoundV2StrategyHarness(
            assetGroupRegistry,
            accessControl,
            IMorpho(MORPHO_COMPOUND_V2),
            IERC20(COMP),
            swapper,
            lens
        );

        morphoCompoundV2Strategy.initialize(
            "MorphoCompoundV2Strategy",
            assetGroupId,
            cUSDC,
            int128(YIELD_FULL_PERCENT_INT),
            int128(-YIELD_FULL_PERCENT_INT)
        );
    }

    function test_depositToProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(morphoCompoundV2Strategy), toDeposit, true);

        // act
        morphoCompoundV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // assert
        assertApproxEqAbs(_getDepositedAssetBalance(), toDeposit, 1);
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        uint256 mintedShares = 100;
        uint256 withdrawnShares = 60;

        deal(address(tokenUsdc), address(morphoCompoundV2Strategy), toDeposit, true);

        // - need to deposit into the protocol
        morphoCompoundV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        morphoCompoundV2Strategy.exposed_mint(mintedShares);

        uint256 strategyDepositBalanceBefore = _getDepositedAssetBalance();

        // act
        morphoCompoundV2Strategy.exposed_redeemFromProtocol(assetGroup, withdrawnShares, new uint256[](0));

        // assert
        uint256 usdcBalanceOfStrategy = tokenUsdc.balanceOf(address(morphoCompoundV2Strategy));
        uint256 strategyDepositBalanceAfter = _getDepositedAssetBalance();

        assertApproxEqAbs(
            strategyDepositBalanceBefore - strategyDepositBalanceAfter, toDeposit * withdrawnShares / mintedShares, 10
        );
        assertApproxEqAbs(usdcBalanceOfStrategy, toDeposit * withdrawnShares / mintedShares, 10);
        assertApproxEqAbs(strategyDepositBalanceAfter, toDeposit * (mintedShares - withdrawnShares) / mintedShares, 10);
    }

    function test_emergencyWithdrawaImpl() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        uint256 mintedShares = 100;
        deal(address(tokenUsdc), address(morphoCompoundV2Strategy), toDeposit, true);

        // - need to deposit into the protocol
        morphoCompoundV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        morphoCompoundV2Strategy.exposed_mint(mintedShares);

        uint256 usdcBalanceOfCTokenBefore = _getAssetBalanceOfProtocol();

        // act
        morphoCompoundV2Strategy.exposed_emergencyWithdrawImpl(new uint256[](0), emergencyWithdrawalRecipient);

        // assert
        uint256 usdcBalanceOfCTokenAfter = _getAssetBalanceOfProtocol();
        uint256 usdcBalanceOfEmergencyWithdrawalRecipient = tokenUsdc.balanceOf(emergencyWithdrawalRecipient);

        uint256 balanceOfStrategyAfter = _getDepositedAssetBalance();

        assertApproxEqAbs(usdcBalanceOfCTokenBefore - usdcBalanceOfCTokenAfter, toDeposit, 1);
        assertApproxEqAbs(usdcBalanceOfEmergencyWithdrawalRecipient, toDeposit, 1);
        assertEq(balanceOfStrategyAfter, 0);
    }

    function test_getYieldPercentage() public {
        // arrange
        int128 positiveLimit = int128(YIELD_FULL_PERCENT_INT / 100);
        int128 negativeLimit = int128(-YIELD_FULL_PERCENT_INT);

        morphoCompoundV2Strategy.setPositiveYieldLimit(positiveLimit);
        morphoCompoundV2Strategy.setNegativeYieldLimit(negativeLimit);

        // act / assert
        int256 zeroManualYield = 123;
        int256 yieldPercentage = morphoCompoundV2Strategy.exposed_getYieldPercentage(zeroManualYield);
        assertEq(zeroManualYield, yieldPercentage);

        int256 tooBigYield = positiveLimit + 1;
        vm.expectRevert(abi.encodeWithSelector(ManualYieldTooBig.selector, int256(tooBigYield)));
        morphoCompoundV2Strategy.exposed_getYieldPercentage(tooBigYield);

        int256 tooSmallYield = negativeLimit - 1;
        vm.expectRevert(abi.encodeWithSelector(ManualYieldTooSmall.selector, int256(tooSmallYield)));
        morphoCompoundV2Strategy.exposed_getYieldPercentage(tooSmallYield);
    }

    function test_getProtocolRewards() public {
        // arrange
        IERC20 rewardToken = morphoCompoundV2Strategy.poolRewardToken();

        uint256 toDeposit = 100000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(morphoCompoundV2Strategy), toDeposit, true);

        // - need to deposit into the protocol
        morphoCompoundV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // - mint some reward tokens by skipping blocks (should be 41792137860151927 COMP, depends on the forked block number)
        vm.roll(block.number + 7200);
        skip(60 * 60 * 24);

        // act
        vm.startPrank(address(0), address(0));
        (address[] memory rewardAddresses, uint256[] memory rewardAmounts) =
            morphoCompoundV2Strategy.getProtocolRewards();
        vm.stopPrank();

        // assert
        assertEq(rewardAddresses.length, 1);
        assertEq(rewardAddresses[0], address(rewardToken));
        assertEq(rewardAmounts.length, rewardAddresses.length);
        assertEq(rewardAmounts[0], 41792137860151928);
    }

    function test_compound() public {
        // arrange
        IERC20 rewardToken = morphoCompoundV2Strategy.poolRewardToken();

        priceFeedManager.setExchangeRate(address(rewardToken), USD_DECIMALS_MULTIPLIER * 50); // COMP

        MockExchange exchange = new MockExchange(rewardToken, tokenUsdc, priceFeedManager);

        deal(
            address(rewardToken),
            address(exchange),
            1_000_000 * 10 ** IERC20Metadata(address(rewardToken)).decimals(),
            false
        );
        deal(address(tokenUsdc), address(exchange), 1_000_000 * 10 ** tokenUsdc.decimals(), true);

        swapper.updateExchangeAllowlist(Arrays.toArray(address(exchange)), Arrays.toArray(true));

        uint256 toDeposit = 100000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(morphoCompoundV2Strategy), toDeposit, true);

        // - need to deposit into the protocol
        morphoCompoundV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // - mint some reward tokens by skipping blocks (should be 41792137860151928 COMP, depends on the forked block number)
        vm.roll(block.number + 7200);
        skip(60 * 60 * 24);

        uint256 balanceOfStrategyBefore = _getDepositedAssetBalance();

        // act
        SwapInfo[] memory compoundSwapInfo = new SwapInfo[](1);
        compoundSwapInfo[0] = SwapInfo({
            swapTarget: address(exchange),
            token: address(rewardToken),
            amountIn: 41792137860151928,
            swapCallData: abi.encodeCall(exchange.swap, (address(rewardToken), 41792137860151928, address(swapper)))
        });

        uint256[] memory slippages = new uint256[](1);
        slippages[0] = 1;

        int256 compoundYieldPercentage =
            morphoCompoundV2Strategy.exposed_compound(assetGroup, compoundSwapInfo, slippages);

        // assert
        uint256 balanceOfStrategyAfter = _getDepositedAssetBalance();

        int256 compoundYieldPercentageExpected =
            int256((balanceOfStrategyAfter - balanceOfStrategyBefore) * YIELD_FULL_PERCENT / balanceOfStrategyBefore);

        assertGt(compoundYieldPercentage, 0);
        assertEq(compoundYieldPercentage, compoundYieldPercentageExpected);
    }

    function test_getUsdWorth() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(morphoCompoundV2Strategy), toDeposit, true);

        // - need to deposit into the protocol
        morphoCompoundV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // act
        uint256 usdWorth = morphoCompoundV2Strategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertApproxEqRel(usdWorth, priceFeedManager.assetToUsd(address(tokenUsdc), toDeposit), 10 ** 15);
    }

    function _getDepositedAssetBalance() private view returns (uint256 totalAssetBalance) {
        (,, totalAssetBalance) = lens.getCurrentSupplyBalanceInOf(
            morphoCompoundV2Strategy.poolTokenAddress(), address(morphoCompoundV2Strategy)
        );
    }

    function _getAssetBalanceOfProtocol() private view returns (uint256) {
        return tokenUsdc.balanceOf(address(morphoCompoundV2Strategy))
            + tokenUsdc.balanceOf(address(morphoCompoundV2Strategy.poolTokenAddress()));
    }
}

// Exposes protocol-specific functions for unit-testing.
contract MorphoCompoundV2StrategyHarness is MorphoCompoundV2Strategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IMorpho morpho_,
        IERC20 poolRewardToken_,
        ISwapper swapper_,
        ILens lens_
    ) MorphoCompoundV2Strategy(assetGroupRegistry_, accessControl_, morpho_, poolRewardToken_, swapper_, lens_) {}
}
