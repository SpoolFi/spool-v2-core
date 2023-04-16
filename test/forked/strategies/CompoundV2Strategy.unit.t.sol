// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../src/strategies/CompoundV2Strategy.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";
import "../EthereumForkConstants.sol";
import "../../mocks/MockExchange.sol";

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
            IComptroller(COMPTROLLER)
        );

        compoundV2Strategy.initialize("CompoundV2Strategy", assetGroupId, ICErc20(cUSDC));
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

        uint256 strategyDepositBalanceBefore =
            compoundV2Strategy.cToken().balanceOfUnderlying(address(compoundV2Strategy));

        // act
        compoundV2Strategy.exposed_redeemFromProtocol(assetGroup, withdrawnShares, new uint256[](0));

        // assert
        uint256 usdcBalanceOfStrategy = tokenUsdc.balanceOf(address(compoundV2Strategy));
        uint256 strategyDepositBalanceAfter =
            compoundV2Strategy.cToken().balanceOfUnderlying(address(compoundV2Strategy));

        assertApproxEqAbs(
            strategyDepositBalanceBefore - strategyDepositBalanceAfter, toDeposit * withdrawnShares / mintedShares, 1
        );
        assertApproxEqAbs(usdcBalanceOfStrategy, toDeposit * withdrawnShares / mintedShares, 1);
        assertApproxEqAbs(strategyDepositBalanceAfter, toDeposit * (mintedShares - withdrawnShares) / mintedShares, 1);
    }

    function test_emergencyWithdrawImpl() public {
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

        // - yield is gathered over blocks
        vm.roll(block.number + 7200);

        // act
        int256 yieldPercentage = compoundV2Strategy.exposed_getYieldPercentage(0);

        // assert
        uint256 balanceOfStrategyAfter = compoundV2Strategy.cToken().balanceOfUnderlying(address(compoundV2Strategy));
        uint256 calculatedYield = balanceOfStrategyBefore * uint256(yieldPercentage) / YIELD_FULL_PERCENT;
        uint256 expectedYield = balanceOfStrategyAfter - balanceOfStrategyBefore;

        assertGt(yieldPercentage, 0);
        assertApproxEqAbs(calculatedYield, expectedYield, 1);
    }

    function test_compound() public {
        // arrange
        IERC20 compToken = compoundV2Strategy.comp();

        priceFeedManager.setExchangeRate(address(compToken), USD_DECIMALS_MULTIPLIER * 50); // COMP

        MockExchange exchange = new MockExchange(compToken, tokenUsdc, priceFeedManager);

        deal(
            address(compToken),
            address(exchange),
            1_000_000 * 10 ** IERC20Metadata(address(compToken)).decimals(),
            false
        );
        deal(address(tokenUsdc), address(exchange), 1_000_000 * 10 ** tokenUsdc.decimals(), true);

        swapper.updateExchangeAllowlist(Arrays.toArray(address(exchange)), Arrays.toArray(true));

        uint256 toDeposit = 100000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(compoundV2Strategy), toDeposit, true);

        // - need to deposit into the protocol
        compoundV2Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // - mint some reward tokens by skipping blocks (should be 41792137860151927 COMP, depends on the forked block number)
        vm.roll(block.number + 7200);

        uint256 balanceOfStrategyBefore = compoundV2Strategy.cToken().balanceOfUnderlying(address(compoundV2Strategy));

        // act
        SwapInfo[] memory compoundSwapInfo = new SwapInfo[](1);
        compoundSwapInfo[0] = SwapInfo({
            swapTarget: address(exchange),
            token: address(compToken),
            amountIn: 41792137860151927,
            swapCallData: abi.encodeCall(exchange.swap, (address(compToken), 41792137860151927, address(swapper)))
        });

        uint256[] memory slippages = new uint256[](1);
        slippages[0] = 1;

        int256 compoundYieldPercentage = compoundV2Strategy.exposed_compound(assetGroup, compoundSwapInfo, slippages);

        // assert
        uint256 balanceOfStrategyAfter = compoundV2Strategy.cToken().balanceOfUnderlying(address(compoundV2Strategy));

        // uint256 idleTokenBalanceOfStrategyAfter = idleToken.balanceOf(address(idleStrategy));
        int256 compoundYieldPercentageExpected =
            int256((balanceOfStrategyAfter - balanceOfStrategyBefore) * YIELD_FULL_PERCENT / balanceOfStrategyBefore);

        assertGt(compoundYieldPercentage, 0);
        assertEq(compoundYieldPercentage, compoundYieldPercentageExpected);
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
        assertApproxEqRel(usdWorth, priceFeedManager.assetToUsd(address(tokenUsdc), toDeposit), 10 ** 15);
    }
}

// Exposes protocol-specific functions for unit-testing.
contract CompoundV2StrategyHarness is CompoundV2Strategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        IComptroller comptroller_
    ) CompoundV2Strategy(assetGroupRegistry_, accessControl_, swapper_, comptroller_) {}
}
