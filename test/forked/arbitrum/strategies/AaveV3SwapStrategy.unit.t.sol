// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../../src/access/SpoolAccessControl.sol";
import "../../../../src/interfaces/Constants.sol";
import "../../../../src/libraries/SpoolUtils.sol";
import "../../../../src/managers/AssetGroupRegistry.sol";
import "../../../../src/strategies/arbitrum/AaveV3SwapStrategy.sol";
import "../../../external/interfaces/IUSDC.sol";
import "../../../libraries/Arrays.sol";
import "../../../libraries/Constants.sol";
import "../../../fixtures/TestFixture.sol";
import "../../ForkTestFixture.sol";
import "../../StrategyHarness.sol";
import "../ArbitrumForkConstants.sol";

contract AaveV3SwapStrategyTest is TestFixture, ForkTestFixture {
    IERC20Metadata private tokenUsdc;
    IERC20Metadata private tokenUsdce;

    IPoolAddressesProvider private poolAddressesProvider;

    AaveV3SwapStrategyHarness private aaveStrategy;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

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

        poolAddressesProvider = IPoolAddressesProvider(AAVE_V3_POOL_ADDRESSES_PROVIDER);

        aaveStrategy = new AaveV3SwapStrategyHarness(
            assetGroupRegistry,
            accessControl,
            swapper,
            poolAddressesProvider
        );
        aaveStrategy.initialize("aave-v3-strategy", assetGroupId, IAToken(aUSDCE_ARB));
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
        uint256 diff = 2e15; // .2%
        assertApproxEqRel(getUnderlyingAssetAmount, toDeposit, diff);
    }

    function test_depositToProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(aaveStrategy), toDeposit);

        uint256 usdceBalanceOfATokenBefore = tokenUsdce.balanceOf(address(aaveStrategy.aToken()));

        // act
        aaveStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // assert
        uint256 usdceBalanceOfATokenAfter = tokenUsdce.balanceOf(address(aaveStrategy.aToken()));
        uint256 aTokenBalanceOfStrategy = aaveStrategy.aToken().balanceOf(address(aaveStrategy));

        uint256 diff = 2e15; // .2%
        assertApproxEqRel(usdceBalanceOfATokenAfter - usdceBalanceOfATokenBefore, toDeposit, diff);
        assertApproxEqRel(aTokenBalanceOfStrategy, toDeposit, diff);
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

        uint256 usdceBalanceOfATokenBefore = tokenUsdce.balanceOf(address(aaveStrategy.aToken()));

        // act
        aaveStrategy.exposed_redeemFromProtocol(assetGroup, 60, new uint256[](0));

        // assert
        uint256 usdceBalanceOfATokenAfter = tokenUsdce.balanceOf(address(aaveStrategy.aToken()));
        uint256 usdcBalanceOfStrategy = tokenUsdc.balanceOf(address(aaveStrategy));
        uint256 aTokenBalanceOfStrategy = aaveStrategy.aToken().balanceOf(address(aaveStrategy));

        uint256 diff = 2e15; // .2%
        assertApproxEqRel(usdceBalanceOfATokenBefore - usdceBalanceOfATokenAfter, toDeposit * 60 / 100, diff);
        assertApproxEqRel(usdcBalanceOfStrategy, toDeposit * 60 / 100, diff);
        assertApproxEqRel(aTokenBalanceOfStrategy, toDeposit * 40 / 100, diff);
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

        uint256 usdceBalanceOfATokenBefore = tokenUsdce.balanceOf(address(aaveStrategy.aToken()));

        // act
        aaveStrategy.exposed_emergencyWithdrawImpl(new uint256[](0), emergencyWithdrawalRecipient);

        // assert
        uint256 usdceBalanceOfATokenAfter = tokenUsdce.balanceOf(address(aaveStrategy.aToken()));
        uint256 usdceBalanceOfEmergencyWithdrawalRecipient = tokenUsdce.balanceOf(emergencyWithdrawalRecipient);
        uint256 aTokenBalanceOfStrategy = aaveStrategy.aToken().balanceOf(address(aaveStrategy));

        uint256 diff = 2e15; // .2%
        assertApproxEqRel(usdceBalanceOfATokenBefore - usdceBalanceOfATokenAfter, toDeposit, diff);
        assertApproxEqRel(usdceBalanceOfEmergencyWithdrawalRecipient, toDeposit, diff);
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
        uint256 diff = 2e15; // .2%
        assertApproxEqRel(usdWorth, priceFeedManager.assetToUsd(address(tokenUsdc), toDeposit), diff);
    }
}

// Exposes protocol-specific functions for unit-testing.
contract AaveV3SwapStrategyHarness is AaveV3SwapStrategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        IPoolAddressesProvider provider_
    ) AaveV3SwapStrategy(assetGroupRegistry_, accessControl_, swapper_, provider_) {}
}
