// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../src/strategies/MorphoAaveV2Strategy.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";
import "../EthereumForkConstants.sol";
import "../../mocks/MockExchange.sol";

contract MorphoAaveV2StrategyTest is TestFixture, ForkTestFixture {
    IERC20Metadata private tokenUsdc;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    ILens private lens;

    MorphoAaveV2StrategyHarness morphoAaveV2Strategy;
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

        lens = ILens(MORPHO_AAVE_V2_LENS);

        morphoAaveV2Strategy = new MorphoAaveV2StrategyHarness(
            assetGroupRegistry,
            accessControl,
            IMorpho(MORPHO_AAVE_V2),
            IERC20(stkAAVE),
            swapper,
            lens
        );

        morphoAaveV2Strategy.initialize(
            "MorphoAaveV2Strategy", assetGroupId, aUSDC, int128(YIELD_FULL_PERCENT_INT), int128(-YIELD_FULL_PERCENT_INT)
        );
    }

    function test_depositToProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(morphoAaveV2Strategy), toDeposit, true);

        // act
        morphoAaveV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // assert
        assertApproxEqAbs(_getDepositedAssetBalance(), toDeposit, 1);
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        uint256 mintedShares = 100;
        uint256 withdrawnShares = 60;

        deal(address(tokenUsdc), address(morphoAaveV2Strategy), toDeposit, true);

        // - need to deposit into the protocol
        morphoAaveV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        morphoAaveV2Strategy.exposed_mint(mintedShares);

        uint256 strategyDepositBalanceBefore = _getDepositedAssetBalance();

        // act
        morphoAaveV2Strategy.exposed_redeemFromProtocol(assetGroup, withdrawnShares, new uint256[](0));

        // assert
        uint256 usdcBalanceOfStrategy = tokenUsdc.balanceOf(address(morphoAaveV2Strategy));
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
        deal(address(tokenUsdc), address(morphoAaveV2Strategy), toDeposit, true);

        // - need to deposit into the protocol
        morphoAaveV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        morphoAaveV2Strategy.exposed_mint(mintedShares);

        uint256 usdcBalanceOfCTokenBefore = _getAssetBalanceOfProtocol();

        // act
        morphoAaveV2Strategy.exposed_emergencyWithdrawImpl(new uint256[](0), emergencyWithdrawalRecipient);

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

        morphoAaveV2Strategy.setPositiveYieldLimit(positiveLimit);
        morphoAaveV2Strategy.setNegativeYieldLimit(negativeLimit);

        // act / assert
        int256 zeroManualYield = 123;
        int256 yieldPercentage = morphoAaveV2Strategy.exposed_getYieldPercentage(zeroManualYield);
        assertEq(zeroManualYield, yieldPercentage);

        int256 tooBigYield = positiveLimit + 1;
        vm.expectRevert(abi.encodeWithSelector(ManualYieldTooBig.selector, int256(tooBigYield)));
        morphoAaveV2Strategy.exposed_getYieldPercentage(tooBigYield);

        int256 tooSmallYield = negativeLimit - 1;
        vm.expectRevert(abi.encodeWithSelector(ManualYieldTooSmall.selector, int256(tooSmallYield)));
        morphoAaveV2Strategy.exposed_getYieldPercentage(tooSmallYield);
    }

    function test_getUsdWorth() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(morphoAaveV2Strategy), toDeposit, true);

        // - need to deposit into the protocol
        morphoAaveV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // act
        uint256 usdWorth = morphoAaveV2Strategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertApproxEqRel(usdWorth, priceFeedManager.assetToUsd(address(tokenUsdc), toDeposit), 10 ** 15);
    }

    function _getDepositedAssetBalance() private view returns (uint256 totalAssetBalance) {
        (,, totalAssetBalance) =
            lens.getCurrentSupplyBalanceInOf(morphoAaveV2Strategy.poolTokenAddress(), address(morphoAaveV2Strategy));
    }

    function _getAssetBalanceOfProtocol() private view returns (uint256) {
        return tokenUsdc.balanceOf(address(morphoAaveV2Strategy))
            + tokenUsdc.balanceOf(address(morphoAaveV2Strategy.poolTokenAddress()));
    }
}

// Exposes protocol-specific functions for unit-testing.
contract MorphoAaveV2StrategyHarness is MorphoAaveV2Strategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IMorpho morpho_,
        IERC20 poolRewardToken_,
        ISwapper swapper_,
        ILens lens_
    ) MorphoAaveV2Strategy(assetGroupRegistry_, accessControl_, morpho_, poolRewardToken_, swapper_, lens_) {}
}
