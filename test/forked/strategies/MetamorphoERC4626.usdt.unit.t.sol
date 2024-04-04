// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/interfaces/IERC4626.sol";

import "../../../src/external/interfaces/weth/IWETH9.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/strategies/GearboxV3ERC4626.sol";
import "../../../src/strategies/ERC4626Strategy.sol";
import "../../fixtures/TestFixture.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../mocks/MockExchange.sol";
import "../../mocks/MockERC4626ReInitializer.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";
import "../EthereumForkConstants.sol";

import "forge-std/console.sol";

contract MetamorphoERC4626Test is TestFixture, ForkTestFixture {
    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    MetamorphoERC4626Harness metamorphoStrategy;
    address implementation;

    // ******* Underlying specific constants **************
    IERC4626 public vault = IERC4626(METAMORPHO_RE7_USDT);
    IERC20Metadata tokenUnderlying = IERC20Metadata(USDT);
    uint256 toDeposit = 100_000 * 10 ** 6;
    uint256 rewardTokenAmount = 13396529259569365546568;
    uint256 underlyingPriceUSD = 1001;

    // ****************************************************

    function setUpForkTestFixture() internal override {
        mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK_EXTENDED_2);
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

        implementation = address(new MetamorphoERC4626Harness(assetGroupRegistry, accessControl, vault));
        metamorphoStrategy = MetamorphoERC4626Harness(address(new ERC1967Proxy(implementation, "")));

        metamorphoStrategy.initialize("MetamorphoStrategy", assetGroupId);

        vm.prank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(metamorphoStrategy));

        _deal(address(metamorphoStrategy), toDeposit);
    }

    function _deal(address to, uint256 amount) private {
        deal(address(tokenUnderlying), to, amount, true);
    }

    function test_depositToProtocol() public {
        // arrange
        uint256 underlyingBalanceOfVaultBefore = tokenUnderlying.balanceOf(address(vault));
        uint256 sharesBefore = vault.balanceOf(address(metamorphoStrategy));
        uint256 sharesToMint = vault.previewDeposit(toDeposit);
        // act
        metamorphoStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // assert
        uint256 underlyingBalanceOfVaultAfter = tokenUnderlying.balanceOf(address(vault));
        uint256 sharesAfter = vault.balanceOf(address(metamorphoStrategy));

        // Morpho vault does not hold assets but routes them to Morpho Blue
        assertEq(underlyingBalanceOfVaultAfter, underlyingBalanceOfVaultBefore);
        assertEq(sharesToMint, sharesAfter - sharesBefore);
        assertApproxEqAbs(vault.previewRedeem(vault.balanceOf(address(metamorphoStrategy))), toDeposit, 1);
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 mintedShares = 100 * 10 ** 18;
        uint256 withdrawnShares = 60 * 10 ** 18;

        // - need to deposit into the protocol
        metamorphoStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        metamorphoStrategy.exposed_mint(mintedShares);

        uint256 underlyingBefore = tokenUnderlying.balanceOf(address(metamorphoStrategy));
        uint256 sharesBefore = vault.balanceOf(address(metamorphoStrategy));
        // act
        metamorphoStrategy.exposed_redeemFromProtocol(assetGroup, withdrawnShares, new uint256[](0));

        uint256 underlyingAfter = tokenUnderlying.balanceOf(address(metamorphoStrategy));
        uint256 sharesAfter = vault.balanceOf(address(metamorphoStrategy));

        assertApproxEqAbs(underlyingAfter - underlyingBefore, (toDeposit * withdrawnShares) / mintedShares, 1);
        assertApproxEqAbs(
            underlyingAfter, (toDeposit * withdrawnShares) / mintedShares, 1 * 10 * tokenUnderlying.decimals()
        );
        assertApproxEqAbs(
            vault.previewRedeem(sharesAfter),
            (toDeposit * (mintedShares - withdrawnShares)) / mintedShares,
            1 * 10 * tokenUnderlying.decimals()
        );
        assertApproxEqAbs(
            (sharesBefore * 10 ** 18) / sharesAfter, (mintedShares * 10 ** 18) / (mintedShares - withdrawnShares), 1
        );
    }

    function test_emergencyWithdrawImpl() public {
        // arrange
        uint256 mintedShares = 100;

        // - need to deposit into the protocol
        metamorphoStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        metamorphoStrategy.exposed_mint(mintedShares);

        uint256 sharesBefore = vault.balanceOf(address(metamorphoStrategy));

        uint256 sharesToBurn = vault.previewWithdraw(toDeposit);

        // act
        metamorphoStrategy.exposed_emergencyWithdrawImpl(new uint256[](0), emergencyWithdrawalRecipient);

        uint256 recipientUnderlyingBalance = tokenUnderlying.balanceOf(emergencyWithdrawalRecipient);

        uint256 sharesAfter = vault.balanceOf(address(metamorphoStrategy));

        assertApproxEqAbs(sharesToBurn, sharesBefore - sharesAfter, 1);
        assertApproxEqAbs(recipientUnderlyingBalance, toDeposit, 1);
        assertEq(sharesAfter, 0);
    }

    function test_getYieldPercentage() public {
        // - need to deposit into the protocol
        metamorphoStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        uint256 balanceOfStrategyBefore = vault.previewRedeem(vault.balanceOf((address(metamorphoStrategy))));

        // - yield is gathered over time
        vm.warp(block.timestamp + 52 weeks);

        // act
        int256 yieldPercentage = metamorphoStrategy.exposed_getYieldPercentage(0);

        // assert
        uint256 balanceOfStrategyAfter = vault.previewRedeem(vault.balanceOf((address(metamorphoStrategy))));

        uint256 calculatedYield = (balanceOfStrategyBefore * uint256(yieldPercentage)) / YIELD_FULL_PERCENT;
        uint256 expectedYield = balanceOfStrategyAfter - balanceOfStrategyBefore;

        assertGt(yieldPercentage, 0);
        assertApproxEqAbs(calculatedYield, expectedYield, 10 ** (metamorphoStrategy.vault().decimals() / 2));
    }

    function test_getProtocolRewards() public {
        // - need to deposit into the protocol
        metamorphoStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        vm.warp(block.timestamp + 1 weeks);

        // act
        vm.startPrank(address(0), address(0));
        (address[] memory rewardAddresses, uint256[] memory rewardAmounts) = metamorphoStrategy.getProtocolRewards();
        vm.stopPrank();

        // assert
        assertEq(rewardAddresses.length, 1);
        assertEq(rewardAddresses[0], address(0));
        assertEq(rewardAmounts.length, rewardAddresses.length);
        assertEq(rewardAmounts[0], 0);
    }

    function test_getUsdWorth() public {
        // - need to deposit into the protocol
        metamorphoStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), new uint256[](0));

        // act
        uint256 usdWorth = metamorphoStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertApproxEqRel(usdWorth, priceFeedManager.assetToUsd(address(tokenUnderlying), toDeposit), 1e7);
    }
}

// Exposes protocol-specific functions for unit-testing.
contract MetamorphoERC4626Harness is ERC4626Strategy, StrategyHarness {
    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, IERC4626 vault_)
        ERC4626Strategy(assetGroupRegistry_, accessControl_, vault_)
    {}
}
