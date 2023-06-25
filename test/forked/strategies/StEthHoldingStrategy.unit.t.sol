// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/console.sol";
import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../src/access/SpoolAccessControl.sol";
import "../../../src/external/interfaces/weth/IWETH9.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../../src/managers/AssetGroupRegistry.sol";
import "../../../src/strategies/StEthHoldingStrategy.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../../mocks/MockExchange.sol";
import "../EthereumForkConstants.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";

contract StEthHoldingStrategyTest is TestFixture, ForkTestFixture {
    IERC20Metadata private tokenWeth;
    uint256 private tokenWethMultiplier;

    ILido private lido;
    ICurveEthPool private curve;

    StEthHoldingStrategyHarness private stEthHoldingStrategy;

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

        lido = ILido(LIDO);
        curve = ICurveEthPool(CURVE_STETH_POOL);

        stEthHoldingStrategy = new StEthHoldingStrategyHarness(
            assetGroupRegistry,
            accessControl,
            assetGroupId,
            lido,
            curve,
            address(tokenWeth)
        );
        stEthHoldingStrategy.initialize("stETH-holding-strategy");
    }

    function test_depositToProtocol_shouldStake() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1000 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(stEthHoldingStrategy), toDeposit);

        uint256 lidoPooledEthBefore = lido.getTotalPooledEther();

        // act
        uint256[] memory slippages = new uint256[](4);
        slippages[3] = type(uint256).max;

        stEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // assert
        uint256 lidoPooledEthAfter = lido.getTotalPooledEther();

        assertEq(lidoPooledEthAfter - lidoPooledEthBefore, toDeposit);
        assertApproxEqAbs(lido.balanceOf(address(stEthHoldingStrategy)), toDeposit, 10);
    }

    function test_depositToProtocol_shouldBuyOnCurve() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1000 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(stEthHoldingStrategy), toDeposit);

        uint256 lidoPooledEthBefore = lido.getTotalPooledEther();

        // act
        uint256[] memory slippages = new uint256[](4);

        stEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // assert
        uint256 lidoPooledEthAfter = lido.getTotalPooledEther();

        assertEq(lidoPooledEthAfter, lidoPooledEthBefore);
        assertApproxEqRel(lido.balanceOf(address(stEthHoldingStrategy)), toDeposit, 1e15); // to 1 permil
    }

    function test_redeemFromProtocol() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1000 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(stEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](4);
        slippages[3] = type(uint256).max;
        stEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        stEthHoldingStrategy.exposed_mint(100);

        uint256 stEthBalanceOfStrategyBefore = lido.balanceOf(address(stEthHoldingStrategy));

        // act
        slippages[0] = 1;
        slippages[3] = 1;
        stEthHoldingStrategy.exposed_redeemFromProtocol(assetGroup, 60, slippages);

        // assert
        uint256 stEthRedeemedExpected = toDeposit * 60 / 100;
        uint256 wethTokenWithdrawnExpected = toDeposit * 60 / 100;
        uint256 wethTokenBalanceOfStrategy = tokenWeth.balanceOf(address(stEthHoldingStrategy));
        uint256 stEthBalanceOfStrategyAfter = lido.balanceOf(address(stEthHoldingStrategy));

        assertApproxEqRel(wethTokenBalanceOfStrategy, wethTokenWithdrawnExpected, 2e15); // 2 permil
        assertApproxEqAbs(stEthBalanceOfStrategyBefore - stEthBalanceOfStrategyAfter, stEthRedeemedExpected, 10);
    }

    function test_emergencyWithdrawImpl() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1000 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(stEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](4);
        slippages[3] = type(uint256).max;
        stEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        stEthHoldingStrategy.exposed_mint(100);

        // act
        slippages = new uint256[](2);
        slippages[0] = 3;
        stEthHoldingStrategy.exposed_emergencyWithdrawImpl(slippages, emergencyWithdrawalRecipient);

        // assert
        uint256 wethTokenBalanceOfWithdrawalRecipient = tokenWeth.balanceOf(emergencyWithdrawalRecipient);
        uint256 stEthBalanceOfStrategyAfter = lido.balanceOf(address(stEthHoldingStrategy));

        assertApproxEqRel(wethTokenBalanceOfWithdrawalRecipient, toDeposit, 2e15); // 2 permil
        assertApproxEqAbs(stEthBalanceOfStrategyAfter, 0, 10);
    }

    function test_getYieldPercentage() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1000 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(stEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](4);
        slippages[3] = type(uint256).max;
        stEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        stEthHoldingStrategy.exposed_mint(100);

        // - generate 20% yield
        uint256 totalPooledEthBefore = lido.getTotalPooledEther();
        uint256 yieldAmount = totalPooledEthBefore * 20 / 100;
        uint256 bufferedAmount = uint256(vm.load(address(lido), keccak256("lido.Lido.bufferedEther")));
        uint256 balanceAmount = address(lido).balance;

        vm.deal(address(lido), balanceAmount + yieldAmount);
        vm.store(address(lido), keccak256("lido.Lido.bufferedEther"), bytes32(bufferedAmount + yieldAmount));

        // act
        int256 yieldPercentage = stEthHoldingStrategy.exposed_getYieldPercentage(0);

        // assert
        uint256 totalPooledEthAfter = lido.getTotalPooledEther();

        assertEq(totalPooledEthAfter, totalPooledEthBefore * 120 / 100);
        assertApproxEqAbs(yieldPercentage, YIELD_FULL_PERCENT_INT / 5, 10);
    }

    function test_getUsdWorth() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1000 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(stEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](4);
        slippages[3] = type(uint256).max;
        stEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // act
        uint256 usdWorth = stEthHoldingStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertApproxEqAbs(usdWorth, priceFeedManager.assetToUsd(address(tokenWeth), toDeposit), 1e4);
    }
}

contract StEthHoldingStrategyHarness is StEthHoldingStrategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        uint256 assetGroupId_,
        ILido lido_,
        ICurveEthPool curve_,
        address weth_
    ) StEthHoldingStrategy(assetGroupRegistry_, accessControl_, assetGroupId_, lido_, curve_, weth_) {}
}
