// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../../src/access/SpoolAccessControl.sol";
import "../../../../src/external/interfaces/weth/IWETH9.sol";
import "../../../../src/interfaces/Constants.sol";
import "../../../../src/libraries/SpoolUtils.sol";
import "../../../../src/managers/AssetGroupRegistry.sol";
import "../../../../src/strategies/arbitrum/helpers/GammaCamelotRewards.sol";
import "../../../../src/strategies/arbitrum/GammaCamelotStrategy.sol";
import "../../../external/interfaces/IUSDC.sol";
import "../../../external/interfaces/ISwapRouter.sol";
import "../../../fixtures/TestFixture.sol";
import "../../../libraries/Arrays.sol";
import "../../../libraries/Constants.sol";
import "../../../mocks/MockExchange.sol";
import "../../ForkTestFixture.sol";
import "../../StrategyHarness.sol";
import "../ArbitrumForkConstants.sol";

contract GammaCamelotStrategyTest is TestFixture, ForkTestFixture {
    using stdStorage for StdStorage;

    IERC20Metadata private tokenWeth;
    IERC20Metadata private tokenUsdc;
    uint256 tokenWethMultiplier;
    uint256 tokenUsdcMultiplier;
    uint24 public poolFee = 100; // 0.01% DAI/USDC pool - 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168

    IHypervisor public pool;
    INitroPool public nitroPool;
    IERC20 public underlyingPool;
    ISwapRouter public router;

    GammaCamelotStrategyHarness private gammaCamelotStrategy;
    GammaCamelotRewards private rewards;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    uint256 toDepositWeth;
    uint256 toDepositUsdc;

    function setUp() public {
        setUpForkTestFixtureArbitrum();
        vm.selectFork(mainnetForkId);
        setUpBase();

        tokenWeth = IERC20Metadata(WETH_ARB);
        tokenUsdc = IERC20Metadata(USDC_ARB);
        tokenWethMultiplier = 10 ** tokenWeth.decimals();
        tokenUsdcMultiplier = 10 ** tokenUsdc.decimals();

        priceFeedManager.setExchangeRate(address(tokenWeth), USD_DECIMALS_MULTIPLIER * 3891);
        priceFeedManager.setExchangeRate(address(tokenUsdc), USD_DECIMALS_MULTIPLIER);

        assetGroup = Arrays.toArray(address(tokenWeth), address(tokenUsdc));
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        assetGroupExchangeRates = SpoolUtils.getExchangeRates(assetGroup, priceFeedManager);

        pool = IHypervisor(HYPERVISOR);
        nitroPool = INitroPool(NITRO_POOL);
        underlyingPool = IERC20(pool.pool());
        router = ISwapRouter(CAMELOT_V3_ROUTER);

        rewards = new GammaCamelotRewards(accessControl);
        gammaCamelotStrategy = new GammaCamelotStrategyHarness(
            assetGroupRegistry,
            accessControl,
            swapper,
            rewards
        );

        vm.prank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(gammaCamelotStrategy));
    }

    // to include initialize in coverage
    modifier initializer() {
        _initialize();
        _;
    }

    function _initialize() private {
        gammaCamelotStrategy.initialize("gamma-camelot-strategy", assetGroupId, pool, nitroPool);
        rewards.initialize(pool, nitroPool, gammaCamelotStrategy, true);
    }

    function _deal(address token, address to, uint256 amount) private {
        if (token == WETH_ARB) {
            deal(to, amount);
            vm.prank(to);
            IWETH9(token).deposit{value: amount}();
        } else if (token == USDC_ARB) {
            vm.prank(IUSDC(token).masterMinter());
            IUSDC(token).configureMinter(address(this), type(uint256).max);
            IUSDC(token).mint(to, amount);
        } else {
            deal(token, to, amount, true);
        }
    }

    function _deposit() private returns (uint256, uint256) {
        // arrange
        uint256[] memory _assetRatio = gammaCamelotStrategy.assetRatio();
        toDepositWeth = _assetRatio[0] / 100;
        toDepositUsdc = _assetRatio[1] / 100;
        _deal(address(tokenWeth), address(gammaCamelotStrategy), toDepositWeth);
        _deal(address(tokenUsdc), address(gammaCamelotStrategy), toDepositUsdc);

        uint256 wethBalanceOfPoolBefore = tokenWeth.balanceOf(address(underlyingPool));
        uint256 usdcBalanceOfPoolBefore = tokenUsdc.balanceOf(address(underlyingPool));

        // act
        uint256[] memory slippages = new uint256[](7);

        gammaCamelotStrategy.exposed_depositToProtocol(
            assetGroup, Arrays.toArray(toDepositWeth, toDepositUsdc), slippages
        );

        return (wethBalanceOfPoolBefore, usdcBalanceOfPoolBefore);
    }

    function test_setup_checks() public {
        address[] memory bad_assetGroup = Arrays.toArray(address(1), address(tokenWeth), address(tokenUsdc));
        assetGroupRegistry.allowTokenBatch(bad_assetGroup);
        uint256 bad_assetGroupId = assetGroupRegistry.registerAssetGroup(bad_assetGroup);

        vm.expectRevert(abi.encodeWithSelector(InvalidAssetGroup.selector, bad_assetGroupId));
        gammaCamelotStrategy.initialize("gamma-camelot-strategy", bad_assetGroupId, pool, nitroPool);
    }

    function test_assetRatio() public initializer {
        // act
        uint256[] memory assetRatio = gammaCamelotStrategy.assetRatio();

        // assert
        uint256[] memory expectedAssetRatio = new uint256[](2);
        (expectedAssetRatio[0], expectedAssetRatio[1]) = pool.getTotalAmounts();

        for (uint256 i; i < 2; ++i) {
            assertEq(assetRatio[i], expectedAssetRatio[i]);
        }
    }

    function test_getYieldPercentage() public initializer {
        // Executes large swaps back and forth, which will accumulate fees to be collected.
        ISwapRouter.ExactInputParams memory params;
        uint256 toSwapWeth = 1000 * tokenWethMultiplier;
        _deal(address(tokenWeth), address(this), toSwapWeth);
        tokenWeth.approve(address(router), toSwapWeth);
        params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(address(tokenWeth), address(tokenUsdc)),
            recipient: address(this),
            deadline: block.timestamp + 1,
            amountIn: toSwapWeth,
            amountOutMinimum: 0
        });
        router.exactInput(params);

        uint256 toSwapUsdc = 1000 * 3891 * tokenUsdcMultiplier;
        _deal(address(tokenUsdc), address(this), toSwapUsdc);
        tokenUsdc.approve(address(router), toSwapUsdc);
        params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(address(tokenUsdc), address(tokenWeth)),
            recipient: address(this),
            deadline: block.timestamp + 1,
            amountIn: toSwapUsdc,
            amountOutMinimum: 0
        });
        router.exactInput(params);

        // compound the fees into the position from the owner
        uint256[4] memory minAmounts;
        address poolOwner = pool.owner();
        vm.prank(poolOwner);
        pool.compound(minAmounts);

        // act
        int256 yieldPercentage = gammaCamelotStrategy.exposed_getYieldPercentage(0);
        assertTrue(yieldPercentage > 0);
    }

    function test_depositToProtocol() public initializer {
        // arrange
        (uint256 wethBalanceOfPoolBefore, uint256 usdcBalanceOfPoolBefore) = _deposit();

        // assert
        uint256 wethBalanceOfPoolAfter = tokenWeth.balanceOf(address(underlyingPool));
        uint256 usdcBalanceOfPoolAfter = tokenUsdc.balanceOf(address(underlyingPool));
        uint256 strategyPoolBalance = gammaCamelotStrategy.getPoolBalance();

        assertGt(wethBalanceOfPoolAfter, wethBalanceOfPoolBefore);
        assertGt(usdcBalanceOfPoolAfter, usdcBalanceOfPoolBefore);
        assertGt(strategyPoolBalance, 0);
    }

    function test_redeemFromProtocol() public initializer {
        // need to deposit into the protocol
        _deposit();

        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        gammaCamelotStrategy.exposed_mint(100);

        uint256 wethBalanceOfPoolBefore = tokenWeth.balanceOf(address(underlyingPool));
        uint256 usdcBalanceOfPoolBefore = tokenUsdc.balanceOf(address(underlyingPool));
        uint256 strategyPoolBalanceBefore = gammaCamelotStrategy.getPoolBalance();

        // act
        uint256[] memory slippages = new uint256[](7);
        slippages[0] = 1;

        gammaCamelotStrategy.exposed_redeemFromProtocol(assetGroup, 60, slippages);

        // assert
        uint256 wethBalanceOfPoolAfter = tokenWeth.balanceOf(address(underlyingPool));
        uint256 usdcBalanceOfPoolAfter = tokenUsdc.balanceOf(address(underlyingPool));

        uint256 wethBalanceOfStrategy = tokenWeth.balanceOf(address(gammaCamelotStrategy));
        uint256 usdcBalanceOfStrategy = tokenUsdc.balanceOf(address(gammaCamelotStrategy));
        uint256 strategyPoolBalanceAfter = gammaCamelotStrategy.getPoolBalance();

        uint256 strategyPoolBalanceExpected = strategyPoolBalanceBefore * 40 / 100;

        assertApproxEqAbs(strategyPoolBalanceAfter, strategyPoolBalanceExpected, 10);
        assertLt(wethBalanceOfPoolAfter, wethBalanceOfPoolBefore);
        assertLt(usdcBalanceOfPoolAfter, usdcBalanceOfPoolBefore);

        assertApproxEqRel(wethBalanceOfStrategy, wethBalanceOfPoolBefore - wethBalanceOfPoolAfter, 5e15); // .5%
        assertApproxEqRel(usdcBalanceOfStrategy, usdcBalanceOfPoolBefore - usdcBalanceOfPoolAfter, 5e15); // .5%
    }

    function test_emergencyWithdrawImpl() public initializer {
        // arrange
        _deposit();

        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        gammaCamelotStrategy.exposed_mint(100);

        uint256 wethBalanceOfPoolBefore = tokenWeth.balanceOf(address(underlyingPool));
        uint256 usdcBalanceOfPoolBefore = tokenUsdc.balanceOf(address(underlyingPool));

        // act
        uint256[] memory slippages = new uint256[](3);
        slippages[0] = 3;

        gammaCamelotStrategy.exposed_emergencyWithdrawImpl(slippages, emergencyWithdrawalRecipient);

        // assert
        uint256 wethBalanceOfPoolAfter = tokenWeth.balanceOf(address(underlyingPool));
        uint256 usdcBalanceOfPoolAfter = tokenUsdc.balanceOf(address(underlyingPool));
        uint256 wethBalanceOfEmergencyWithdrawalRecipient = tokenWeth.balanceOf(address(emergencyWithdrawalRecipient));
        uint256 usdcBalanceOfEmergencyWithdrawalRecipient = tokenUsdc.balanceOf(address(emergencyWithdrawalRecipient));
        uint256 strategyPoolBalanceAfter = gammaCamelotStrategy.getPoolBalance();

        assertEq(strategyPoolBalanceAfter, 0);
        assertLt(wethBalanceOfPoolAfter, wethBalanceOfPoolBefore);
        assertLt(usdcBalanceOfPoolAfter, usdcBalanceOfPoolBefore);
        assertApproxEqRel(wethBalanceOfEmergencyWithdrawalRecipient, toDepositWeth, 1e13); // 0.001%
        assertApproxEqRel(usdcBalanceOfEmergencyWithdrawalRecipient, toDepositUsdc, 1e13); // 0.001%
    }

    function test_getProtocolRewards() public initializer {
        // arrange
        _deposit();

        // act
        // Executes a large swap, which will accumulate fees to be collected.
        uint256 toSwapWeth = 1000 * tokenWethMultiplier;
        _deal(address(tokenWeth), address(this), toSwapWeth);
        tokenWeth.approve(address(router), toSwapWeth);
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(address(tokenWeth), address(tokenUsdc)),
            recipient: address(this),
            deadline: block.timestamp + 1,
            amountIn: toSwapWeth,
            amountOutMinimum: 0
        });
        router.exactInput(params);

        // push forward time + block number
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + (365 days / 12));

        // act
        vm.prank(address(0), address(0));
        (address[] memory rewardAddresses, uint256[] memory rewardAmounts) = gammaCamelotStrategy.getProtocolRewards();

        // assert
        assertEq(rewardAddresses.length, 2);
        assertEq(rewardAddresses.length, rewardAmounts.length);
        for (uint256 i = 0; i < rewardAmounts.length; i++) {
            assertGt(rewardAmounts[i], 0);
        }
    }

    function test_compound() public initializer {
        // arrange
        // 4 exchanges: GRAIL-WETH, GRAIL-USDC, ARB-WETH, ARB-USDC
        address[] memory underlyingTokens = gammaCamelotStrategy.assets();
        MockExchange[] memory exchanges = new MockExchange[](4);
        for (uint256 i = 0; i < exchanges.length; i++) {
            IERC20Metadata rewardToken = IERC20Metadata(rewards.baseRewardTokens(i / 2));
            IERC20Metadata underlyingToken = IERC20Metadata(underlyingTokens[i % 2]);
            exchanges[i] = new MockExchange(rewardToken, underlyingToken, priceFeedManager);
            _deal(address(rewardToken), address(exchanges[i]), 1_000_000 * (10 ** rewardToken.decimals()));
            _deal(address(underlyingToken), address(exchanges[i]), 1_000_000 * (10 ** underlyingToken.decimals()));
            swapper.updateExchangeAllowlist(Arrays.toArray(address(exchanges[i])), Arrays.toArray(true));

            priceFeedManager.setExchangeRate(address(rewardToken), USD_DECIMALS_MULTIPLIER * 95 / 100);
        }

        // add deposit
        _deposit();

        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        gammaCamelotStrategy.exposed_mint(100);

        // act
        // Executes a large swap, which will accumulate fees to be collected.
        uint256 toSwapWeth = 1000 * tokenWethMultiplier;
        _deal(address(tokenWeth), address(this), toSwapWeth);
        tokenWeth.approve(address(router), toSwapWeth);
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(address(tokenWeth), address(tokenUsdc)),
            recipient: address(this),
            deadline: block.timestamp + 100,
            amountIn: toSwapWeth,
            amountOutMinimum: 0
        });
        router.exactInput(params);

        // push forward time + block number
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + (365 days / 12));

        // sets up rewards to reflect asset ratio
        uint256[] memory rewardAmountsReceived = new uint256[](4);
        rewardAmountsReceived[0] = 4809926952281283;
        rewardAmountsReceived[1] = 1334758691716883;
        rewardAmountsReceived[2] = 177555217558945675214;
        rewardAmountsReceived[3] = 49271719144109260161;

        uint256 lpTokensOfStrategyBefore = gammaCamelotStrategy.getPoolBalance();

        // act
        SwapInfo[] memory compoundSwapInfo = new SwapInfo[](4);
        for (uint256 i = 0; i < exchanges.length; i++) {
            address rewardToken = rewards.baseRewardTokens(i / 2);
            uint256 rewardAmountReceived = rewardAmountsReceived[i];
            compoundSwapInfo[i] = SwapInfo({
                swapTarget: address(exchanges[i]),
                token: rewardToken,
                swapCallData: abi.encodeWithSelector(
                    exchanges[i].swap.selector, rewardToken, rewardAmountReceived, address(swapper)
                    )
            });
        }

        uint256[] memory slippages = new uint256[](6);
        int256 compoundYieldPercentage = gammaCamelotStrategy.exposed_compound(assetGroup, compoundSwapInfo, slippages);

        // assert
        uint256 lpTokensOfStrategyAfter = gammaCamelotStrategy.getPoolBalance();
        int256 compoundYieldPercentageExpected =
            int256(YIELD_FULL_PERCENT * (lpTokensOfStrategyAfter - lpTokensOfStrategyBefore) / lpTokensOfStrategyBefore);

        assertGt(compoundYieldPercentage, 0);
        assertEq(compoundYieldPercentage, compoundYieldPercentageExpected);
    }

    function test_getUsdWorth() public initializer {
        // arrange
        _deposit();

        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        gammaCamelotStrategy.exposed_mint(100);

        // act
        uint256 usdWorth = gammaCamelotStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        uint256 expectedValue;
        expectedValue += priceFeedManager.assetToUsd(address(tokenWeth), toDepositWeth);
        expectedValue += priceFeedManager.assetToUsd(address(tokenUsdc), toDepositUsdc);

        assertApproxEqRel(usdWorth, expectedValue, 1e15); // to 1 permil
    }
}

// Exposes protocol-specific functions for unit-testing.
contract GammaCamelotStrategyHarness is GammaCamelotStrategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        IGammaCamelotRewards rewards_
    ) GammaCamelotStrategy(assetGroupRegistry_, accessControl_, swapper_, rewards_) {}
}
