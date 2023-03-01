// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;


import "forge-std/console.sol";
import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../src/access/SpoolAccessControl.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../../src/managers/AssetGroupRegistry.sol";
import "../../../src/strategies/AaveV2Strategy.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";
import "../EthereumForkConstants.sol";
import "../../../src/strategies/CompoundV2Strategy.sol";

contract CompoundV2StrategyTest is TestFixture, ForkTestFixture {
    IERC20Metadata private tokenUsdc;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    CompoundV2StrategyHarness compoundV2Strategy;
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

        compoundV2Strategy = new CompoundV2StrategyHarness(
            assetGroupRegistry,
            accessControl,
            swapper,
            IComptroller(comptroller),
            assetGroupId
        );

        compoundV2Strategy.initialize("CompoundV2Strategy", ICErc20(cUSDC));
    }

    function test_depositToProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(compoundV2Strategy), toDeposit, true);

        uint256 usdcBalanceOfCTokenBefore = tokenUsdc.balanceOf(address(compoundV2Strategy.cToken()));

        // act
        compoundV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // assert
        uint256 usdcBalanceOfCTokenAfter = tokenUsdc.balanceOf(address(compoundV2Strategy.cToken()));

        assertEq(usdcBalanceOfCTokenAfter - usdcBalanceOfCTokenBefore, toDeposit);
        assertApproxEqAbs(compoundV2Strategy.cToken().balanceOfUnderlying(address(compoundV2Strategy)), toDeposit, 1);
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        uint256 mintedShares = 100;
        uint256 withdrawnShares = 60;

        deal(address(tokenUsdc), address(compoundV2Strategy), toDeposit, true);

        // - need to deposit into the protocol
        compoundV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        compoundV2Strategy.exposed_mint(mintedShares);

        uint256 strategyDepositBalanceBefore = compoundV2Strategy.cToken().balanceOfUnderlying(address(compoundV2Strategy));

        // act
        compoundV2Strategy.exposed_redeemFromProtocol(assetGroup, withdrawnShares, new uint256[](0));

        // assert
        uint256 usdcBalanceOfStrategy = tokenUsdc.balanceOf(address(compoundV2Strategy));
        uint256 strategyDepositBalanceAfter = compoundV2Strategy.cToken().balanceOfUnderlying(address(compoundV2Strategy));

        assertApproxEqAbs(strategyDepositBalanceBefore - strategyDepositBalanceAfter, toDeposit * withdrawnShares / mintedShares, 1);
        assertApproxEqAbs(usdcBalanceOfStrategy, toDeposit * withdrawnShares / mintedShares, 1);
        assertApproxEqAbs(strategyDepositBalanceAfter, toDeposit * (mintedShares - withdrawnShares) / mintedShares, 1);
    }

    function test_emergencyWithdrawaImpl() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        uint256 mintedShares = 100;
        deal(address(tokenUsdc), address(compoundV2Strategy), toDeposit, true);

        // - need to deposit into the protocol
        compoundV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        compoundV2Strategy.exposed_mint(mintedShares);

        uint256 usdcBalanceOfCTokenBefore = tokenUsdc.balanceOf(address(compoundV2Strategy.cToken()));

        // act
        compoundV2Strategy.exposed_emergencyWithdrawImpl(new uint256[](0), emergencyWithdrawalRecipient);

        // assert
        uint256 usdcBalanceOfCTokenAfter = tokenUsdc.balanceOf(address(compoundV2Strategy.cToken()));
        uint256 usdcBalanceOfEmergencyWithdrawalRecipient = tokenUsdc.balanceOf(emergencyWithdrawalRecipient);

        uint256 cTokenBalanceOfStrategy = compoundV2Strategy.cToken().balanceOf(address(compoundV2Strategy));

        assertApproxEqAbs(usdcBalanceOfCTokenBefore - usdcBalanceOfCTokenAfter, toDeposit, 1);
        assertApproxEqAbs(usdcBalanceOfEmergencyWithdrawalRecipient, toDeposit, 1);
        assertEq(cTokenBalanceOfStrategy, 0);
    }

    // base yield
    function test_getYieldPercentage() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(compoundV2Strategy), toDeposit, true);

        // - need to deposit into the protocol
        compoundV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        uint256 balanceOfStrategyBefore = compoundV2Strategy.cToken().balanceOfUnderlying(address(compoundV2Strategy));

        // - yield is gathered over time
        skip(SECONDS_IN_YEAR);

        // act
        int256 yieldPercentage = compoundV2Strategy.exposed_getYieldPercentage(0);

        // assert
        uint256 balanceOfStrategyAfter = compoundV2Strategy.cToken().balanceOfUnderlying(address(compoundV2Strategy));
        uint256 calculatedYield = balanceOfStrategyBefore * uint256(yieldPercentage) / YIELD_FULL_PERCENT;
        uint256 expectedYield = balanceOfStrategyAfter - balanceOfStrategyBefore;

        assertEq(calculatedYield, expectedYield);
    }

    // TODO: add test
    function test_compound() public {
        // // arrange
        // uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        // deal(address(tokenUsdc), address(compoundV2Strategy), toDeposit, true);

        // // - need to deposit into the protocol
        // compoundV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // SwapInfo[] memory swapInfo;
        // uint256[] memory slippages;


        // // act
        // int256 compoundYield = compoundV2Strategy.exposed_compound(assetGroup, swapInfo, slippages);

        // // assert
        
    }

    function test_getUsdWorth() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(compoundV2Strategy), toDeposit, true);

        // - need to deposit into the protocol
        compoundV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // act
        uint256 usdWorth = compoundV2Strategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertApproxEqRel(usdWorth, priceFeedManager.assetToUsd(address(tokenUsdc), toDeposit), 10**15);
    }
}

// Exposes protocol-specific functions for unit-testing.
contract CompoundV2StrategyHarness is CompoundV2Strategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        IComptroller comptroller_,
        uint256 assetGroupId_
    ) CompoundV2Strategy(assetGroupRegistry_, accessControl_, swapper_, comptroller_, assetGroupId_) {}
}
