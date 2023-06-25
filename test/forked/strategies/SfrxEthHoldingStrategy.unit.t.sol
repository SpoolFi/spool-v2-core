// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/console.sol";
import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../src/access/SpoolAccessControl.sol";
import "../../../src/external/interfaces/weth/IWETH9.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../../src/managers/AssetGroupRegistry.sol";
import "../../../src/strategies/SfrxEthHoldingStrategy.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../../mocks/MockExchange.sol";
import "../EthereumForkConstants.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";

contract SfrxEthHoldingStrategyTest is TestFixture, ForkTestFixture {
    IERC20Metadata private tokenWeth;
    uint256 private tokenWethMultiplier;

    IERC20 public frxEthToken;
    ISfrxEthToken public sfrxEthToken;
    IFrxEthMinter public frxEthMinter;
    ICurveEthPool private curve;

    SfrxEthHoldingStrategyHarness private sfrxEthHoldingStrategy;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    function setUp() public {
        setUpForkTestFixture();
        vm.selectFork(mainnetForkId);
        setUpBase();

        tokenWeth = IERC20Metadata(WETH);
        tokenWethMultiplier = 10 ** tokenWeth.decimals();

        priceFeedManager.setExchangeRate(address(tokenWeth), USD_DECIMALS_MULTIPLIER * 2000);

        assetGroup = Arrays.toArray(address(tokenWeth));
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        assetGroupExchangeRates = SpoolUtils.getExchangeRates(assetGroup, priceFeedManager);

        frxEthToken = IERC20(FRXETH_TOKEN);
        sfrxEthToken = ISfrxEthToken(SFRXETH_TOKEN);
        frxEthMinter = IFrxEthMinter(FRXETH_MINTER);
        curve = ICurveEthPool(CURVE_FRXETH_POOL);

        sfrxEthHoldingStrategy = new SfrxEthHoldingStrategyHarness(
            assetGroupRegistry,
            accessControl,
            assetGroupId,
            frxEthToken,
            sfrxEthToken,
            frxEthMinter,
            curve,
            address(tokenWeth)
        );
        sfrxEthHoldingStrategy.initialize("sfrxETH-holding-strategy");
    }

    function test_depositToProtocol_shouldStake() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1000 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(sfrxEthHoldingStrategy), toDeposit);

        uint256 frxEthTotalSupplyBefore = frxEthToken.totalSupply();
        uint256 sfrxEthTotalSupplyBefore = sfrxEthToken.totalSupply();

        // act
        uint256[] memory slippages = new uint256[](4);
        slippages[3] = type(uint256).max;

        sfrxEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // assert
        uint256 frxEthTotalSupplyAfter = frxEthToken.totalSupply();
        uint256 sfrxEthTotalSupplyAfter = sfrxEthToken.totalSupply();
        uint256 sfrxEthBalanceStrategy = sfrxEthToken.balanceOf(address(sfrxEthHoldingStrategy));
        uint256 sfrxEthBalanceStrategyExpected = sfrxEthToken.convertToShares(toDeposit);

        assertEq(frxEthTotalSupplyAfter - frxEthTotalSupplyBefore, toDeposit);
        assertTrue(sfrxEthBalanceStrategy > 0);
        assertEq(sfrxEthBalanceStrategy, sfrxEthTotalSupplyAfter - sfrxEthTotalSupplyBefore);
        assertEq(sfrxEthBalanceStrategy, sfrxEthBalanceStrategyExpected);
    }

    function test_depositToProtocol_shouldBuyOnCurve() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1000 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(sfrxEthHoldingStrategy), toDeposit);

        uint256 frxEthTotalSupplyBefore = frxEthToken.totalSupply();
        uint256 sfrxEthTotalSupplyBefore = sfrxEthToken.totalSupply();

        // act
        uint256[] memory slippages = new uint256[](4);

        sfrxEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // assert
        uint256 frxEthTotalSupplyAfter = frxEthToken.totalSupply();
        uint256 sfrxEthTotalSupplyAfter = sfrxEthToken.totalSupply();
        uint256 sfrxEthBalanceStrategy = sfrxEthToken.balanceOf(address(sfrxEthHoldingStrategy));
        uint256 frxEthBalanceOfStrategy = frxEthToken.balanceOf(address(sfrxEthHoldingStrategy));
        uint256 sfrxEthBalanceStrategyExpected = sfrxEthToken.convertToShares(toDeposit);

        assertEq(frxEthTotalSupplyAfter, frxEthTotalSupplyBefore);
        assertTrue(sfrxEthBalanceStrategy > 0);
        assertEq(sfrxEthBalanceStrategy, sfrxEthTotalSupplyAfter - sfrxEthTotalSupplyBefore);
        assertEq(frxEthBalanceOfStrategy, 0);
        assertApproxEqRel(sfrxEthBalanceStrategy, sfrxEthBalanceStrategyExpected, 1e15); // 1 permil
    }

    function test_redeemFromProtocol() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1000 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(sfrxEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](4);
        sfrxEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        sfrxEthHoldingStrategy.exposed_mint(100);

        uint256 sfrxEthBalanceOfStrategyBefore = sfrxEthToken.balanceOf(address(sfrxEthHoldingStrategy));
        uint256 frxEthTotalSupplyBefore = frxEthToken.totalSupply();
        uint256 sfrxEthTotalSupplyBefore = sfrxEthToken.totalSupply();

        // act
        slippages[0] = 1;
        slippages[3] = 1;
        sfrxEthHoldingStrategy.exposed_redeemFromProtocol(assetGroup, 60, slippages);

        // assert
        uint256 sfrxEthRedeemedExpected = sfrxEthBalanceOfStrategyBefore * 60 / 100;
        uint256 wethTokenWithdrawnExpected = toDeposit * 60 / 100;
        uint256 wethTokenBalanceOfStrategy = tokenWeth.balanceOf(address(sfrxEthHoldingStrategy));
        uint256 sfrxEthBalanceOfStrategyAfter = sfrxEthToken.balanceOf(address(sfrxEthHoldingStrategy));
        uint256 frxEthBalanceOfStrategy = frxEthToken.balanceOf(address(sfrxEthHoldingStrategy));
        uint256 frxEthTotalSupplyAfter = frxEthToken.totalSupply();
        uint256 sfrxEthTotalSupplyAfter = sfrxEthToken.totalSupply();

        assertApproxEqRel(wethTokenBalanceOfStrategy, wethTokenWithdrawnExpected, 1e15); // 1 permil
        assertEq(sfrxEthBalanceOfStrategyBefore - sfrxEthBalanceOfStrategyAfter, sfrxEthRedeemedExpected);
        assertEq(frxEthBalanceOfStrategy, 0);
        assertEq(frxEthTotalSupplyAfter, frxEthTotalSupplyBefore);
        assertEq(sfrxEthTotalSupplyBefore - sfrxEthTotalSupplyAfter, sfrxEthRedeemedExpected);
    }

    function test_emergencyWithdrawImpl() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1000 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(sfrxEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](4);
        sfrxEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        sfrxEthHoldingStrategy.exposed_mint(100);

        uint256 sfrxEthBalanceOfStrategyBefore = sfrxEthToken.balanceOf(address(sfrxEthHoldingStrategy));
        uint256 frxEthTotalSupplyBefore = frxEthToken.totalSupply();
        uint256 sfrxEthTotalSupplyBefore = sfrxEthToken.totalSupply();

        // act
        slippages = new uint256[](2);
        slippages[0] = 3;
        sfrxEthHoldingStrategy.exposed_emergencyWithdrawImpl(slippages, emergencyWithdrawalRecipient);

        // assert
        uint256 wethTokenBalanceOfWithdrawalRecipient = tokenWeth.balanceOf(emergencyWithdrawalRecipient);
        uint256 sfrxEthBalanceOfStrategyAfter = sfrxEthToken.balanceOf(address(sfrxEthHoldingStrategy));
        uint256 frxEthBalanceOfStrategy = frxEthToken.balanceOf(address(sfrxEthHoldingStrategy));
        uint256 frxEthTotalSupplyAfter = frxEthToken.totalSupply();
        uint256 sfrxEthTotalSupplyAfter = sfrxEthToken.totalSupply();

        assertApproxEqRel(wethTokenBalanceOfWithdrawalRecipient, toDeposit, 1e15); // 1 permil
        assertEq(frxEthBalanceOfStrategy, 0);
        assertEq(sfrxEthBalanceOfStrategyAfter, 0);
        assertEq(frxEthTotalSupplyAfter, frxEthTotalSupplyBefore);
        assertEq(sfrxEthTotalSupplyBefore - sfrxEthTotalSupplyAfter, sfrxEthBalanceOfStrategyBefore);
    }

    function test_getYieldPercentage() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1000 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(sfrxEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](6);
        sfrxEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        sfrxEthHoldingStrategy.exposed_mint(100);

        // - generate 20% yield
        uint256 priceBefore = sfrxEthToken.convertToAssets(1 ether);

        // -- check total assets now
        uint256 totalAssets = sfrxEthToken.totalAssets();
        // -- skip time to end of reward cycle
        skip(sfrxEthToken.rewardsCycleEnd() - block.timestamp);
        // -- update balance of frxEth owned by sfrxEth
        deal(address(frxEthToken), address(sfrxEthToken), totalAssets * 120 / 100, true);
        // -- sync rewards
        sfrxEthToken.syncRewards();
        // -- skip time to end of reward cycle
        skip(sfrxEthToken.rewardsCycleEnd() - block.timestamp);

        // act
        int256 yieldPercentage = sfrxEthHoldingStrategy.exposed_getYieldPercentage(0);

        // assert
        uint256 priceAfter = sfrxEthToken.convertToAssets(1 ether);

        assertApproxEqAbs(priceAfter, priceBefore * 120 / 100, 10);
        assertEq(yieldPercentage, YIELD_FULL_PERCENT_INT / 5);
    }

    function test_getUsdWorth() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1000 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(sfrxEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](4);
        slippages[3] = type(uint256).max;
        sfrxEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        sfrxEthHoldingStrategy.exposed_mint(100);

        // act
        uint256 usdWorth = sfrxEthHoldingStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertApproxEqAbs(usdWorth, priceFeedManager.assetToUsd(address(tokenWeth), toDeposit), 1e4);
    }
}

contract SfrxEthHoldingStrategyHarness is SfrxEthHoldingStrategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        uint256 assetGroupId_,
        IERC20 frxEthToken_,
        ISfrxEthToken sfrxEthToken_,
        IFrxEthMinter frxEthMinter_,
        ICurveEthPool curve_,
        address weth_
    )
        SfrxEthHoldingStrategy(
            assetGroupRegistry_,
            accessControl_,
            assetGroupId_,
            frxEthToken_,
            sfrxEthToken_,
            frxEthMinter_,
            curve_,
            weth_
        )
    {}
}
