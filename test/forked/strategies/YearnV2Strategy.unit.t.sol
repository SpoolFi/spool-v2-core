// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/console.sol";
import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../src/access/SpoolAccessControl.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../../src/managers/AssetGroupRegistry.sol";
import "../../../src/strategies/YearnV2Strategy.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../EthereumForkConstants.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";

contract YearnV2StrategyTest is TestFixture, ForkTestFixture {
    IERC20Metadata private tokenUsdc;

    IYearnTokenVault yTokenVault;

    YearnV2StrategyHarness private yearnStrategy;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

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

        yTokenVault = IYearnTokenVault(YEARN_V2_USDC_TOKEN_VAULT);

        yearnStrategy = new YearnV2StrategyHarness(
            assetGroupRegistry,
            accessControl,
            yTokenVault
        );
        yearnStrategy.initialize("yearn-v2-strategy", assetGroupId);
    }

    function test_depositToProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(yearnStrategy), toDeposit, true);

        uint256 yTokenVaultTotalAssetsBefore = yTokenVault.totalAssets();

        // act
        uint256[] memory slippages = new uint256[](7);
        slippages[0] = 0;
        slippages[6] = 1;

        yearnStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // assert
        uint256 yTokenVaultTotalAssetsAfter = yTokenVault.totalAssets();
        uint256 yTokenVaultBalanceOfStrategy = yTokenVault.balanceOf(address(yearnStrategy));
        uint256 yTokenVaultBalanceOfStrategyExpected =
            toDeposit * yearnStrategy.oneShare() / yTokenVault.pricePerShare();

        assertEq(yTokenVaultTotalAssetsAfter - yTokenVaultTotalAssetsBefore, toDeposit);
        assertTrue(yTokenVaultBalanceOfStrategy > 0);
        assertApproxEqRel(yTokenVaultBalanceOfStrategy, yTokenVaultBalanceOfStrategyExpected, 1e15); // to 1 permil
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(yearnStrategy), toDeposit, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](7);
        slippages[0] = 0;
        slippages[6] = 1;
        yearnStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        yearnStrategy.exposed_mint(100);

        uint256 yTokenVaultTotalAssetsBefore = yTokenVault.totalAssets();

        // act
        slippages[0] = 1;
        yearnStrategy.exposed_redeemFromProtocol(assetGroup, 60, slippages);

        // assert
        uint256 yTokenVaultTotalAssetsAfter = yTokenVault.totalAssets();
        uint256 usdcBalanceOfStrategy = tokenUsdc.balanceOf(address(yearnStrategy));
        uint256 yTokenVaultBalanceOfStrategy = yTokenVault.balanceOf(address(yearnStrategy));
        uint256 yTokenVaultBalanceOfStrategyExpected =
            toDeposit * 40 * yearnStrategy.oneShare() / 100 / yTokenVault.pricePerShare();

        assertApproxEqAbs(yTokenVaultTotalAssetsBefore - yTokenVaultTotalAssetsAfter, toDeposit * 60 / 100, 10);
        assertApproxEqAbs(usdcBalanceOfStrategy, toDeposit * 60 / 100, 10);
        assertApproxEqRel(yTokenVaultBalanceOfStrategy, yTokenVaultBalanceOfStrategyExpected, 1e15); // to 1 permil
    }

    function test_emergencyWithdrawImpl() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(yearnStrategy), toDeposit, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](7);
        slippages[0] = 0;
        slippages[6] = 1;
        yearnStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        yearnStrategy.exposed_mint(100);

        uint256 yTokenVaultTotalAssetsBefore = yTokenVault.totalAssets();

        // act
        slippages = new uint256[](2);
        slippages[0] = 3;
        slippages[1] = 1;
        yearnStrategy.exposed_emergencyWithdrawImpl(slippages, emergencyWithdrawalRecipient);

        // assert
        uint256 yTokenVaultTotalAssetsAfter = yTokenVault.totalAssets();
        uint256 usdcBalanceOfEmergencyWithdrawalRecipient = tokenUsdc.balanceOf(emergencyWithdrawalRecipient);
        uint256 yTokenVaultBalanceOfStrategy = yTokenVault.balanceOf(address(yearnStrategy));

        assertApproxEqAbs(yTokenVaultTotalAssetsBefore - yTokenVaultTotalAssetsAfter, toDeposit, 10);
        assertApproxEqAbs(usdcBalanceOfEmergencyWithdrawalRecipient, toDeposit, 10);
        assertEq(yTokenVaultBalanceOfStrategy, 0);
    }

    function test_getYieldPercentage() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(yearnStrategy), toDeposit, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](7);
        slippages[0] = 0;
        slippages[6] = 1;
        yearnStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        yearnStrategy.exposed_mint(100);

        // - mint 10_000_000 USDC to yTokenVault as a yield, which is about 1/3 of current assets held
        deal(
            address(tokenUsdc),
            address(yTokenVault),
            tokenUsdc.balanceOf(address(yTokenVault)) + 10_000_000 * (10 ** tokenUsdc.decimals()),
            true
        );

        // act
        int256 yieldPercentage = yearnStrategy.exposed_getYieldPercentage(0);

        // assert
        slippages[0] = 1;
        yearnStrategy.exposed_redeemFromProtocol(assetGroup, 100, slippages);

        uint256 calculatedYield = toDeposit * uint256(yieldPercentage) / YIELD_FULL_PERCENT;
        uint256 actualYield = tokenUsdc.balanceOf(address(yearnStrategy)) - toDeposit;

        assertTrue(actualYield > 0);
        assertApproxEqRel(actualYield, calculatedYield, 1e15); // to 1 permil
    }

    function test_getUsdWorth() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(yearnStrategy), toDeposit, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](7);
        slippages[0] = 0;
        slippages[6] = 1;
        yearnStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // act
        uint256 usdWorth = yearnStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertApproxEqRel(usdWorth, priceFeedManager.assetToUsd(address(tokenUsdc), toDeposit), 1e15); // to 1 permil
    }
}

// Exposes protocol-specific functions for unit-testing.
contract YearnV2StrategyHarness is YearnV2Strategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IYearnTokenVault yTokenVault_
    ) YearnV2Strategy(assetGroupRegistry_, accessControl_, yTokenVault_) {}
}
