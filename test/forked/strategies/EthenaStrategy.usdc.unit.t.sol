// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../../src/libraries/BytesUint256Lib.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/strategies/EthenaStrategy.sol";
import "../../fixtures/TestFixture.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../mocks/MockExchange.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";
import "../EthereumForkConstants.sol";
import "forge-std/console.sol";

interface IEthenaRewardDistributor {
    function transferInRewards(uint256 amount) external;
}

contract EthenaStrategyUsdcTest is TestFixture, ForkTestFixture {
    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    EthenaStrategyHarness ethenaStrategy;

    // ******* Underlying specific constants **************
    IERC20Metadata USDe = IERC20Metadata(USDe_TOKEN);
    IsUSDe sUSDe = IsUSDe(sUSDe_TOKEN);
    IERC20Metadata ENAToken = IERC20Metadata(ENA_TOKEN);
    uint256 toDeposit = 100000 * 10 ** 6;
    IERC20Metadata underlyingToken = IERC20Metadata(USDC);

    MockExchange USDe_USDC_Exchange;
    MockExchange sUSDe_USDC_Exchange;
    MockExchange ENA_USDe_Exchange;

    // ****************************************************

    function setUpForkTestFixture() internal override {
        mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK_EXTENDED_3);
    }

    function setUp() public {
        setUpForkTestFixture();
        vm.selectFork(mainnetForkId);
        setUpBase();

        assetGroup = Arrays.toArray(USDC);
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        address implementation =
            address(new EthenaStrategyHarness(assetGroupRegistry, accessControl, USDe, sUSDe, ENAToken, swapper));
        ethenaStrategy = EthenaStrategyHarness(address(new ERC1967Proxy(implementation, "")));

        ethenaStrategy.initialize("EthenaStrategy", assetGroupId);

        vm.prank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(ethenaStrategy));

        _deal(address(ethenaStrategy), toDeposit);

        sUSDe_USDC_Exchange = new MockExchange(sUSDe,underlyingToken, priceFeedManager);
        USDe_USDC_Exchange = new MockExchange(USDe,underlyingToken, priceFeedManager);
        ENA_USDe_Exchange = new MockExchange(ENAToken,USDe, priceFeedManager);

        deal(
            address(sUSDe),
            address(sUSDe_USDC_Exchange),
            1_000_000 * 10 ** IERC20Metadata(address(sUSDe)).decimals(),
            false
        );
        _deal(address(sUSDe_USDC_Exchange), 1_000_000 * 10 ** underlyingToken.decimals());

        deal(
            address(USDe),
            address(USDe_USDC_Exchange),
            1_000_000 * 10 ** IERC20Metadata(address(USDe)).decimals(),
            false
        );
        _deal(address(USDe_USDC_Exchange), 1_000_000 * 10 ** underlyingToken.decimals());

        deal(
            address(ENAToken),
            address(ENA_USDe_Exchange),
            1_000_000 * 10 ** IERC20Metadata(address(ENAToken)).decimals(),
            false
        );
        deal(address(USDe), address(ENA_USDe_Exchange), 1_000_000 * 10 ** USDe.decimals(), false);

        swapper.updateExchangeAllowlist(
            Arrays.toArray(address(sUSDe_USDC_Exchange), address(USDe_USDC_Exchange), address(ENA_USDe_Exchange)),
            Arrays.toArray(true, true, true)
        );

        // set exchange rate 1 to 1 for easier testing
        priceFeedManager.setExchangeRate(address(USDe), USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(sUSDe), USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(USDC, USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(ENAToken), USD_DECIMALS_MULTIPLIER * 8);

        assetGroupExchangeRates = SpoolUtils.getExchangeRates(Arrays.toArray(address(USDe)), priceFeedManager);
    }

    function _deal(address to, uint256 amount) private {
        vm.startPrank(USDC_WHALE);
        underlyingToken.transfer(to, amount);
        vm.stopPrank();
    }

    function disableCooldown() internal {
        // disable cooldown
        address sUSDeOwner = sUSDe.owner();
        vm.startPrank(sUSDeOwner);
        sUSDe.setCooldownDuration(0);
        assertEq(sUSDe.cooldownDuration(), 0);
        vm.stopPrank();
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

    function _depositToProtocol() private {
        uint256 snapshot = vm.snapshot();

        vm.startPrank(address(0), address(0));
        vm.recordLogs();
        uint256[] memory slippages = new uint256[](1);
        slippages[0] = 1;
        ethenaStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics.length, 1);
        assertEq(entries[0].topics[0], keccak256("SwapEstimation(address,address,uint256)"));
        vm.stopPrank();

        vm.revertTo(snapshot);

        ethenaStrategy.exposed_depositToProtocol(
            assetGroup, Arrays.toArray(toDeposit), buildSlippages(USDe_USDC_Exchange, entries[0].data)
        );
    }

    function _redeemFromProtocol(MockExchange exchange, uint256 toRedeem) private {
        uint256 snapshot = vm.snapshot();
        uint256[] memory slippages = new uint256[](1);
        slippages[0] = 1;
        vm.startPrank(address(0), address(0));
        vm.recordLogs();
        ethenaStrategy.exposed_redeemFromProtocol(assetGroup, toRedeem, slippages);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory data;
        bytes32 sig = keccak256("SwapEstimation(address,address,uint256)");
        for (uint256 i; i < entries.length; i++) {
            if (entries[i].topics[0] == sig) {
                data = entries[i].data;
                break;
            }
        }
        vm.stopPrank();
        vm.revertTo(snapshot);
        ethenaStrategy.exposed_redeemFromProtocol(assetGroup, toRedeem, buildSlippages(exchange, data));
    }

    function _emergencyWithdraw(MockExchange exchange) private {
        uint256 snapshot = vm.snapshot();
        uint256[] memory slippages = new uint256[](1);
        slippages[0] = 1;
        vm.startPrank(address(0), address(0));
        vm.recordLogs();
        ethenaStrategy.exposed_emergencyWithdrawImpl(slippages, emergencyWithdrawalRecipient);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory data;
        bytes32 sig = keccak256("SwapEstimation(address,address,uint256)");
        for (uint256 i; i < entries.length; i++) {
            if (entries[i].topics[0] == sig) {
                data = entries[i].data;
                break;
            }
        }
        vm.stopPrank();
        vm.revertTo(snapshot);
        ethenaStrategy.exposed_emergencyWithdrawImpl(buildSlippages(exchange, data), emergencyWithdrawalRecipient);
    }

    function test_depositToProtocolWithSwap() public {
        assertEq(underlyingToken.balanceOf(address(ethenaStrategy)), toDeposit);
        assertEq(sUSDe.balanceOf(address(ethenaStrategy)), 0);

        _depositToProtocol();

        assertEq(underlyingToken.balanceOf(address(ethenaStrategy)), 0);

        uint256 toMint = sUSDe.previewDeposit(toDeposit * 10 ** 12);
        uint256 sUSDeBalanceOfStrategy = sUSDe.balanceOf(address(ethenaStrategy));
        assertApproxEqAbs(sUSDeBalanceOfStrategy, toMint, 1);

        uint256[] memory amounts = ethenaStrategy.getUnderlyingAssetAmounts();
        assertEq(amounts.length, 1);
        assertApproxEqAbs(amounts[0], toDeposit * 10 ** 12, 1);
    }

    function test_redeemFromProtocolWithSwap() public {
        // arrange
        uint256 mintedShares = 100 * 10 ** 18;
        uint256 withdrawnShares = 60 * 10 ** 18;

        // - need to deposit into the protocol
        _depositToProtocol();
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        ethenaStrategy.exposed_mint(mintedShares);

        uint256 underlyingBefore = underlyingToken.balanceOf(address(ethenaStrategy));
        uint256 sharesBefore = sUSDe.balanceOf(address(ethenaStrategy));

        _redeemFromProtocol(sUSDe_USDC_Exchange, withdrawnShares);

        uint256 underlyingAfter = underlyingToken.balanceOf(address(ethenaStrategy));
        uint256 sharesAfter = sUSDe.balanceOf(address(ethenaStrategy));

        // since we exchange 1 to 1 there is strict equality
        assertEq(underlyingAfter - underlyingBefore, (sharesBefore - sharesAfter) / 10 ** 12, "1");

        uint256 shouldBeRatio = mintedShares * 10 ** 18 / (mintedShares - withdrawnShares);
        assertApproxEqAbs(sharesBefore * 10 ** 18 / sharesAfter, shouldBeRatio, 1, "2");
    }

    function test_redeemFromProtocol() public {
        disableCooldown();
        // arrange
        uint256 mintedShares = 100 * 10 ** 18;
        uint256 withdrawnShares = 60 * 10 ** 18;

        // - need to deposit into the protocol
        _depositToProtocol();
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        ethenaStrategy.exposed_mint(mintedShares);

        uint256 underlyingBefore = underlyingToken.balanceOf(address(ethenaStrategy));
        uint256 sharesBefore = sUSDe.balanceOf(address(ethenaStrategy));

        _redeemFromProtocol(USDe_USDC_Exchange, withdrawnShares);

        uint256 underlyingAfter = underlyingToken.balanceOf(address(ethenaStrategy));
        uint256 sharesAfter = sUSDe.balanceOf(address(ethenaStrategy));

        uint256 shouldBeWithdrawn = (toDeposit * withdrawnShares) / mintedShares;
        assertApproxEqAbs(underlyingAfter - underlyingBefore, shouldBeWithdrawn, 1, "1");

        uint256 shouldBeRatio = mintedShares * 10 ** 18 / (mintedShares - withdrawnShares);
        assertApproxEqAbs(sharesBefore * 10 ** 18 / sharesAfter, shouldBeRatio, 1, "2");
    }

    function test_emergencyWithdrawImplWithSwap() public {
        // arrange
        uint256 mintedShares = 100 * 10 ** 18;

        // - need to deposit into the protocol
        _depositToProtocol();
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        ethenaStrategy.exposed_mint(mintedShares);

        uint256 USDeBalanceBefore = sUSDe.previewRedeem(sUSDe.balanceOf(address(ethenaStrategy)));

        _emergencyWithdraw(sUSDe_USDC_Exchange);

        uint256 USDeBalanceAfter = sUSDe.previewRedeem(sUSDe.balanceOf(address(ethenaStrategy)));
        uint256 balanceOfEmergencyWithdrawalRecipient = underlyingToken.balanceOf(emergencyWithdrawalRecipient);

        uint256 sUSDeBalanceOfStrategy = sUSDe.balanceOf(address(ethenaStrategy));
        uint256 USDeBalanceOfStrategy = USDe.balanceOf(address(ethenaStrategy));
        uint256 underlyingBalanceOfStrategy = underlyingToken.balanceOf(address(ethenaStrategy));

        // 1% slippage
        assertApproxEqAbs(USDeBalanceBefore - USDeBalanceAfter, toDeposit * 10 ** 12, 1, "1");
        // 6% slippage
        assertApproxEqAbs(balanceOfEmergencyWithdrawalRecipient, toDeposit, (toDeposit / 100) * 6, "2");
        assertEq(sUSDeBalanceOfStrategy, 0, "3");
        assertEq(USDeBalanceOfStrategy, 0, "4");
        assertEq(underlyingBalanceOfStrategy, 0, "4");
    }

    function test_emergencyWithdrawImpl() public {
        disableCooldown();
        // arrange
        uint256 mintedShares = 100 * 10 ** 18;

        // - need to deposit into the protocol
        _depositToProtocol();
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        ethenaStrategy.exposed_mint(mintedShares);

        uint256 USDeBalanceBefore = sUSDe.previewRedeem(sUSDe.balanceOf(address(ethenaStrategy)));

        // act
        _emergencyWithdraw(USDe_USDC_Exchange);

        // assert
        uint256 USDeBalanceAfter = sUSDe.previewRedeem(sUSDe.balanceOf(address(ethenaStrategy)));
        uint256 balanceOfEmergencyWithdrawalRecipient = underlyingToken.balanceOf(emergencyWithdrawalRecipient);

        uint256 sUSDeBalanceOfStrategy = sUSDe.balanceOf(address(ethenaStrategy));
        uint256 USDeBalanceOfStrategy = USDe.balanceOf(address(ethenaStrategy));
        uint256 underlyingBalanceOfStrategy = underlyingToken.balanceOf(address(ethenaStrategy));

        // 0.25% slippage
        assertApproxEqAbs(USDeBalanceBefore - USDeBalanceAfter, toDeposit * 10 ** 12, toDeposit / 400, "1");
        // 0.25% slippage
        assertApproxEqAbs(balanceOfEmergencyWithdrawalRecipient, toDeposit, toDeposit / 400, "2");
        assertEq(sUSDeBalanceOfStrategy, 0, "3");
        assertEq(USDeBalanceOfStrategy, 0, "4");
        assertEq(underlyingBalanceOfStrategy, 0, "4");
    }

    // base yield
    function test_getYieldPercentage() public {
        // - vest all tokens in ETHENA first
        vm.warp(block.timestamp + 52 weeks);
        assertEq(sUSDe.getUnvestedAmount(), 0);
        ethenaStrategy.exposed_getYieldPercentage(0);
        // - need to deposit into the protocol
        _depositToProtocol();

        uint256 balanceOfStrategyBefore = ethenaStrategy.getUnderlyingAssetAmounts()[0];

        uint256 USDeBalanceOfStakingContractBeforeReward = USDe.balanceOf(address(sUSDe));

        uint256 rewardAmount = 50_000 * 10 ** USDe.decimals();
        deal(address(USDe), ETHENA_REWARD_DISTRIBUTOR_CONTRACT, rewardAmount);
        vm.startPrank(ETHENA_REWARD_DISTRIBUTOR_WALLET);
        IEthenaRewardDistributor(ETHENA_REWARD_DISTRIBUTOR_CONTRACT).transferInRewards(rewardAmount);
        vm.stopPrank();
        assertEq(sUSDe.getUnvestedAmount(), rewardAmount);

        uint256 USDeBalanceOfStakingContractAfterReward = USDe.balanceOf(address(sUSDe));

        assertEq(USDeBalanceOfStakingContractAfterReward - USDeBalanceOfStakingContractBeforeReward, rewardAmount);

        // - yield is gathered over time
        vm.warp(block.timestamp + 52 weeks);

        assertEq(sUSDe.getUnvestedAmount(), 0);

        // act
        int256 yieldPercentage = ethenaStrategy.exposed_getYieldPercentage(0);

        // assert
        uint256 balanceOfStrategyAfter = ethenaStrategy.getUnderlyingAssetAmounts()[0];

        uint256 calculatedYield = balanceOfStrategyBefore * uint256(yieldPercentage) / YIELD_FULL_PERCENT;
        uint256 expectedYield = balanceOfStrategyAfter - balanceOfStrategyBefore;

        assertGt(yieldPercentage, 0, "1");
        // 1%
        assertApproxEqAbs(calculatedYield, expectedYield, expectedYield / 100, "2");
    }

    function test_getUsdWorth() public {
        _depositToProtocol();

        uint256 usdWorth = ethenaStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        uint256 expectedUsdWorth = priceFeedManager.assetToUsd(address(USDe), toDeposit * 10 ** 12);

        // 0.25% due to swap from USDC to USDe we loose some value
        assertApproxEqAbs(usdWorth, expectedUsdWorth, expectedUsdWorth / 400);
    }

    function test_compound() public {
        // - need to deposit into the protocol
        _depositToProtocol();

        // emulate air drop
        deal(
            address(ENAToken), address(ethenaStrategy), 123 * 10 ** IERC20Metadata(address(ENAToken)).decimals(), false
        );

        uint256 balanceOfStrategyBefore = ethenaStrategy.exposed_underlyingAssetAmount();

        // act
        SwapInfo[] memory compoundSwapInfo = new SwapInfo[](1);
        compoundSwapInfo[0] = SwapInfo({
            swapTarget: address(ENA_USDe_Exchange),
            token: address(ENAToken),
            swapCallData: abi.encodeCall(ENA_USDe_Exchange.swap, (address(ENAToken), 123e18, address(swapper)))
        });

        uint256[] memory slippages = new uint256[](0);
        int256 compoundYieldPercentage = ethenaStrategy.exposed_compound(assetGroup, compoundSwapInfo, slippages);

        uint256 balanceOfStrategyAfter = ethenaStrategy.exposed_underlyingAssetAmount();

        int256 compoundYieldPercentageExpected =
            int256((balanceOfStrategyAfter - balanceOfStrategyBefore) * YIELD_FULL_PERCENT / balanceOfStrategyBefore);

        assertGt(compoundYieldPercentage, 0);
        assertApproxEqAbs(compoundYieldPercentage, compoundYieldPercentageExpected, 10);
    }
}

// Exposes protocol-specific functions for unit-testing.
contract EthenaStrategyHarness is EthenaStrategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IERC20Metadata USDe_,
        IsUSDe sUSDe_,
        IERC20Metadata ENAToken_,
        ISwapper swapper_
    ) EthenaStrategy(assetGroupRegistry_, accessControl_, USDe_, sUSDe_, ENAToken_, swapper_) {}

    function exposed_underlyingAssetAmount() external view returns (uint256) {
        return _underlyingAssetAmount();
    }
}
