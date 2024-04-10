// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/interfaces/IERC4626.sol";

import "../../../src/external/interfaces/weth/IWETH9.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/strategies/GearboxV3ERC4626.sol";
import "../../fixtures/TestFixture.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../mocks/MockExchange.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";
import "../EthereumForkConstants.sol";

contract GearboxV3ERC4626Test is TestFixture, ForkTestFixture {
    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    GearboxV3StrategyHarness gearboxV3Strategy;
    address gearboxV3StrategyWithGearImplementation;

    // ******* Underlying specific constants **************
    IERC20Metadata tokenUnderlying = IERC20Metadata(USDC);
    IFarmingPool sdToken = IFarmingPool(SDUSDC_TOKEN);
    uint256 toDeposit = 100000 * 10 ** 6;
    uint256 rewardTokenAmount = 13396529259569365546568;
    uint256 underlyingPriceUSD = 1001;

    IERC4626 dToken;

    // ****************************************************

    function setUpForkTestFixture() internal override {
        mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK_EXTENDED_1);
    }

    function setUp() public {
        setUpForkTestFixture();
        vm.selectFork(mainnetForkId);
        setUpBase();

        priceFeedManager.setExchangeRate(
            address(tokenUnderlying), (USD_DECIMALS_MULTIPLIER * underlyingPriceUSD) / 1000
        );

        assetGroup = Arrays.toArray(address(tokenUnderlying));
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        assetGroupExchangeRates = SpoolUtils.getExchangeRates(assetGroup, priceFeedManager);

        dToken = IERC4626(sdToken.stakingToken());
        gearboxV3StrategyWithGearImplementation =
            address(new GearboxV3StrategyHarness(assetGroupRegistry, accessControl, swapper, sdToken, dToken));
        gearboxV3Strategy =
            GearboxV3StrategyHarness(address(new ERC1967Proxy(gearboxV3StrategyWithGearImplementation, "")));

        gearboxV3Strategy.initialize("GearboxV3Strategy", assetGroupId);

        vm.prank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(gearboxV3Strategy));

        _deal(address(gearboxV3Strategy), toDeposit);
    }

    function _deal(address to, uint256 amount) private {
        deal(address(tokenUnderlying), to, amount, true);
    }

    function _underlyingBalanceOfStrategy() private view returns (uint256) {
        uint256 balanceOfDToken = sdToken.balanceOf(address(gearboxV3Strategy));
        return gearboxV3Strategy.vault().previewRedeem(balanceOfDToken);
    }

    function test_depositToProtocol() public {
        // arrange
        uint256 underlyingBalanceOfDTokenBefore = tokenUnderlying.balanceOf(address(gearboxV3Strategy.vault()));

        // act
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        gearboxV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // assert
        uint256 underlyingBalanceOfDTokenAfter = tokenUnderlying.balanceOf(address(gearboxV3Strategy.vault()));

        assertEq(underlyingBalanceOfDTokenAfter - underlyingBalanceOfDTokenBefore, toDeposit);
        assertApproxEqAbs(_underlyingBalanceOfStrategy(), toDeposit, 1);
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 mintedShares = 100;
        uint256 withdrawnShares = 60;

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        gearboxV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        gearboxV3Strategy.exposed_mint(mintedShares);

        uint256 strategyDepositBalanceBefore = _underlyingBalanceOfStrategy();

        // act
        slippages[0] = 1;
        gearboxV3Strategy.exposed_redeemFromProtocol(assetGroup, withdrawnShares, slippages);

        // assert
        uint256 underlyingBalanceOfStrategy = tokenUnderlying.balanceOf(address(gearboxV3Strategy));
        uint256 strategyDepositBalanceAfter = _underlyingBalanceOfStrategy();

        assertApproxEqAbs(
            strategyDepositBalanceBefore - strategyDepositBalanceAfter, (toDeposit * withdrawnShares) / mintedShares, 1
        );
        assertApproxEqAbs(underlyingBalanceOfStrategy, (toDeposit * withdrawnShares) / mintedShares, 1);
        assertApproxEqAbs(strategyDepositBalanceAfter, (toDeposit * (mintedShares - withdrawnShares)) / mintedShares, 1);
    }

    function test_emergencyWithdrawImpl() public {
        // arrange
        uint256 mintedShares = 100;

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        gearboxV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        gearboxV3Strategy.exposed_mint(mintedShares);

        uint256 underlyingBalanceOfDTokenBefore = tokenUnderlying.balanceOf(address(gearboxV3Strategy.vault()));

        // act
        slippages = new uint256[](2);
        slippages[0] = 3;
        slippages[1] = 1;
        gearboxV3Strategy.exposed_emergencyWithdrawImpl(slippages, emergencyWithdrawalRecipient);

        // assert
        uint256 underlyingBalanceOfDTokenAfter = tokenUnderlying.balanceOf(address(gearboxV3Strategy.vault()));
        uint256 underlyingBalanceOfEmergencyWithdrawalRecipient =
            tokenUnderlying.balanceOf(emergencyWithdrawalRecipient);

        uint256 dTokenBalanceOfStrategy = gearboxV3Strategy.vault().balanceOf(address(gearboxV3Strategy));
        uint256 sdTokenBalanceOfStrategy = sdToken.balanceOf(address(gearboxV3Strategy));

        assertApproxEqAbs(underlyingBalanceOfDTokenBefore - underlyingBalanceOfDTokenAfter, toDeposit, 1);
        assertApproxEqAbs(underlyingBalanceOfEmergencyWithdrawalRecipient, toDeposit, 1);
        assertEq(dTokenBalanceOfStrategy, 0);
        assertEq(sdTokenBalanceOfStrategy, 0);
    }

    // base yield
    function test_getYieldPercentage() public {
        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        gearboxV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        uint256 balanceOfStrategyBefore = _underlyingBalanceOfStrategy();

        // - yield is gathered over time
        vm.warp(block.timestamp + 52 weeks);

        // act
        int256 yieldPercentage = gearboxV3Strategy.exposed_getYieldPercentage(0);

        // assert
        uint256 balanceOfStrategyAfter = _underlyingBalanceOfStrategy();

        uint256 calculatedYield = (balanceOfStrategyBefore * uint256(yieldPercentage)) / YIELD_FULL_PERCENT;
        uint256 expectedYield = balanceOfStrategyAfter - balanceOfStrategyBefore;

        assertGt(yieldPercentage, 0);
        assertApproxEqAbs(calculatedYield, expectedYield, 10 ** (tokenUnderlying.decimals() - 3));

        // we should get what we expect
        slippages = new uint256[](2);
        slippages[0] = 3;
        slippages[1] = 1;
        gearboxV3Strategy.exposed_emergencyWithdrawImpl(slippages, address(gearboxV3Strategy));
        uint256 afterWithdraw = tokenUnderlying.balanceOf(address(gearboxV3Strategy));
        assertEq(afterWithdraw, balanceOfStrategyAfter, "3");
    }

    function test_getProtocolRewards() public {
        // arrange
        IERC20 gearToken = gearboxV3Strategy.gear();

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        gearboxV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // - mint some reward tokens by skipping blocks (should be `rewardTokenAmount` GEAR, depends on the forked block number)
        vm.warp(block.timestamp + 1 weeks);

        // act
        vm.startPrank(address(0), address(0));
        (address[] memory rewardAddresses, uint256[] memory rewardAmounts) = gearboxV3Strategy.getProtocolRewards();
        vm.stopPrank();

        // assert
        assertEq(rewardAddresses.length, 1);
        assertEq(rewardAddresses[0], address(gearToken));
        assertEq(rewardAmounts.length, rewardAddresses.length);

        assertEq(rewardAmounts[0], rewardTokenAmount);
    }

    function test_compound() public {
        // arrange
        IERC20 gearToken = gearboxV3Strategy.gear();

        priceFeedManager.setExchangeRate(address(gearToken), USD_DECIMALS_MULTIPLIER * 50); // GEAR

        MockExchange exchange = new MockExchange(gearToken, tokenUnderlying, priceFeedManager);

        deal(
            address(gearToken),
            address(exchange),
            1_000_000 * 10 ** IERC20Metadata(address(gearToken)).decimals(),
            false
        );
        _deal(address(exchange), 1_000_000 * 10 ** tokenUnderlying.decimals());

        swapper.updateExchangeAllowlist(Arrays.toArray(address(exchange)), Arrays.toArray(true));

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        gearboxV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

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

        slippages = new uint256[](4);
        slippages[3] = 1;
        int256 compoundYieldPercentage = gearboxV3Strategy.exposed_compound(assetGroup, compoundSwapInfo, slippages);

        // assert
        uint256 balanceOfStrategyAfter = _underlyingBalanceOfStrategy();

        int256 compoundYieldPercentageExpected =
            int256(((balanceOfStrategyAfter - balanceOfStrategyBefore) * YIELD_FULL_PERCENT) / balanceOfStrategyBefore);

        assertGt(compoundYieldPercentage, 0);
        assertApproxEqAbs(compoundYieldPercentage, compoundYieldPercentageExpected, 10);
    }

    function test_getUsdWorth() public {
        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        gearboxV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // act
        uint256 usdWorth = gearboxV3Strategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertApproxEqRel(usdWorth, priceFeedManager.assetToUsd(address(tokenUnderlying), toDeposit), 1e7);
    }
}

// Exposes protocol-specific functions for unit-testing.
contract GearboxV3StrategyHarness is GearboxV3ERC4626, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        IFarmingPool sdToken_,
        IERC4626 dToken_
    ) GearboxV3ERC4626(assetGroupRegistry_, accessControl_, swapper_, sdToken_, dToken_) {}
}
