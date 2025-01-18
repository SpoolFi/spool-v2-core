// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../src/external/interfaces/strategies/aave/IStakedGho.sol";
import "../../../src/strategies/AaveGhoStakingStrategy.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../ForkTestFixture.sol";
import {StrategyHarnessNonAtomic} from "../StrategyHarness.sol";
import "../../mocks/MockExchange.sol";

contract AaveGhoStakingStrategyUsdcTest is TestFixture, ForkTestFixture {
    IERC20Metadata tokenUsdc;
    IERC20Metadata tokenGho;
    IERC20Metadata tokenAave;
    IStakedGho stakedGho;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    AaveGhoStakingStrategyHarness aaveGhoStakingStrategy;

    MockExchange usdcGhoExchange;
    MockExchange usdcAaveExchange;

    address actor = address(0xacacacacac);

    function setUpForkTestFixture() internal override {
        mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK_EXTENDED_5);
    }

    function setUp() public {
        setUpForkTestFixture();
        vm.selectFork(mainnetForkId);
        setUpBase();

        tokenUsdc = IERC20Metadata(USDC);
        tokenGho = IERC20Metadata(GHO);
        tokenAave = IERC20Metadata(AAVE);
        stakedGho = IStakedGho(STAKED_GHO);

        priceFeedManager.setExchangeRate(address(tokenUsdc), USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(tokenGho), USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(tokenAave), 100 * USD_DECIMALS_MULTIPLIER);

        assetGroup = Arrays.toArray(address(tokenUsdc));
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        assetGroupExchangeRates = SpoolUtils.getExchangeRates(assetGroup, priceFeedManager);

        aaveGhoStakingStrategy = new AaveGhoStakingStrategyHarness(
            assetGroupRegistry,
            accessControl,
            tokenGho,
            stakedGho,
            priceFeedManager,
            swapper
        );
        aaveGhoStakingStrategy.initialize("AaveGhoStakingStrategyUsdc", assetGroupId);
        vm.startPrank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(aaveGhoStakingStrategy));
        vm.stopPrank();

        usdcGhoExchange = new MockExchange(tokenUsdc, tokenGho, priceFeedManager);
        usdcAaveExchange = new MockExchange(tokenUsdc, tokenAave, priceFeedManager);
        swapper.updateExchangeAllowlist(
            Arrays.toArray(address(usdcGhoExchange), address(usdcAaveExchange)), Arrays.toArray(true, true)
        );

        _dealUsdc(address(usdcGhoExchange), 1_000_000 * 10 ** tokenUsdc.decimals());
        deal(address(tokenGho), address(usdcGhoExchange), 1_000_000 * 10 ** tokenGho.decimals(), false);
        _dealUsdc(address(usdcAaveExchange), 1_000_000 * 10 ** tokenUsdc.decimals());
        _dealAave(address(usdcAaveExchange), 10_000 * 10 ** tokenAave.decimals());
    }

    function _dealUsdc(address to, uint256 amount) internal {
        vm.startPrank(USDC_WHALE);
        tokenUsdc.transfer(to, amount);
        vm.stopPrank();
    }

    function _dealAave(address to, uint256 amount) internal {
        vm.startPrank(address(0x4da27a545c0c5B758a6BA100e3a049001de870f5));
        tokenAave.transfer(to, amount);
        vm.stopPrank();
    }

    function _encodeSwapToSlippages(MockExchange exchange, bytes memory logData)
        internal
        view
        returns (uint256[] memory slippages)
    {
        (address tokenIn,, uint256 toSwap) = abi.decode(logData, (address, address, uint256));
        bytes memory swapCallData = abi.encodeCall(exchange.swap, (tokenIn, toSwap, address(swapper)));
        uint256[] memory encodedSwapCallData = BytesUint256Lib.encode(swapCallData);

        slippages = new uint256[](5 + encodedSwapCallData.length);
        slippages[3] = uint256(uint160(address(exchange)));
        slippages[4] = swapCallData.length;
        for (uint256 i; i < encodedSwapCallData.length; ++i) {
            slippages[5 + i] = encodedSwapCallData[i];
        }
    }

    function _encodeSwapToBytes(MockExchange exchange, bytes memory logData)
        internal
        view
        returns (bytes memory data)
    {
        (address tokenIn,, uint256 toSwap) = abi.decode(logData, (address, address, uint256));
        bytes memory swapCallData = abi.encodeCall(exchange.swap, (tokenIn, toSwap, address(swapper)));

        data = abi.encode(address(exchange), swapCallData);
    }

    function test_strategyInteraction() public {
        vm.recordLogs();

        uint256 USDC_DECIMALS_MULTIPLIER = 10 ** tokenUsdc.decimals();
        uint256 STAKED_GHO_DECIMALS_MULTIPLIER = 10 ** stakedGho.decimals();

        {
            // deposit 1,000 USDC
            _dealUsdc(address(aaveGhoStakingStrategy), 1_000 * USDC_DECIMALS_MULTIPLIER);

            // - get data for the swap
            uint256 snapshotId = vm.snapshot();
            vm.startPrank(address(0), address(0));
            vm.getRecordedLogs();

            uint256[] memory slippages = new uint256[](4);
            slippages[0] = 0; // dhw with deposit selector
            slippages[3] = 1; // swap data -> marker for swap estimation
            aaveGhoStakingStrategy.exposed_initializeDepositToProtocol(
                assetGroup, Arrays.toArray(1_000 * USDC_DECIMALS_MULTIPLIER), slippages
            );

            Vm.Log[] memory logs = vm.getRecordedLogs();
            vm.stopPrank();
            vm.revertTo(snapshotId);

            assertEq(logs.length, 1);
            assertEq(logs[0].topics.length, 1);
            assertEq(logs[0].topics[0], keccak256("SwapEstimation(address,address,uint256)"));

            slippages = _encodeSwapToSlippages(usdcGhoExchange, logs[0].data);
            slippages[0] = 0; // dhw with deposit selector

            // - do the actual deposit
            aaveGhoStakingStrategy.exposed_initializeDepositToProtocol(
                assetGroup, Arrays.toArray(1_000 * USDC_DECIMALS_MULTIPLIER), slippages
            );

            // - assert state
            assertEq(tokenUsdc.balanceOf(address(aaveGhoStakingStrategy)), 0);
            assertEq(tokenGho.balanceOf(address(aaveGhoStakingStrategy)), 0);
            assertEq(stakedGho.balanceOf(address(aaveGhoStakingStrategy)), 1_000 * STAKED_GHO_DECIMALS_MULTIPLIER);

            // - bookkeeping
            aaveGhoStakingStrategy.exposed_mint(100);

            // - check underlying asset amounts
            uint256[] memory underlyingAssetAmounts = aaveGhoStakingStrategy.getUnderlyingAssetAmounts();
            assertEq(underlyingAssetAmounts.length, 1);
            assertEq(underlyingAssetAmounts[0], 1_000 * USDC_DECIMALS_MULTIPLIER);
        }

        {
            // withdrawal 1
            // - initialize withdrawal
            uint256[] memory slippages = new uint256[](1);
            slippages[0] = 0; // dhw with withdrawal selector
            aaveGhoStakingStrategy.exposed_initializeWithdrawalFromProtocol(assetGroup, 50, Arrays.toArray(1));

            // - assert state - nothing should change
            assertEq(tokenUsdc.balanceOf(address(aaveGhoStakingStrategy)), 0);
            assertEq(tokenGho.balanceOf(address(aaveGhoStakingStrategy)), 0);
            assertEq(stakedGho.balanceOf(address(aaveGhoStakingStrategy)), 1_000 * STAKED_GHO_DECIMALS_MULTIPLIER);

            // - wait 21 days
            vm.roll(block.number + 100);
            skip(21 * 24 * 60 * 60);

            // - get data for the swap
            uint256 snapshotId = vm.snapshot();
            vm.startPrank(address(0), address(0));
            vm.getRecordedLogs();

            bytes memory continuationData = abi.encode(address(0), new bytes(0));
            aaveGhoStakingStrategy.exposed_continueWithdrawalFromProtocol(assetGroup, continuationData);

            Vm.Log[] memory logs = vm.getRecordedLogs();
            vm.stopPrank();
            vm.revertTo(snapshotId);

            assertGt(logs.length, 0);
            assertEq(logs[logs.length - 1].topics.length, 1);
            assertEq(logs[logs.length - 1].topics[0], keccak256("SwapEstimation(address,address,uint256)"));

            continuationData = _encodeSwapToBytes(usdcGhoExchange, logs[logs.length - 1].data);

            // - do the actual withdrawal continuation
            aaveGhoStakingStrategy.exposed_continueWithdrawalFromProtocol(assetGroup, continuationData);

            // - assert state
            assertEq(tokenUsdc.balanceOf(address(aaveGhoStakingStrategy)), 500 * USDC_DECIMALS_MULTIPLIER);
            assertEq(tokenGho.balanceOf(address(aaveGhoStakingStrategy)), 0);
            assertEq(stakedGho.balanceOf(address(aaveGhoStakingStrategy)), 500 * STAKED_GHO_DECIMALS_MULTIPLIER);

            // - bookkeeping
            aaveGhoStakingStrategy.exposed_burn(50);
        }

        {
            // withdrawal 2
            // - wait 0.5 days
            vm.roll(block.number + 100);
            skip(0.5 * 24 * 60 * 60);

            // - we are still within the unstake window from last withdrawal
            // - withdrawal should be atomic now

            // - get data for the swap
            uint256 snapshotId = vm.snapshot();
            vm.startPrank(address(0), address(0));
            vm.getRecordedLogs();

            uint256[] memory slippages = new uint256[](4);
            slippages[0] = 1; // dhw with withdrawal selector
            slippages[3] = 1; // swap data -> marker for swap estimation
            aaveGhoStakingStrategy.exposed_initializeWithdrawalFromProtocol(assetGroup, 25, slippages);

            Vm.Log[] memory logs = vm.getRecordedLogs();
            vm.stopPrank();
            vm.revertTo(snapshotId);

            assertGt(logs.length, 0);
            assertEq(logs[logs.length - 1].topics.length, 1);
            assertEq(logs[logs.length - 1].topics[0], keccak256("SwapEstimation(address,address,uint256)"));

            slippages = _encodeSwapToSlippages(usdcGhoExchange, logs[logs.length - 1].data);
            slippages[0] = 1; // dhw with withdrawal selector

            // - do the actual withdrawal
            aaveGhoStakingStrategy.exposed_initializeWithdrawalFromProtocol(assetGroup, 25, slippages);

            // - assert state
            assertEq(tokenUsdc.balanceOf(address(aaveGhoStakingStrategy)), 750 * USDC_DECIMALS_MULTIPLIER);
            assertEq(tokenGho.balanceOf(address(aaveGhoStakingStrategy)), 0);
            assertEq(stakedGho.balanceOf(address(aaveGhoStakingStrategy)), 250 * STAKED_GHO_DECIMALS_MULTIPLIER);

            // - bookkeeping
            aaveGhoStakingStrategy.exposed_burn(25);
        }

        {
            // check rewards and start compound
            // - check rewards
            (address[] memory rewardTokens, uint256[] memory rewardAmounts) =
                aaveGhoStakingStrategy.exposed_getProtocolRewardsInternal();

            assertEq(rewardTokens[0], address(tokenAave));
            assertEq(rewardAmounts[0], 28206822345662000);

            // - start compound
            SwapInfo[] memory compoundSwapInfo = new SwapInfo[](1);
            compoundSwapInfo[0] = SwapInfo({
                swapTarget: address(usdcAaveExchange),
                token: address(tokenAave),
                swapCallData: abi.encodeCall(
                    usdcAaveExchange.swap, (address(tokenAave), 28206822345662000, address(swapper))
                    )
            });

            aaveGhoStakingStrategy.exposed_prepareCompoundImpl(assetGroup, compoundSwapInfo);

            (rewardTokens, rewardAmounts) = aaveGhoStakingStrategy.exposed_getProtocolRewardsInternal();

            assertEq(rewardAmounts[0], 0);
            assertEq(tokenAave.balanceOf(address(aaveGhoStakingStrategy)), 0);
            assertEq(tokenUsdc.balanceOf(address(aaveGhoStakingStrategy)), 750_000000 + 2_820682);
        }

        {
            // check yield and usd worth
            // - base yield should be 0 under normal circumstances
            int256 baseYieldPercentage = aaveGhoStakingStrategy.exposed_getYieldPercentage(0);
            uint256 usdWorth = aaveGhoStakingStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

            assertEq(baseYieldPercentage, 0);
            assertEq(usdWorth, 250 * USD_DECIMALS_MULTIPLIER);

            // - simulate a refund of slashed funds, since it is easier than slashing funds
            //   - this will give a positive yield
            //   - slashing would give a negative yield
            address refunder = address(0xefd);
            uint256 refundAmount = stakedGho.totalSupply();
            deal(address(tokenGho), refunder, refundAmount, false);
            vm.startPrank(refunder);
            tokenGho.approve(address(stakedGho), refundAmount);
            stakedGho.returnFunds(refundAmount);
            vm.stopPrank();

            // - base yield should be 100% now
            baseYieldPercentage = aaveGhoStakingStrategy.exposed_getYieldPercentage(0);
            usdWorth = aaveGhoStakingStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

            assertEq(baseYieldPercentage, YIELD_FULL_PERCENT_INT);
            assertEq(usdWorth, 500 * USD_DECIMALS_MULTIPLIER);
        }
    }
}

contract AaveGhoStakingStrategyHarness is AaveGhoStakingStrategy, StrategyHarnessNonAtomic {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IERC20Metadata gho_,
        IStakedGho stakedGho_,
        IUsdPriceFeedManager priceFeedManager_,
        ISwapper swapper_
    ) AaveGhoStakingStrategy(assetGroupRegistry_, accessControl_, gho_, stakedGho_, priceFeedManager_, swapper_) {}
}
