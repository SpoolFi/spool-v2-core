// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/console.sol";
import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../src/access/SpoolAccessControl.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../../src/managers/AssetGroupRegistry.sol";
import "../../../src/strategies/IdleStrategy.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../../mocks/MockExchange.sol";
import "../EthereumForkConstants.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";

contract IdleStrategyTest is TestFixture, ForkTestFixture {
    IERC20Metadata private tokenUsdc;
    uint256 tokenUsdcMultiplier;

    IIdleToken idleToken;

    IdleStrategyHarness private idleStrategy;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    function setUp() public {
        setUpForkTestFixture();
        vm.selectFork(mainnetForkId);
        setUpBase();

        tokenUsdc = IERC20Metadata(USDC);
        tokenUsdcMultiplier = 10 ** tokenUsdc.decimals();

        priceFeedManager.setExchangeRate(address(tokenUsdc), USD_DECIMALS_MULTIPLIER * 1001 / 1000);

        assetGroup = Arrays.toArray(address(tokenUsdc));
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        assetGroupExchangeRates = SpoolUtils.getExchangeRates(assetGroup, priceFeedManager);

        idleToken = IIdleToken(IDLE_BEST_YIELD_SENIOR_USDC);

        idleStrategy = new IdleStrategyHarness(
            assetGroupRegistry,
            accessControl,
            swapper
        );
        idleStrategy.initialize("idle-strategy", assetGroupId, idleToken);

        vm.prank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(idleStrategy));
    }

    function test_depositToProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * tokenUsdcMultiplier;
        deal(address(tokenUsdc), address(idleStrategy), toDeposit, true);

        uint256 usdcBalanceOfIdleTokenBefore = tokenUsdc.balanceOf(address(idleToken));

        // act
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;

        idleStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // assert
        uint256 usdcBalanceOfIdleTokenAfter = tokenUsdc.balanceOf(address(idleToken));
        uint256 idleTokenBalanceOfStrategy = idleToken.balanceOf(address(idleStrategy));
        uint256 idleTokenBalanceOfStrategyExpected = toDeposit * idleStrategy.oneShare() / idleToken.tokenPrice();

        assertEq(usdcBalanceOfIdleTokenAfter - usdcBalanceOfIdleTokenBefore, toDeposit);
        assertTrue(idleTokenBalanceOfStrategy > 0);
        assertEq(idleTokenBalanceOfStrategy, idleTokenBalanceOfStrategyExpected);
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * tokenUsdcMultiplier;
        deal(address(tokenUsdc), address(idleStrategy), toDeposit, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        idleStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        idleStrategy.exposed_mint(100);
        // - advance block number due to reentrancy check on Idle
        vm.roll(block.number + 1);

        uint256 usdcBalanceOfIdleTokenBefore = tokenUsdc.balanceOf(address(idleToken));
        uint256 idleTokenBalanceOfStrategyBefore = idleToken.balanceOf(address(idleStrategy));

        // act
        slippages[0] = 1;
        idleStrategy.exposed_redeemFromProtocol(assetGroup, 60, slippages);

        // assert
        uint256 idleTokenRedeemedExpected = idleTokenBalanceOfStrategyBefore * 60 / 100;
        uint256 usdcTokenWithdrawnExpected =
            idleTokenRedeemedExpected * idleToken.tokenPriceWithFee(address(this)) / idleStrategy.oneShare();
        uint256 usdcBalanceOfStrategy = tokenUsdc.balanceOf(address(idleStrategy));
        uint256 usdcBalanceOfIdleTokenAfter = tokenUsdc.balanceOf(address(idleToken));
        uint256 idleTokenBalanceOfStrategyAfter = idleToken.balanceOf(address(idleStrategy));

        assertTrue(usdcBalanceOfStrategy > 0);
        assertEq(usdcBalanceOfStrategy, usdcTokenWithdrawnExpected);
        assertEq(usdcBalanceOfIdleTokenBefore - usdcBalanceOfIdleTokenAfter, usdcTokenWithdrawnExpected);
        assertEq(idleTokenBalanceOfStrategyBefore - idleTokenBalanceOfStrategyAfter, idleTokenRedeemedExpected);
    }

    function test_emergencyWithdrawImpl() public {
        // arrange
        uint256 toDeposit = 1000 * tokenUsdcMultiplier;
        deal(address(tokenUsdc), address(idleStrategy), toDeposit, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        idleStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        idleStrategy.exposed_mint(100);
        // - advance block number due to reentrancy check on Idle
        vm.roll(block.number + 1);

        uint256 usdcBalanceOfIdleTokenBefore = tokenUsdc.balanceOf(address(idleToken));
        uint256 idleTokenBalanceOfStrategyBefore = idleToken.balanceOf(address(idleStrategy));

        // act
        slippages = new uint256[](2);
        slippages[0] = 3;
        slippages[1] = 1;
        idleStrategy.exposed_emergencyWithdrawImpl(slippages, emergencyWithdrawalRecipient);

        // assert
        uint256 idleTokenRedeemedExpected = idleTokenBalanceOfStrategyBefore;
        uint256 usdcTokenWithdrawnExpected =
            idleTokenRedeemedExpected * idleToken.tokenPriceWithFee(address(this)) / idleStrategy.oneShare();
        uint256 usdcBalanceOfEmergencyWithdrawalRecipient = tokenUsdc.balanceOf(emergencyWithdrawalRecipient);
        uint256 usdcBalanceOfIdleTokenAfter = tokenUsdc.balanceOf(address(idleToken));
        uint256 idleTokenBalanceOfStrategyAfter = idleToken.balanceOf(address(idleStrategy));

        assertTrue(usdcBalanceOfEmergencyWithdrawalRecipient > 0);
        assertEq(usdcBalanceOfEmergencyWithdrawalRecipient, usdcTokenWithdrawnExpected);
        assertEq(usdcBalanceOfIdleTokenBefore - usdcBalanceOfIdleTokenAfter, usdcTokenWithdrawnExpected);
        assertEq(idleTokenBalanceOfStrategyAfter, 0);
    }

    function test_getProtocolRewards() public {
        // arrange
        address[] memory rewardTokens = idleToken.getGovTokens();

        uint256 toDeposit = 1000 * tokenUsdcMultiplier;
        deal(address(tokenUsdc), address(idleStrategy), toDeposit, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        idleStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // - advance block number to gather rewards for reward tokens 0 and 2
        vm.roll(block.number + 200000); // ~1 month
        // - mint some reward tokens 1
        deal(
            rewardTokens[1],
            address(idleToken),
            IERC20Metadata(rewardTokens[1]).balanceOf(address(idleToken))
                + 1_000 * 10 ** IERC20Metadata(rewardTokens[1]).decimals()
        );

        // act
        vm.startPrank(address(0), address(0));
        (address[] memory rewardAddresses, uint256[] memory rewardAmounts) = idleStrategy.getProtocolRewards();
        vm.stopPrank();

        // assert
        assertEq(rewardAddresses, rewardTokens);
        assertEq(rewardAmounts.length, rewardAddresses.length);
        assertEq(rewardAmounts, Arrays.toArray(6008767417759680, 84903624193661186, 312239863552643167));
    }

    function test_compound() public {
        // arrange
        address[] memory rewardTokens = idleToken.getGovTokens();

        priceFeedManager.setExchangeRate(rewardTokens[0], USD_DECIMALS_MULTIPLIER * 50); // COMP
        priceFeedManager.setExchangeRate(rewardTokens[1], USD_DECIMALS_MULTIPLIER * 80); // stkAAVE
        priceFeedManager.setExchangeRate(rewardTokens[2], USD_DECIMALS_MULTIPLIER * 4 / 10); // IDLE

        MockExchange[] memory exchanges = new MockExchange[](rewardTokens.length);
        for (uint256 i; i < rewardTokens.length; ++i) {
            exchanges[i] = new MockExchange(IERC20(rewardTokens[i]), tokenUsdc, priceFeedManager);

            deal(
                rewardTokens[i],
                address(exchanges[i]),
                1_000_000 * 10 ** IERC20Metadata(rewardTokens[i]).decimals(),
                false
            );
            deal(address(tokenUsdc), address(exchanges[i]), 1_000_000 * tokenUsdcMultiplier, true);
        }
        swapper.updateExchangeAllowlist(
            Arrays.toArray(address(exchanges[0]), address(exchanges[1]), address(exchanges[2])),
            Arrays.toArray(true, true, true)
        );

        uint256 toDeposit = 1000 * tokenUsdcMultiplier;
        deal(address(tokenUsdc), address(idleStrategy), toDeposit, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        idleStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // - advance block number to gather rewards for reward tokens 0 and 2
        vm.roll(block.number + 200000); // ~1 month
        // - mint some reward tokens 1
        deal(
            rewardTokens[1],
            address(idleToken),
            IERC20Metadata(rewardTokens[1]).balanceOf(address(idleToken))
                + 1_000 * 10 ** IERC20Metadata(rewardTokens[1]).decimals()
        );

        uint256 idleTokenBalanceOfStrategyBefore = idleToken.balanceOf(address(idleStrategy));

        // act
        SwapInfo[] memory compoundSwapInfo = new SwapInfo[](rewardTokens.length);
        compoundSwapInfo[0] = SwapInfo({
            swapTarget: address(exchanges[0]),
            token: rewardTokens[0],
            swapCallData: abi.encodeWithSelector(
                exchanges[0].swap.selector, address(rewardTokens[0]), 6008767417759680, address(swapper)
                )
        });
        compoundSwapInfo[1] = SwapInfo({
            swapTarget: address(exchanges[1]),
            token: rewardTokens[1],
            swapCallData: abi.encodeWithSelector(
                exchanges[1].swap.selector, address(rewardTokens[1]), 84903624193661186, address(swapper)
                )
        });
        compoundSwapInfo[2] = SwapInfo({
            swapTarget: address(exchanges[2]),
            token: rewardTokens[2],
            swapCallData: abi.encodeWithSelector(
                exchanges[1].swap.selector, address(rewardTokens[2]), 312239863552643167, address(swapper)
                )
        });
        slippages = new uint256[](4);
        slippages[3] = 1;
        int256 compoundYieldPercentage = idleStrategy.exposed_compound(assetGroup, compoundSwapInfo, slippages);

        // assert
        uint256 idleTokenBalanceOfStrategyAfter = idleToken.balanceOf(address(idleStrategy));
        int256 compoundYieldPercentageExpected = int256(
            (idleTokenBalanceOfStrategyAfter - idleTokenBalanceOfStrategyBefore) * YIELD_FULL_PERCENT
                / idleTokenBalanceOfStrategyBefore
        );

        assertTrue(compoundYieldPercentage > 0);
        assertEq(compoundYieldPercentage, compoundYieldPercentageExpected);
    }

    function test_getYieldPercentage() public {
        // arrange
        uint256 toDeposit = 1000 * tokenUsdcMultiplier;
        deal(address(tokenUsdc), address(idleStrategy), toDeposit, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        idleStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        idleStrategy.exposed_mint(100);
        // - advance block number due to reentrancy check on Idle
        vm.roll(block.number + 1);

        // - mint 1_000_000 USDC to idleToken as a yield, which is about 1/10 of current assets held
        deal(address(tokenUsdc), address(idleToken), 1_000_000 * tokenUsdcMultiplier, true);

        // act
        int256 yieldPercentage = idleStrategy.exposed_getYieldPercentage(0);

        // assert
        slippages[0] = 1;
        idleStrategy.exposed_redeemFromProtocol(assetGroup, 100, slippages);

        uint256 calculatedYield = toDeposit * uint256(yieldPercentage) / YIELD_FULL_PERCENT;
        uint256 actualYield = tokenUsdc.balanceOf(address(idleStrategy)) - toDeposit;

        assertTrue(actualYield > 0);
        assertEq(actualYield, calculatedYield);
    }

    function test_getUsdWorth() public {
        // arrange
        uint256 toDeposit = 1000 * tokenUsdcMultiplier;
        deal(address(tokenUsdc), address(idleStrategy), toDeposit, true);

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        idleStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // act
        uint256 usdWorth = idleStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertApproxEqRel(usdWorth, priceFeedManager.assetToUsd(address(tokenUsdc), toDeposit), 1e15); // to 1 permil
    }
}

// Exposes protocol-specific functions for unit-testing.
contract IdleStrategyHarness is IdleStrategy, StrategyHarness {
    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, ISwapper swapper_)
        IdleStrategy(assetGroupRegistry_, accessControl_, swapper_)
    {}
}
