// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/console.sol";
import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../src/access/SpoolAccessControl.sol";
import "../../../src/external/interfaces/weth/IWETH9.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../../src/managers/AssetGroupRegistry.sol";
import "../../../src/strategies/OEthHoldingStrategy.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../../mocks/MockExchange.sol";
import "../EthereumForkConstants.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";

contract OEthHoldingStrategyTest is TestFixture, ForkTestFixture {
    IERC20Metadata private tokenWeth;
    uint256 private tokenWethMultiplier;

    IOEthToken public oEthToken;
    IVaultCore public oEthVault;
    ICurveEthPool private curve;

    OEthHoldingStrategyHarness private oEthHoldingStrategy;

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    function setUpForkTestFixture() internal override {
        mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK_EXTENDED);
    }

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

        oEthToken = IOEthToken(OETH_TOKEN);
        oEthVault = IVaultCore(OETH_VAULT);
        curve = ICurveEthPool(CURVE_OETH_POOL);

        oEthHoldingStrategy = new OEthHoldingStrategyHarness(
            assetGroupRegistry,
            accessControl,
            assetGroupId,
            oEthToken,
            oEthVault,
            curve,
            address(tokenWeth)
        );
        oEthHoldingStrategy.initialize("oETH-holding-strategy");
    }

    function test_depositToProtocol_shouldMint() public {
        // arrange
        // - get weth to strategy
        uint256 amount = 1000;
        uint256 toDeposit = amount * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(oEthHoldingStrategy), toDeposit);

        uint256 oEthTotalSupplyBefore = oEthToken.totalSupply();

        // act
        uint256[] memory slippages = new uint256[](5);
        slippages[3] = 1;

        oEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // assert
        uint256 oEthTotalSupplyAfter = oEthToken.totalSupply();
        uint256 oEthBalanceStrategy = oEthToken.balanceOf(address(oEthHoldingStrategy));
        uint256 oEthBalanceStrategyExpected = oEthVault.priceUnitMint(address(tokenWeth)) * amount;

        assertGe(oEthTotalSupplyAfter - oEthTotalSupplyBefore, toDeposit);
        assertGe(oEthTotalSupplyAfter - oEthTotalSupplyBefore, oEthBalanceStrategy);
        assertTrue(oEthBalanceStrategy > 0);
        assertEq(oEthBalanceStrategy, oEthBalanceStrategyExpected);
    }

    function test_depositToProtocol_shouldBuyOnCurve() public {
        // arrange
        // - get weth to strategy
        uint256 amount = 1000;
        uint256 toDeposit = amount * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(oEthHoldingStrategy), toDeposit);

        uint256 oEthTotalSupplyBefore = oEthToken.totalSupply();

        // act
        uint256[] memory slippages = new uint256[](5);

        oEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // assert
        uint256 oEthTotalSupplyAfter = oEthToken.totalSupply();
        uint256 oEthBalanceStrategy = oEthToken.balanceOf(address(oEthHoldingStrategy));

        assertEq(oEthTotalSupplyAfter, oEthTotalSupplyBefore);
        assertTrue(oEthBalanceStrategy > 0);
        assertApproxEqRel(oEthBalanceStrategy, toDeposit, 1e16); // 1 permil
    }

    function test_redeemFromProtocol() public {
        // arrange
        // - get weth to strategy
        uint256 amount = 1000;
        uint256 toDeposit = amount * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(oEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](5);
        slippages[3] = 1;
        oEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        oEthHoldingStrategy.exposed_mint(100);

        uint256 oEthBalanceOfStrategyBefore = oEthToken.balanceOf(address(oEthHoldingStrategy));
        uint256 oEthTotalSupplyBefore = oEthToken.totalSupply();

        // act
        slippages[0] = 1;
        oEthHoldingStrategy.exposed_redeemFromProtocol(assetGroup, 60, slippages);

        // assert
        uint256 oEthRedeemedExpected = oEthBalanceOfStrategyBefore * 60 / 100;
        uint256 wethTokenWithdrawnExpected = toDeposit * 60 / 100;
        uint256 wethTokenBalanceOfStrategy = tokenWeth.balanceOf(address(oEthHoldingStrategy));
        uint256 oEthBalanceOfStrategyAfter = oEthToken.balanceOf(address(oEthHoldingStrategy));
        uint256 oEthTotalSupplyAfter = oEthToken.totalSupply();

        assertApproxEqRel(wethTokenBalanceOfStrategy, wethTokenWithdrawnExpected, 1e16); // 1%
        assertEq(oEthBalanceOfStrategyBefore - oEthBalanceOfStrategyAfter, oEthRedeemedExpected);
        assertEq(oEthTotalSupplyAfter, oEthTotalSupplyBefore);
    }

    function test_emergencyWithdrawImpl() public {
        // arrange
        // - get weth to strategy
        uint256 amount = 1000;
        uint256 toDeposit = amount * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(oEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](5);
        slippages[3] = 1;
        oEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        oEthHoldingStrategy.exposed_mint(100);

        uint256 oEthTotalSupplyBefore = oEthToken.totalSupply();

        // act
        slippages = new uint256[](2);
        slippages[0] = 3;
        oEthHoldingStrategy.exposed_emergencyWithdrawImpl(slippages, emergencyWithdrawalRecipient);

        // assert
        uint256 wethTokenBalanceOfWithdrawalRecipient = tokenWeth.balanceOf(emergencyWithdrawalRecipient);
        uint256 oEthBalanceOfStrategyAfter = oEthToken.balanceOf(address(oEthHoldingStrategy));
        uint256 oEthTotalSupplyAfter = oEthToken.totalSupply();

        assertApproxEqRel(wethTokenBalanceOfWithdrawalRecipient, toDeposit, 1e16); // 1%
        assertEq(oEthBalanceOfStrategyAfter, 0);
        assertEq(oEthTotalSupplyAfter, oEthTotalSupplyBefore);
    }

    function test_getYieldPercentage() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1000 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(oEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](5);
        slippages[3] = 1;
        oEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        oEthHoldingStrategy.exposed_mint(100);

        // - generate ~20% yield (reduce credits per token by 20%)
        uint256 priceBefore = oEthVault.priceUnitMint(address(tokenWeth));
        vm.record();
        uint256 rebasingCreditsPerToken = oEthToken.rebasingCreditsPerTokenHighres();
        (bytes32[] memory reads,) = vm.accesses(address(oEthToken));
        vm.store(address(oEthToken), reads[1], bytes32(rebasingCreditsPerToken * 10e18 / 12e18));

        // act
        int256 yieldPercentage = oEthHoldingStrategy.exposed_getYieldPercentage(0);

        // assert
        uint256 priceAfter = oEthVault.priceUnitMint(address(tokenWeth));

        assertEq(priceAfter, priceBefore);
        assertApproxEqRel(yieldPercentage, YIELD_FULL_PERCENT_INT / 5, 1e14); // .01%
    }

    function test_getUsdWorth() public {
        // arrange
        // - get weth to strategy
        uint256 amount = 1000;
        uint256 toDeposit = amount * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(oEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](5);
        slippages[3] = 1;
        oEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        oEthHoldingStrategy.exposed_mint(100);

        // act
        uint256 usdWorth = oEthHoldingStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertApproxEqAbs(usdWorth, priceFeedManager.assetToUsd(address(tokenWeth), toDeposit), 1e4);
    }
}

contract OEthHoldingStrategyHarness is OEthHoldingStrategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        uint256 assetGroupId_,
        IOEthToken oEthToken_,
        IVaultCore oEthVault_,
        ICurveEthPool curve_,
        address weth_
    ) OEthHoldingStrategy(assetGroupRegistry_, accessControl_, assetGroupId_, oEthToken_, oEthVault_, curve_, weth_) {}
}
