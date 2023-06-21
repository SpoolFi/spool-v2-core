// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../src/strategies/NotionalFinanceStrategy.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";
import "../EthereumForkConstants.sol";
import "../../mocks/MockExchange.sol";

contract NotionalFinanceStrategyTest is TestFixture, ForkTestFixture {
    uint256 private constant NTOKEN_DECIMALS_MULTIPLIER = 10 ** 8;
    uint80 private underlyingDecimalsMultiplier;

    IERC20Metadata private tokenUsdc;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    NotionalFinanceStrategyHarness notionalFinanceStrategy;

    IERC20 private cToken;

    address[] smartVaultStrategies;

    uint256 rewardsPerSecond;

    function setUp() public {
        setUpForkTestFixture();
        vm.selectFork(mainnetForkId);
        setUpBase();

        tokenUsdc = IERC20Metadata(USDC);
        underlyingDecimalsMultiplier = SafeCast.toUint80(10 ** tokenUsdc.decimals());

        priceFeedManager.setExchangeRate(address(tokenUsdc), USD_DECIMALS_MULTIPLIER * 1001 / 1000);

        assetGroup = Arrays.toArray(address(tokenUsdc));
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        assetGroupExchangeRates = SpoolUtils.getExchangeRates(assetGroup, priceFeedManager);

        cToken = IERC20(cUSDC);

        notionalFinanceStrategy = new NotionalFinanceStrategyHarness(
            assetGroupRegistry,
            accessControl,
            swapper,
            INotional(NOTIONAL_FINANCE_PROXY),
            IERC20(NOTE)
        );

        notionalFinanceStrategy.initialize("CompoundV2Strategy", assetGroupId, INToken(NOTIONAL_FINANCE_NUSDC));

        vm.prank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(notionalFinanceStrategy));
    }

    function test_depositToProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(notionalFinanceStrategy), toDeposit, true);

        uint256 usdcBalanceOfProtocolBefore = _getAssetBalanceOfProtocol();

        // act
        notionalFinanceStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // assert
        uint256 usdcBalanceOfProtocolAfter = _getAssetBalanceOfProtocol();

        assertEq(usdcBalanceOfProtocolAfter - usdcBalanceOfProtocolBefore, toDeposit);
        assertApproxEqAbs(_getDepositedAssetBalance(), toDeposit, 1);
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        uint256 mintedShares = 100;
        uint256 withdrawnShares = 60;

        deal(address(tokenUsdc), address(notionalFinanceStrategy), toDeposit, true);

        // - need to deposit into the protocol
        notionalFinanceStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        notionalFinanceStrategy.exposed_mint(mintedShares);

        uint256 strategyDepositBalanceBefore = _getDepositedAssetBalance();

        // act
        notionalFinanceStrategy.exposed_redeemFromProtocol(assetGroup, withdrawnShares, new uint256[](0));

        // assert
        uint256 usdcBalanceOfStrategy = tokenUsdc.balanceOf(address(notionalFinanceStrategy));
        uint256 strategyDepositBalanceAfter = _getDepositedAssetBalance();

        assertApproxEqAbs(
            strategyDepositBalanceBefore - strategyDepositBalanceAfter, toDeposit * withdrawnShares / mintedShares, 1
        );
        assertApproxEqRel(usdcBalanceOfStrategy, toDeposit * withdrawnShares / mintedShares, 10 ** 15);
        assertApproxEqAbs(strategyDepositBalanceAfter, toDeposit * (mintedShares - withdrawnShares) / mintedShares, 1);
    }

    function test_emergencyWithdrawImpl() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        uint256 mintedShares = 100;
        deal(address(tokenUsdc), address(notionalFinanceStrategy), toDeposit, true);

        // - need to deposit into the protocol
        notionalFinanceStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        notionalFinanceStrategy.exposed_mint(mintedShares);

        uint256 usdcBalanceOfProtocolBefore = _getAssetBalanceOfProtocol();

        // act
        notionalFinanceStrategy.exposed_emergencyWithdrawImpl(new uint256[](0), emergencyWithdrawalRecipient);

        // assert
        uint256 usdcBalanceOfProtocolAfter = _getAssetBalanceOfProtocol();
        uint256 usdcBalanceOfEmergencyWithdrawalRecipient = tokenUsdc.balanceOf(emergencyWithdrawalRecipient);

        uint256 nTokenBalanceOfStrategy = notionalFinanceStrategy.nToken().balanceOf(address(notionalFinanceStrategy));

        assertApproxEqRel(usdcBalanceOfProtocolBefore - usdcBalanceOfProtocolAfter, toDeposit, 10 ** 15);
        assertApproxEqRel(usdcBalanceOfEmergencyWithdrawalRecipient, toDeposit, 10 ** 15);
        assertEq(nTokenBalanceOfStrategy, 0);
    }

    // base yield
    function test_getYieldPercentage() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(notionalFinanceStrategy), toDeposit, true);

        // - need to deposit into the protocol
        notionalFinanceStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        uint256 balanceOfStrategyBefore = _getDepositedAssetBalance();

        // - yield is gathered over blocks
        vm.roll(block.number + 7200);
        skip(60 * 60 * 24);

        // act
        int256 yieldPercentage = notionalFinanceStrategy.exposed_getYieldPercentage(0);

        // assert
        uint256 balanceOfStrategyAfter = _getDepositedAssetBalance();
        uint256 calculatedYield = balanceOfStrategyBefore * uint256(yieldPercentage) / YIELD_FULL_PERCENT;
        uint256 expectedYield = balanceOfStrategyAfter - balanceOfStrategyBefore;

        assertGt(yieldPercentage, 0);
        assertApproxEqAbs(calculatedYield, expectedYield, 1);
    }

    function test_getProtocolRewards() public {
        // arrange
        IERC20 noteToken = notionalFinanceStrategy.note();

        uint256 toDeposit = 100000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(notionalFinanceStrategy), toDeposit, true);

        // - need to deposit into the protocol
        notionalFinanceStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // - mint some reward tokens by skipping blocks (should be 7454639134 NOTEtoken, depends on the forked block number)
        vm.roll(block.number + 7200);
        skip(60 * 60 * 24);

        // act
        vm.startPrank(address(0), address(0));
        (address[] memory rewardAddresses, uint256[] memory rewardAmounts) =
            notionalFinanceStrategy.getProtocolRewards();
        vm.stopPrank();

        // assert
        assertEq(rewardAddresses.length, 1);
        assertEq(rewardAddresses[0], address(noteToken));
        assertEq(rewardAmounts.length, rewardAddresses.length);
        assertEq(rewardAmounts[0], 7454639134);
    }

    function test_compound() public {
        // arrange
        IERC20 noteToken = notionalFinanceStrategy.note();

        priceFeedManager.setExchangeRate(address(noteToken), USD_DECIMALS_MULTIPLIER * 50); // tokenNOTE

        MockExchange exchange = new MockExchange(noteToken, tokenUsdc, priceFeedManager);

        // transfer tokens from NOTE token holder the exchange
        address noteTokenHolder = address(0x22341fB5D92D3d801144aA5A925F401A91418A05);
        vm.startPrank(noteTokenHolder);
        noteToken.transfer(address(exchange), 1_000_000 * 10 ** IERC20Metadata(address(noteToken)).decimals());
        vm.stopPrank();

        // deal asset tokens the exchange
        deal(address(tokenUsdc), address(exchange), 1_000_000 * 10 ** tokenUsdc.decimals(), true);

        swapper.updateExchangeAllowlist(Arrays.toArray(address(exchange)), Arrays.toArray(true));

        uint256 toDeposit = 100000 * 10 ** tokenUsdc.decimals();
        deal(address(tokenUsdc), address(notionalFinanceStrategy), toDeposit, true);

        // - need to deposit into the protocol
        notionalFinanceStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // - mint some reward tokens by skipping blocks (should be 7454639134 NOTEtoken, depends on the forked block number)
        vm.roll(block.number + 7200);
        skip(60 * 60 * 24);

        uint256 balanceOfStrategyBefore = _getDepositedAssetBalance();

        // act
        SwapInfo[] memory compoundSwapInfo = new SwapInfo[](1);
        compoundSwapInfo[0] = SwapInfo({
            swapTarget: address(exchange),
            token: address(noteToken),
            swapCallData: abi.encodeCall(exchange.swap, (address(noteToken), 7454639134, address(swapper)))
        });

        uint256[] memory slippages = new uint256[](1);
        slippages[0] = 1;

        int256 compoundYieldPercentage =
            notionalFinanceStrategy.exposed_compound(assetGroup, compoundSwapInfo, slippages);

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
        deal(address(tokenUsdc), address(notionalFinanceStrategy), toDeposit, true);

        // - need to deposit into the protocol
        notionalFinanceStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // act
        uint256 usdWorth = notionalFinanceStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertApproxEqRel(usdWorth, priceFeedManager.assetToUsd(address(tokenUsdc), toDeposit), 10 ** 15);
    }

    function _getDepositedAssetBalance() private view returns (uint256 totalAssetBalance) {
        uint256 nTokenAmount = notionalFinanceStrategy.nToken().balanceOf(address(notionalFinanceStrategy));

        totalAssetBalance = (
            nTokenAmount * uint256(notionalFinanceStrategy.nToken().getPresentValueUnderlyingDenominated())
                / notionalFinanceStrategy.nToken().totalSupply()
        ) * underlyingDecimalsMultiplier / NTOKEN_DECIMALS_MULTIPLIER;
    }

    function _getAssetBalanceOfProtocol() private view returns (uint256) {
        return tokenUsdc.balanceOf(address(cToken));
    }
}

// Exposes protocol-specific functions for unit-testing.
contract NotionalFinanceStrategyHarness is NotionalFinanceStrategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        INotional notional_,
        IERC20 note_
    ) NotionalFinanceStrategy(assetGroupRegistry_, accessControl_, swapper_, notional_, note_) {}
}
