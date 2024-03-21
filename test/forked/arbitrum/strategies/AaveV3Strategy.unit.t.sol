// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../../src/access/SpoolAccessControl.sol";
import "../../../../src/interfaces/Constants.sol";
import "../../../../src/libraries/SpoolUtils.sol";
import "../../../../src/managers/AssetGroupRegistry.sol";
import "../../../../src/strategies/arbitrum/AaveV3Strategy.sol";
import "../../../external/interfaces/IUSDC.sol";
import "../../../libraries/Arrays.sol";
import "../../../libraries/Constants.sol";
import "../../../fixtures/TestFixture.sol";
import "../../ForkTestFixture.sol";
import "../../StrategyHarness.sol";
import "../ArbitrumForkConstants.sol";

contract AaveV3StrategyTest is TestFixture, ForkTestFixture {
    IERC20Metadata private tokenUsdc;

    IPoolAddressesProvider private poolAddressesProvider;

    AaveV3StrategyHarness private aaveStrategy;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    function setUp() public {
        setUpForkTestFixtureArbitrum();
        vm.selectFork(mainnetForkId);
        setUpBase();

        tokenUsdc = IERC20Metadata(USDC_ARB);

        priceFeedManager.setExchangeRate(address(tokenUsdc), USD_DECIMALS_MULTIPLIER * 1001 / 1000);

        assetGroup = Arrays.toArray(address(tokenUsdc));
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        assetGroupExchangeRates = SpoolUtils.getExchangeRates(assetGroup, priceFeedManager);

        poolAddressesProvider = IPoolAddressesProvider(AAVE_V3_POOL_ADDRESSES_PROVIDER);

        aaveStrategy = new AaveV3StrategyHarness(
            assetGroupRegistry,
            accessControl,
            poolAddressesProvider
        );
        aaveStrategy.initialize("aave-v3-strategy", assetGroupId, IAToken(aUSDC_ARB));
    }

    function _deal(address token, address to, uint256 amount) private {
        vm.prank(IUSDC(token).masterMinter());
        IUSDC(token).configureMinter(address(this), type(uint256).max);
        IUSDC(token).mint(to, amount);
    }

    function test_assetRatio() public {
        // act
        uint256[] memory assetRatio = aaveStrategy.assetRatio();

        // assert
        uint256[] memory expectedAssetRatio = new uint256[](1);
        expectedAssetRatio[0] = 1;

        for (uint256 i; i < assetRatio.length; ++i) {
            assertEq(assetRatio[i], expectedAssetRatio[i]);
        }
    }

    function test_getUnderlyingAssetAmounts() public {
        // - need to deposit into the protocol

        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(aaveStrategy), toDeposit);

        aaveStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        aaveStrategy.exposed_mint(100);

        // act
        uint256[] memory getUnderlyingAssetAmounts = aaveStrategy.getUnderlyingAssetAmounts();
        uint256 getUnderlyingAssetAmount = getUnderlyingAssetAmounts[0];

        // assert
        assertApproxEqAbs(getUnderlyingAssetAmount, toDeposit, 1);
    }

    function test_depositToProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(aaveStrategy), toDeposit);

        uint256 usdcBalanceOfATokenBefore = tokenUsdc.balanceOf(address(aaveStrategy.aToken()));

        // act
        aaveStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // assert
        uint256 usdcBalanceOfATokenAfter = tokenUsdc.balanceOf(address(aaveStrategy.aToken()));
        uint256 aTokenBalanceOfStrategy = aaveStrategy.aToken().balanceOf(address(aaveStrategy));

        assertEq(usdcBalanceOfATokenAfter - usdcBalanceOfATokenBefore, toDeposit);
        assertEq(aTokenBalanceOfStrategy, toDeposit);
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(aaveStrategy), toDeposit);

        // - need to deposit into the protocol
        aaveStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        aaveStrategy.exposed_mint(100);

        uint256 usdcBalanceOfATokenBefore = tokenUsdc.balanceOf(address(aaveStrategy.aToken()));

        // act
        aaveStrategy.exposed_redeemFromProtocol(assetGroup, 60, new uint256[](0));

        // assert
        uint256 usdcBalanceOfATokenAfter = tokenUsdc.balanceOf(address(aaveStrategy.aToken()));
        uint256 usdcBalanceOfStrategy = tokenUsdc.balanceOf(address(aaveStrategy));
        uint256 aTokenBalanceOfStrategy = aaveStrategy.aToken().balanceOf(address(aaveStrategy));

        assertEq(usdcBalanceOfATokenBefore - usdcBalanceOfATokenAfter, toDeposit * 60 / 100);
        assertEq(usdcBalanceOfStrategy, toDeposit * 60 / 100);
        assertApproxEqAbs(aTokenBalanceOfStrategy, toDeposit * 40 / 100, 10);
    }

    function test_emergencyWithdrawImpl() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(aaveStrategy), toDeposit);

        // - need to deposit into the protocol
        aaveStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        aaveStrategy.exposed_mint(100);

        uint256 usdcBalanceOfATokenBefore = tokenUsdc.balanceOf(address(aaveStrategy.aToken()));

        // act
        aaveStrategy.exposed_emergencyWithdrawImpl(new uint256[](0), emergencyWithdrawalRecipient);

        // assert
        uint256 usdcBalanceOfATokenAfter = tokenUsdc.balanceOf(address(aaveStrategy.aToken()));
        uint256 usdcBalanceOfEmergencyWithdrawalRecipient = tokenUsdc.balanceOf(emergencyWithdrawalRecipient);
        uint256 aTokenBalanceOfStrategy = aaveStrategy.aToken().balanceOf(address(aaveStrategy));

        assertEq(usdcBalanceOfATokenBefore - usdcBalanceOfATokenAfter, toDeposit);
        assertEq(usdcBalanceOfEmergencyWithdrawalRecipient, toDeposit);
        assertEq(aTokenBalanceOfStrategy, 0);
    }

    function test_getYieldPercentage() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(aaveStrategy), toDeposit);

        // - need to deposit into the protocol
        aaveStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        uint256 aTokenBalanceOfStrategyBefore = aaveStrategy.aToken().balanceOf(address(aaveStrategy));

        // - yield is gathered over time
        skip(SECONDS_IN_YEAR);

        // act
        int256 yieldPercentage = aaveStrategy.exposed_getYieldPercentage(0);

        // assert
        uint256 aTokenBalanceOfStrategyAfter = aaveStrategy.aToken().balanceOf(address(aaveStrategy));
        uint256 calculatedYield = aTokenBalanceOfStrategyBefore * uint256(yieldPercentage) / YIELD_FULL_PERCENT;
        uint256 expectedYield = aTokenBalanceOfStrategyAfter - aTokenBalanceOfStrategyBefore;

        assertTrue(calculatedYield > 0);
        assertEq(calculatedYield, expectedYield);
    }

    function test_getUsdWorth() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(aaveStrategy), toDeposit);

        // - need to deposit into the protocol
        aaveStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // act
        uint256 usdWorth = aaveStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertEq(usdWorth, priceFeedManager.assetToUsd(address(tokenUsdc), toDeposit));
    }
}

// Exposes protocol-specific functions for unit-testing.
contract AaveV3StrategyHarness is AaveV3Strategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IPoolAddressesProvider provider_
    ) AaveV3Strategy(assetGroupRegistry_, accessControl_, provider_) {}
}
