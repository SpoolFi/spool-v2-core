// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/interfaces/IERC4626.sol";

import "../../../src/external/interfaces/weth/IWETH9.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/strategies/GearboxV3ERC4626.sol";
import "../../../src/strategies/ERC4626StrategyDouble.sol";
import "../../fixtures/TestFixture.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../mocks/MockExchange.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";
import "../EthereumForkConstants.sol";

import "forge-std/console.sol";

interface YearnVault is IERC4626 {
    function keeper() external view returns (address);
    function report() external returns (uint256 _profit, uint256 _loss);
}

contract YearnV3ERC4626Test is TestFixture, ForkTestFixture {
    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    YearnV3ERC4626Harness yearnV3Strategy;
    address implementation;

    // ******* Underlying specific constants **************
    YearnVault public vault = YearnVault(YearnAjnaDAIVault);
    YearnVault public harvester = YearnVault(YearnAjnaDAIHarvester);
    IERC20Metadata tokenUnderlying = IERC20Metadata(DAI);
    uint256 toDeposit = 100_000 * 10 ** 18;
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

        implementation = address(new YearnV3ERC4626Harness(assetGroupRegistry, accessControl, vault, harvester));
        yearnV3Strategy = YearnV3ERC4626Harness(address(new ERC1967Proxy(implementation, "")));

        yearnV3Strategy.initialize("MetamorphoStrategy", assetGroupId);

        vm.prank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(yearnV3Strategy));

        _deal(address(yearnV3Strategy), toDeposit);
    }

    function _deal(address to, uint256 amount) private {
        deal(address(tokenUnderlying), to, amount, true);
    }

    function test_depositToProtocol() public {
        // arrange
        uint256 underlyingBalanceOfVaultBefore = vault.totalAssets();
        uint256 sharesBefore = vault.balanceOf(address(yearnV3Strategy));
        uint256 sharesToMint = vault.previewDeposit(toDeposit);
        uint256 harvesterAssetsBefore = harvester.totalAssets();
        uint256 harvesterSharesToMint = harvester.previewDeposit(sharesToMint);
        uint256 harvesterSharesBefore = harvester.balanceOf(address(yearnV3Strategy));
        // act
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        yearnV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // assert
        uint256 underlyingBalanceOfVaultAfter = vault.totalAssets();
        uint256 sharesAfter = vault.balanceOf(address(yearnV3Strategy));
        uint256 harvesterAssetsAfter = harvester.totalAssets();
        uint256 harvesterSharesAfter = harvester.balanceOf(address(yearnV3Strategy));

        assertEq(underlyingBalanceOfVaultAfter, underlyingBalanceOfVaultBefore + toDeposit, "1");
        // all shares minted to strategy were put into harvester therefore shares balance is unchanged
        assertEq(sharesBefore, sharesAfter, "2");
        assertApproxEqAbs(vault.previewRedeem(sharesToMint), toDeposit, 1, "3");

        //  all vault shares gone into harvester
        assertEq(harvesterAssetsAfter, harvesterAssetsBefore + sharesToMint, "4");
        // harvester shares are minted to vault
        assertEq(harvesterSharesAfter, harvesterSharesToMint + harvesterSharesBefore, "5");
        assertApproxEqAbs(harvester.previewRedeem(harvesterSharesToMint), sharesToMint, 1, "6");
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 mintedShares = 100 * 10 ** 18;
        uint256 withdrawnShares = 60 * 10 ** 18;

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        yearnV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        yearnV3Strategy.exposed_mint(mintedShares);

        uint256 underlyingBefore = tokenUnderlying.balanceOf(address(yearnV3Strategy));
        uint256 sharesBefore = harvester.balanceOf(address(yearnV3Strategy));
        // act
        slippages[0] = 1;
        yearnV3Strategy.exposed_redeemFromProtocol(assetGroup, withdrawnShares, slippages);

        uint256 underlyingAfter = tokenUnderlying.balanceOf(address(yearnV3Strategy));
        uint256 sharesAfter = harvester.balanceOf(address(yearnV3Strategy));

        // rounding error occurs in both vault and harvester
        assertApproxEqAbs(underlyingAfter - underlyingBefore, (toDeposit * withdrawnShares) / mintedShares, 2, "1");
        assertApproxEqAbs(
            vault.previewRedeem(harvester.previewRedeem(sharesAfter)),
            (toDeposit * (mintedShares - withdrawnShares)) / mintedShares,
            2,
            "2"
        );
        assertApproxEqAbs(sharesBefore / sharesAfter, mintedShares / (mintedShares - withdrawnShares), 1, "3");
    }

    function test_emergencyWithdrawImpl() public {
        // arrange
        uint256 mintedShares = 100;

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        yearnV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        yearnV3Strategy.exposed_mint(mintedShares);

        uint256 sharesBefore = harvester.balanceOf(address(yearnV3Strategy));

        uint256 sharesToBurn = harvester.previewWithdraw(vault.previewWithdraw(toDeposit));

        // act
        slippages = new uint256[](2);
        slippages[0] = 3;
        slippages[1] = 1;
        yearnV3Strategy.exposed_emergencyWithdrawImpl(slippages, emergencyWithdrawalRecipient);

        uint256 recipientUnderlyingBalance = tokenUnderlying.balanceOf(emergencyWithdrawalRecipient);

        uint256 sharesAfter = harvester.balanceOf(address(yearnV3Strategy));

        assertApproxEqAbs(sharesToBurn, sharesBefore - sharesAfter, 2, "1");
        assertApproxEqAbs(recipientUnderlyingBalance, toDeposit, 2, "2");
        assertEq(sharesAfter, 0, "3");
    }

    // TODO: getYieldPercentage is broken need to debug further
    function test_getYieldPercentage() public {
        // basic report for some rewards
        vm.startPrank(harvester.keeper());
        harvester.report();
        vm.stopPrank();

        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        yearnV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        uint256 balanceOfStrategyBefore = yearnV3Strategy.exposed_underlyingAssetAmount();

        // - yield is gathered over time
        vm.warp(block.timestamp + 52 weeks);

        // act
        int256 yieldPercentage = yearnV3Strategy.exposed_getYieldPercentage(0);

        // assert
        uint256 balanceOfStrategyAfter = yearnV3Strategy.exposed_underlyingAssetAmount();

        uint256 expectedYield = balanceOfStrategyAfter - balanceOfStrategyBefore;

        uint256 calculatedYieldPercentage = (expectedYield * YIELD_FULL_PERCENT) / balanceOfStrategyBefore;

        uint256 calculatedYield = (balanceOfStrategyBefore * uint256(yieldPercentage)) / YIELD_FULL_PERCENT;

        assertGt(yieldPercentage, 0, "1");
        assertEq(uint256(yieldPercentage), calculatedYieldPercentage, "2");
        assertApproxEqAbs(calculatedYield, expectedYield, 10 ** (tokenUnderlying.decimals() - 3));

        // we should get what we expect
        slippages = new uint256[](2);
        slippages[0] = 3;
        slippages[1] = 1;
        yearnV3Strategy.exposed_emergencyWithdrawImpl(slippages, address(yearnV3Strategy));
        uint256 afterWithdraw = tokenUnderlying.balanceOf(address(yearnV3Strategy));
        assertEq(afterWithdraw, balanceOfStrategyAfter, "3");
    }

    function test_getProtocolRewards() public {
        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        yearnV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        vm.warp(block.timestamp + 1 weeks);

        // act
        vm.startPrank(address(0), address(0));
        (address[] memory rewardAddresses, uint256[] memory rewardAmounts) = yearnV3Strategy.getProtocolRewards();
        vm.stopPrank();

        // assert
        assertEq(rewardAddresses.length, 0);
        assertEq(rewardAmounts.length, rewardAddresses.length);
    }

    function test_getUsdWorth() public {
        // - need to deposit into the protocol
        uint256[] memory slippages = new uint256[](5);
        slippages[0] = 0;
        slippages[4] = 1;
        yearnV3Strategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // act
        uint256 usdWorth = yearnV3Strategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertApproxEqRel(usdWorth, priceFeedManager.assetToUsd(address(tokenUnderlying), toDeposit), 1e7);
    }
}

// Exposes protocol-specific functions for unit-testing.
contract YearnV3ERC4626Harness is ERC4626StrategyDouble, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IERC4626 vault_,
        IERC4626 harvester_
    ) ERC4626StrategyDouble(assetGroupRegistry_, accessControl_, vault_, harvester_) {}

    function exposed_underlyingAssetAmount() external view returns (uint256) {
        return underlyingAssetAmount_();
    }
}
