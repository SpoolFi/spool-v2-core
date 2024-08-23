// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../src/external/interfaces/weth/IWETH9.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/strategies/GearboxV3SwapStrategy.sol";
import "../../fixtures/TestFixture.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../mocks/MockExchange.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";
import "../EthereumForkConstants.sol";

contract GearboxV3SwapStrategyGhoTest is TestFixture, ForkTestFixture {
    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    GearboxV3SwapStrategyHarness gearboxV3SwapStrategy;
    IERC20Metadata poolToken;
    MockExchange pool_underlying_Exchange;

    bytes eventSig = "SwapEstimation(address,address,uint256)";
    uint256 toDepositInPoolToken;

    // ******* Underlying specific constants **************
    IERC20Metadata underlyingToken = IERC20Metadata(USDC);
    IFarmingPool sdToken = IFarmingPool(SDGHO_TOKEN);
    uint256 toDeposit = 100000 * 10 ** 6;
    uint256 rewardTokenAmount = 7344302374703652272138;
    uint256 underlyingPriceUSD = 1001;
    // ****************************************************

    function setUpForkTestFixture() internal override {
        mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK_EXTENDED_5);
    }

    function setUp() public {
        setUpForkTestFixture();
        vm.selectFork(mainnetForkId);
        setUpBase();

        assetGroup = Arrays.toArray(address(underlyingToken));
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        gearboxV3SwapStrategy = new GearboxV3SwapStrategyHarness(
            assetGroupRegistry,
            accessControl,
            swapper,
            priceFeedManager
        );

        gearboxV3SwapStrategy.initialize("GearboxV3SwapStrategy", assetGroupId, sdToken);

        vm.prank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(gearboxV3SwapStrategy));

        _deal(address(underlyingToken), address(gearboxV3SwapStrategy), toDeposit);

        address dToken = address(gearboxV3SwapStrategy.dToken());
        poolToken = IERC20Metadata(IPoolV3(dToken).asset());
        toDepositInPoolToken = _underlyingToPoolTokenAmount(toDeposit);

        // create and deal to the exchange
        pool_underlying_Exchange = new MockExchange(poolToken, underlyingToken, priceFeedManager);
        _deal(address(poolToken), address(pool_underlying_Exchange), 1_000_000 * 10 ** poolToken.decimals());
        _deal(address(underlyingToken), address(pool_underlying_Exchange), 1_000_000 * 10 ** underlyingToken.decimals());

        swapper.updateExchangeAllowlist(Arrays.toArray(address(pool_underlying_Exchange)), Arrays.toArray(true));

        // set exchange rate 1 to 1 for easier testing
        priceFeedManager.setExchangeRate(address(underlyingToken), USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(poolToken), USD_DECIMALS_MULTIPLIER);

        assetGroupExchangeRates = SpoolUtils.getExchangeRates(Arrays.toArray(address(poolToken)), priceFeedManager);
    }

    function _deal(address token, address to, uint256 amount) private {
        if (token == USDC) {
            vm.startPrank(USDC_WHALE);
            underlyingToken.transfer(to, amount);
            vm.stopPrank();
        } else {
            deal(token, to, amount, true);
        }
    }

    function _underlyingToPoolTokenAmount(uint256 amount) private view returns (uint256) {
        // eg. if pool token has 18 decimals and underlying token has 6 decimals: convert underlying token amount to 18 decimals
        uint256 poolTokenDecimals = poolToken.decimals();
        uint256 underlyingTokenDecimals = underlyingToken.decimals();
        uint256 diff = poolTokenDecimals - underlyingTokenDecimals;
        return amount * 10 ** diff;
    }

    function _underlyingBalanceOfStrategy() private view returns (uint256) {
        uint256 balanceOfDToken = sdToken.balanceOf(address(gearboxV3SwapStrategy));
        return gearboxV3SwapStrategy.dToken().previewRedeem(balanceOfDToken);
    }

    function buildSlippages(MockExchange exchange, bytes memory data)
        internal
        view
        returns (uint256[] memory slippages)
    {
        (address tokenIn,, uint256 toSwap) = abi.decode(data, (address, address, uint256));
        bytes memory swapCallData = abi.encodeCall(exchange.swap, (tokenIn, toSwap, address(swapper)));
        uint256[] memory encodedSwapCallData = BytesUint256Lib.encode(swapCallData);
        slippages = new uint256[](2 + encodedSwapCallData.length);
        slippages[0] = uint160(address(exchange));
        slippages[1] = swapCallData.length;
        for (uint256 i; i < encodedSwapCallData.length; i++) {
            slippages[i + 2] = encodedSwapCallData[i];
        }
    }

    function _deposit() internal {
        uint256 snapshot = vm.snapshot();

        vm.startPrank(address(0), address(0));
        vm.recordLogs();
        uint256[] memory slippages = new uint256[](1);
        slippages[0] = 1;
        gearboxV3SwapStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics.length, 1);
        assertEq(entries[0].topics[0], keccak256(eventSig));
        vm.stopPrank();

        vm.revertTo(snapshot);

        gearboxV3SwapStrategy.exposed_depositToProtocol(
            assetGroup, Arrays.toArray(toDeposit), buildSlippages(pool_underlying_Exchange, entries[0].data)
        );
    }

    function _redeem(uint256 toRedeem) internal {
        uint256 snapshot = vm.snapshot();
        uint256[] memory slippages = new uint256[](1);
        slippages[0] = 1;
        vm.startPrank(address(0), address(0));
        vm.recordLogs();
        gearboxV3SwapStrategy.exposed_redeemFromProtocol(assetGroup, toRedeem, slippages);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory data;
        bytes32 sig = keccak256(eventSig);
        for (uint256 i; i < entries.length; i++) {
            if (entries[i].topics[0] == sig) {
                data = entries[i].data;
                break;
            }
        }
        vm.stopPrank();
        vm.revertTo(snapshot);
        gearboxV3SwapStrategy.exposed_redeemFromProtocol(
            assetGroup, toRedeem, buildSlippages(pool_underlying_Exchange, data)
        );
    }

    function test_depositToProtocol() public {
        _deposit();

        // assert
        // act
        uint256[] memory getUnderlyingAssetAmounts = gearboxV3SwapStrategy.getUnderlyingAssetAmounts();
        uint256 getUnderlyingAssetAmount = getUnderlyingAssetAmounts[0];
        uint256 diff = 2e15; // .2%
        assertApproxEqRel(getUnderlyingAssetAmount, toDeposit, diff);
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 mintedShares = 100;
        uint256 withdrawnShares = 60;

        // - need to deposit into the protocol
        _deposit();
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        gearboxV3SwapStrategy.exposed_mint(mintedShares);

        uint256 strategyDepositBalanceBefore = _underlyingBalanceOfStrategy();

        // act
        _redeem(withdrawnShares);

        // assert
        uint256 strategyDepositBalanceAfter = _underlyingBalanceOfStrategy();

        assertApproxEqAbs(
            strategyDepositBalanceBefore - strategyDepositBalanceAfter,
            toDepositInPoolToken * withdrawnShares / mintedShares,
            1
        );
        assertApproxEqAbs(
            strategyDepositBalanceAfter, toDepositInPoolToken * (mintedShares - withdrawnShares) / mintedShares, 1
        );
    }

    function test_emergencyWithdrawImpl() public {
        // arrange
        uint256 mintedShares = 100;

        // - need to deposit into the protocol
        _deposit();
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        gearboxV3SwapStrategy.exposed_mint(mintedShares);

        uint256 poolTokenBalanceOfDTokenBefore = poolToken.balanceOf(address(gearboxV3SwapStrategy.dToken()));

        // act
        gearboxV3SwapStrategy.exposed_emergencyWithdrawImpl(new uint256[](0), emergencyWithdrawalRecipient);

        // assert
        uint256 poolTokenBalanceOfDTokenAfter = poolToken.balanceOf(address(gearboxV3SwapStrategy.dToken()));
        uint256 poolTokenBalanceOfEmergencyWithdrawalRecipient = poolToken.balanceOf(emergencyWithdrawalRecipient);

        uint256 dTokenBalanceOfStrategy = gearboxV3SwapStrategy.dToken().balanceOf(address(gearboxV3SwapStrategy));
        uint256 sdTokenBalanceOfStrategy = sdToken.balanceOf(address(gearboxV3SwapStrategy));

        assertApproxEqAbs(poolTokenBalanceOfDTokenBefore - poolTokenBalanceOfDTokenAfter, toDepositInPoolToken, 1);
        assertApproxEqAbs(poolTokenBalanceOfEmergencyWithdrawalRecipient, toDepositInPoolToken, 1);
        assertEq(dTokenBalanceOfStrategy, 0);
        assertEq(sdTokenBalanceOfStrategy, 0);
    }

    // base yield
    function test_getYieldPercentage() public {
        // - need to deposit into the protocol
        _deposit();

        uint256 balanceOfStrategyBefore = _underlyingBalanceOfStrategy();

        // - yield is gathered over time
        vm.warp(block.timestamp + 52 weeks);

        // act
        int256 yieldPercentage = gearboxV3SwapStrategy.exposed_getYieldPercentage(0);

        // assert
        uint256 balanceOfStrategyAfter = _underlyingBalanceOfStrategy();

        uint256 calculatedYield = balanceOfStrategyBefore * uint256(yieldPercentage) / YIELD_FULL_PERCENT;
        uint256 expectedYield = balanceOfStrategyAfter - balanceOfStrategyBefore;

        assertGt(yieldPercentage, 0);
        assertApproxEqRel(calculatedYield, expectedYield, 10 ** 11);
    }

    function test_getProtocolRewards() public {
        // arrange
        IERC20 gearToken = gearboxV3SwapStrategy.gear();

        // - need to deposit into the protocol
        _deposit();

        // - mint some reward tokens by skipping blocks (should be `rewardTokenAmount` GEAR, depends on the forked block number)
        vm.warp(block.timestamp + 1 weeks);

        // act
        vm.startPrank(address(0), address(0));
        (address[] memory rewardAddresses, uint256[] memory rewardAmounts) = gearboxV3SwapStrategy.getProtocolRewards();
        vm.stopPrank();

        // assert
        assertEq(rewardAddresses.length, 1);
        assertEq(rewardAddresses[0], address(gearToken));
        assertEq(rewardAmounts.length, rewardAddresses.length);

        console.log("rewardAmounts[0]: %d", rewardAmounts[0]);
        assertEq(rewardAmounts[0], rewardTokenAmount);
    }

    function test_compound() public {
        // arrange
        IERC20 gearToken = gearboxV3SwapStrategy.gear();

        priceFeedManager.setExchangeRate(address(gearToken), USD_DECIMALS_MULTIPLIER * 50); // GEAR

        MockExchange exchange = new MockExchange(gearToken, poolToken, priceFeedManager);

        deal(
            address(gearToken),
            address(exchange),
            1_000_000 * 10 ** IERC20Metadata(address(gearToken)).decimals(),
            false
        );
        _deal(address(poolToken), address(exchange), 1_000_000 * 10 ** poolToken.decimals());

        swapper.updateExchangeAllowlist(Arrays.toArray(address(exchange)), Arrays.toArray(true));

        // - need to deposit into the protocol
        _deposit();

        // - mint some reward tokens by skipping blocks (should be `rewardTokenAmount` GEAR, depends on the forked block number)
        vm.warp(block.timestamp + 1 weeks);

        uint256 balanceOfStrategyBefore = _underlyingBalanceOfStrategy();

        // act
        SwapInfo[] memory compoundSwapInfo = new SwapInfo[](1);
        compoundSwapInfo[0] = SwapInfo({
            swapTarget: address(exchange),
            token: address(gearToken),
            swapCallData: abi.encodeCall(exchange.swap, (address(gearToken), rewardTokenAmount, address(swapper)))
        });

        uint256[] memory slippages = new uint256[](1);
        slippages[0] = 1;

        int256 compoundYieldPercentage = gearboxV3SwapStrategy.exposed_compound(assetGroup, compoundSwapInfo, slippages);

        // assert
        uint256 balanceOfStrategyAfter = _underlyingBalanceOfStrategy();

        int256 compoundYieldPercentageExpected =
            int256((balanceOfStrategyAfter - balanceOfStrategyBefore) * YIELD_FULL_PERCENT / balanceOfStrategyBefore);

        assertGt(compoundYieldPercentage, 0);
        assertApproxEqAbs(compoundYieldPercentage, compoundYieldPercentageExpected, 10);
    }

    function test_getUsdWorth() public {
        // - need to deposit into the protocol
        _deposit();

        // act
        uint256 usdWorth = gearboxV3SwapStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertApproxEqRel(usdWorth, priceFeedManager.assetToUsd(address(underlyingToken), toDeposit), 1e7);
    }
}

// Exposes protocol-specific functions for unit-testing.
contract GearboxV3SwapStrategyHarness is GearboxV3SwapStrategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        IUsdPriceFeedManager priceFeedManager_
    ) GearboxV3SwapStrategy(assetGroupRegistry_, accessControl_, swapper_, priceFeedManager_) {}
}
