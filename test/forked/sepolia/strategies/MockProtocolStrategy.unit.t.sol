// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../../src/access/SpoolAccessControl.sol";
import "../../../../src/interfaces/Constants.sol";
import "../../../../src/libraries/SpoolUtils.sol";
import "../../../../src/managers/AssetGroupRegistry.sol";
import "../../../../src/strategies/mocks/MockProtocolStrategy.sol";
import "../../../../src/strategies/mocks/MockProtocol.sol";
import "../../../external/interfaces/IUSDC.sol";
import "../../../libraries/Arrays.sol";
import "../../../libraries/Constants.sol";
import "../../../mocks/MockExchange.sol";
import "../../../fixtures/TestFixture.sol";
import "../../ForkTestFixture.sol";
import "../../StrategyHarness.sol";
import "../SepoliaForkConstants.sol";

contract MockProtocolStrategyTest is TestFixture, ForkTestFixture {
    MockProtocolStrategyHarness private mockProtocolStrategy;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;
    MockProtocol private protocol;
    address user = address(0x1);

    uint256 apy = 800;
    IERC20Metadata tokenUnderlying = IERC20Metadata(USDC_SEPOLIA);

    function setUp() public {
        setUpForkTestFixtureSepolia();
        vm.selectFork(mainnetForkId);
        setUpBase();

        priceFeedManager.setExchangeRate(address(tokenUnderlying), USD_DECIMALS_MULTIPLIER * 1001 / 1000);

        assetGroup = Arrays.toArray(address(tokenUnderlying));
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        assetGroupExchangeRates = SpoolUtils.getExchangeRates(assetGroup, priceFeedManager);

        protocol = new MockProtocol(address(tokenUnderlying), apy);

        mockProtocolStrategy = new MockProtocolStrategyHarness(
            assetGroupRegistry,
            accessControl,
            protocol
        );
        mockProtocolStrategy.initialize("mock-strategy", assetGroupId);

        vm.prank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(mockProtocolStrategy));
    }

    function _deal(address to, uint256 amount) private {
        IUSDC(address(tokenUnderlying)).mint(to, amount);
    }

    function _strategyBalance() private view returns (uint256) {
        return protocol.balanceOf(address(mockProtocolStrategy));
    }

    function _protocolBalance() private view returns (uint256) {
        return tokenUnderlying.balanceOf(address(protocol));
    }

    function test_assetRatio() public {
        // act
        uint256[] memory assetRatio = mockProtocolStrategy.assetRatio();

        // assert
        uint256[] memory expectedAssetRatio = new uint256[](1);
        expectedAssetRatio[0] = 1;

        for (uint256 i; i < assetRatio.length; ++i) {
            assertEq(assetRatio[i], expectedAssetRatio[i]);
        }
    }

    function test_getUnderlyingAssetAmounts() public {
        // - arrange
        uint256 toDeposit = 1000 * 10 ** tokenUnderlying.decimals();
        _deal(address(mockProtocolStrategy), toDeposit);

        mockProtocolStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        mockProtocolStrategy.exposed_mint(100);

        // act
        uint256[] memory getUnderlyingAssetAmounts = mockProtocolStrategy.getUnderlyingAssetAmounts();
        uint256 getUnderlyingAssetAmount = getUnderlyingAssetAmounts[0];

        // assert
        assertApproxEqAbs(getUnderlyingAssetAmount, toDeposit, 1);
    }

    function test_depositToProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUnderlying.decimals();
        _deal(address(mockProtocolStrategy), toDeposit);

        uint256 balanceOfStrategyBefore = _strategyBalance();

        // act
        mockProtocolStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // assert
        uint256 balanceOfStrategyAfter = _strategyBalance();
        uint256 balanceOfProtocolAfter = _protocolBalance();

        assertEq(balanceOfStrategyAfter - balanceOfStrategyBefore, toDeposit);
        assertEq(balanceOfProtocolAfter, toDeposit);
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUnderlying.decimals();
        _deal(address(mockProtocolStrategy), toDeposit);

        // - need to deposit into the protocol
        mockProtocolStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        mockProtocolStrategy.exposed_mint(100);

        uint256 balanceOfStrategyBefore = _strategyBalance();

        // act
        mockProtocolStrategy.exposed_redeemFromProtocol(assetGroup, 60, new uint256[](0));

        // assert
        uint256 balanceOfStrategyAfter = _strategyBalance();
        uint256 balanceOfProtocolAfter = _protocolBalance();

        assertEq(balanceOfStrategyBefore - balanceOfStrategyAfter, toDeposit * 60 / 100);
        assertEq(balanceOfProtocolAfter, toDeposit * 40 / 100);
    }

    function test_emergencyWithdrawImpl() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUnderlying.decimals();
        _deal(address(mockProtocolStrategy), toDeposit);

        // - need to deposit into the protocol
        mockProtocolStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        mockProtocolStrategy.exposed_mint(100);

        uint256 balanceOfStrategyBefore = _strategyBalance();

        // act
        mockProtocolStrategy.exposed_emergencyWithdrawImpl(new uint256[](0), emergencyWithdrawalRecipient);

        // assert
        uint256 balanceOfStrategyAfter = _strategyBalance();
        uint256 balanceOfEmergencyWithdrawalRecipient = tokenUnderlying.balanceOf(emergencyWithdrawalRecipient);
        assertEq(balanceOfStrategyBefore - balanceOfStrategyAfter, toDeposit);
        assertEq(balanceOfEmergencyWithdrawalRecipient, toDeposit);
        assertEq(balanceOfStrategyAfter, 0);
    }

    function test_getYieldPercentage() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUnderlying.decimals();
        _deal(address(mockProtocolStrategy), toDeposit);

        // - need to deposit into the protocol
        mockProtocolStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        uint256 balanceOfStrategyBefore = _strategyBalance();

        // - yield is gathered over time
        vm.warp(block.timestamp + 52 weeks);

        // act
        int256 yieldPercentage = mockProtocolStrategy.exposed_getYieldPercentage(0);

        // assert
        uint256 balanceOfStrategyAfter = _strategyBalance();
        uint256 calculatedYield = balanceOfStrategyBefore * uint256(yieldPercentage) / YIELD_FULL_PERCENT;
        uint256 expectedYield = balanceOfStrategyAfter - balanceOfStrategyBefore;

        assertGt(yieldPercentage, 0);
        assertApproxEqAbs(calculatedYield, expectedYield, 1);

        // - yield is gathered over time
        vm.warp(block.timestamp + 26 weeks);

        // act
        yieldPercentage = mockProtocolStrategy.exposed_getYieldPercentage(0);

        // assert
        balanceOfStrategyAfter = _strategyBalance();
        calculatedYield = balanceOfStrategyBefore * uint256(yieldPercentage) / YIELD_FULL_PERCENT;
        expectedYield = balanceOfStrategyAfter - balanceOfStrategyBefore;

        assertGt(yieldPercentage, 0);
        assertApproxEqAbs(calculatedYield, expectedYield, 1);
    }

    function test_getUsdWorth() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUnderlying.decimals();
        _deal(address(mockProtocolStrategy), toDeposit);

        // - need to deposit into the protocol
        mockProtocolStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // act
        uint256 usdWorth = mockProtocolStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertEq(usdWorth, priceFeedManager.assetToUsd(address(tokenUnderlying), toDeposit));
    }

    function test_apy() public {
        // arrange
        uint256 toDeposit = 1000 * 10 ** tokenUnderlying.decimals();
        _deal(address(mockProtocolStrategy), toDeposit);

        mockProtocolStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        mockProtocolStrategy.exposed_mint(100);
        uint256 balanceOfStrategyBefore = _strategyBalance();

        // simulate 1 year of yield
        uint256 yield = toDeposit * apy / FULL_PERCENT;

        vm.warp(block.timestamp + 52 weeks);

        mockProtocolStrategy.exposed_redeemFromProtocol(assetGroup, 100, new uint256[](0));
        uint256 balanceOfStrategyAfter = tokenUnderlying.balanceOf(address(mockProtocolStrategy));

        assertEq(balanceOfStrategyAfter, balanceOfStrategyBefore + yield);
    }
}

// Exposes protocol-specific functions for unit-testing.
contract MockProtocolStrategyHarness is MockProtocolStrategy, StrategyHarness {
    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, MockProtocol protocol_)
        MockProtocolStrategy(assetGroupRegistry_, accessControl_, protocol_)
    {}
}
