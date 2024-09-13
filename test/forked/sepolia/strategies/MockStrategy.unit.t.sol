// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../../src/access/SpoolAccessControl.sol";
import "../../../../src/interfaces/Constants.sol";
import "../../../../src/libraries/SpoolUtils.sol";
import "../../../../src/managers/AssetGroupRegistry.sol";
import "../../../../src/strategies/mocks/MockStrategy.sol";
import "../../../external/interfaces/IUSDC.sol";
import "../../../libraries/Arrays.sol";
import "../../../libraries/Constants.sol";
import "../../../mocks/MockExchange.sol";
import "../../../fixtures/TestFixture.sol";
import "../../ForkTestFixture.sol";
import "../../StrategyHarness.sol";
import "../SepoliaForkConstants.sol";

contract MockStrategyTest is TestFixture, ForkTestFixture {
    IERC20Metadata private tokenUsdc;

    MockStrategyHarness private mockStrategy;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    uint256 rewardTokenPerSecond = 20000;

    function setUp() public {
        setUpForkTestFixtureSepolia();
        vm.selectFork(mainnetForkId);
        setUpBase();

        tokenUsdc = IERC20Metadata(USDC_SEPOLIA);

        priceFeedManager.setExchangeRate(address(tokenUsdc), USD_DECIMALS_MULTIPLIER * 1001 / 1000);

        assetGroup = Arrays.toArray(address(tokenUsdc));
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        assetGroupExchangeRates = SpoolUtils.getExchangeRates(assetGroup, priceFeedManager);

        mockStrategy = new MockStrategyHarness(
            assetGroupRegistry,
            accessControl
        );
        mockStrategy.initialize("mock-strategy", assetGroupId, rewardTokenPerSecond);

        vm.prank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(mockStrategy));
    }

    function _deal(address token, address to, uint256 amount) private {
        IUSDC(token).mint(to, amount);
    }

    function _strategyBalance() private view returns (uint256 amount) {
        (amount,) = mockStrategy.userInfo(address(mockStrategy));
    }

    function _protocolBalance() private view returns (uint256 amount) {
        (, amount,,) = mockStrategy.poolInfo();
    }

    function test_assetRatio() public {
        // act
        uint256[] memory assetRatio = mockStrategy.assetRatio();

        // assert
        uint256[] memory expectedAssetRatio = new uint256[](1);
        expectedAssetRatio[0] = 1;

        for (uint256 i; i < assetRatio.length; ++i) {
            assertEq(assetRatio[i], expectedAssetRatio[i]);
        }
    }

    function test_getUnderlyingAssetAmounts() public {
        // - arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(mockStrategy), toDeposit);

        mockStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        mockStrategy.exposed_mint(100);

        // act
        uint256[] memory getUnderlyingAssetAmounts = mockStrategy.getUnderlyingAssetAmounts();
        uint256 getUnderlyingAssetAmount = getUnderlyingAssetAmounts[0];

        // assert
        assertApproxEqAbs(getUnderlyingAssetAmount, toDeposit, 1);
    }

    function test_depositToProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(mockStrategy), toDeposit);

        uint256 usdcBalanceOfStrategyBefore = _strategyBalance();

        // act
        mockStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // assert
        uint256 usdcBalanceOfStrategyAfter = _strategyBalance();
        uint256 usdcBalanceOfProtocolAfter = _protocolBalance();

        assertEq(usdcBalanceOfStrategyAfter - usdcBalanceOfStrategyBefore, toDeposit);
        assertEq(usdcBalanceOfProtocolAfter, toDeposit);
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(mockStrategy), toDeposit);

        // - need to deposit into the protocol
        mockStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        mockStrategy.exposed_mint(100);

        uint256 usdcBalanceOfStrategyBefore = _strategyBalance();

        // act
        mockStrategy.exposed_redeemFromProtocol(assetGroup, 60, new uint256[](0));

        // assert
        uint256 usdcBalanceOfStrategyAfter = _strategyBalance();
        uint256 usdcBalanceOfProtocolAfter = _protocolBalance();

        assertEq(usdcBalanceOfStrategyBefore - usdcBalanceOfStrategyAfter, toDeposit * 60 / 100);
        assertEq(usdcBalanceOfProtocolAfter, toDeposit * 40 / 100);
    }

    function test_emergencyWithdrawImpl() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(mockStrategy), toDeposit);

        // - need to deposit into the protocol
        mockStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        mockStrategy.exposed_mint(100);

        uint256 usdcBalanceOfStrategyBefore = _strategyBalance();

        // act
        mockStrategy.exposed_emergencyWithdrawImpl(new uint256[](0), emergencyWithdrawalRecipient);

        // assert
        uint256 usdcBalanceOfStrategyAfter = _strategyBalance();
        uint256 usdcBalanceOfEmergencyWithdrawalRecipient = tokenUsdc.balanceOf(emergencyWithdrawalRecipient);
        assertEq(usdcBalanceOfStrategyBefore - usdcBalanceOfStrategyAfter, toDeposit);
        assertEq(usdcBalanceOfEmergencyWithdrawalRecipient, toDeposit);
        assertEq(usdcBalanceOfStrategyAfter, 0);
    }

    function test_getProtocolRewards() public {
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(mockStrategy), toDeposit);

        // - need to deposit into the protocol
        mockStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // yield is gathered over time
        skip(SECONDS_IN_YEAR);

        // act
        vm.startPrank(address(0), address(0));
        (address[] memory rewardAddresses, uint256[] memory rewardAmounts) = mockStrategy.getProtocolRewards();
        vm.stopPrank();

        // assert
        assertEq(rewardAddresses.length, 1);
        assertEq(rewardAddresses[0], address(tokenUsdc));
        assertEq(rewardAmounts.length, rewardAddresses.length);
        assertGt(rewardAmounts[0], 0);
    }

    function test_compound() public {
        // arrange
        uint256 toDeposit = 100000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(mockStrategy), toDeposit);

        // - need to deposit into the protocol
        mockStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // yield is gathered over time
        skip(SECONDS_IN_YEAR);

        uint256 balanceOfStrategyBefore = _strategyBalance();

        // act
        SwapInfo[] memory compoundSwapInfo = new SwapInfo[](0);
        uint256[] memory slippages = new uint256[](0);

        int256 compoundYieldPercentage = mockStrategy.exposed_compound(assetGroup, compoundSwapInfo, slippages);

        // assert
        uint256 balanceOfStrategyAfter = _strategyBalance();

        int256 compoundYieldPercentageExpected =
            int256((balanceOfStrategyAfter - balanceOfStrategyBefore) * YIELD_FULL_PERCENT / balanceOfStrategyBefore);

        assertGt(compoundYieldPercentage, 0);
        assertEq(compoundYieldPercentage, compoundYieldPercentageExpected);
    }

    function test_getUsdWorth() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUsdc.decimals();
        _deal(address(tokenUsdc), address(mockStrategy), toDeposit);

        // - need to deposit into the protocol
        mockStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // act
        uint256 usdWorth = mockStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertEq(usdWorth, priceFeedManager.assetToUsd(address(tokenUsdc), toDeposit));
    }
}

// Exposes protocol-specific functions for unit-testing.
contract MockStrategyHarness is MockStrategy, StrategyHarness {
    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_)
        MockStrategy(assetGroupRegistry_, accessControl_)
    {}
}
