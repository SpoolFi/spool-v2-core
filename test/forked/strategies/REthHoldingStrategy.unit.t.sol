// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/console.sol";
import "forge-std/console2.sol";
import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../src/access/SpoolAccessControl.sol";
import "../../../src/external/interfaces/weth/IWETH9.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../../src/managers/AssetGroupRegistry.sol";
import "../../../src/strategies/REthHoldingStrategy.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../../mocks/MockExchange.sol";
import "../EthereumForkConstants.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";

contract REthHoldingStrategyTest is TestFixture, ForkTestFixture {
    IERC20Metadata private tokenWeth;
    uint256 private tokenWethMultiplier;

    IRocketStorage private rocketStorage;
    IREthToken private rEthToken;
    IRocketSwapRouter private rocketSwapRouter;

    address private uniswapPool;
    address private balancerVault;

    REthHoldingStrategyHarness private rEthHoldingStrategy;

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

        rocketStorage = IRocketStorage(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46);
        rocketSwapRouter = IRocketSwapRouter(ROCKET_SWAP_ROUTER);
        rEthToken = IREthToken(rocketSwapRouter.rETH());

        uniswapPool = address(0xa4e0faA58465A2D369aa21B3e42d43374c6F9613);
        balancerVault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

        rEthHoldingStrategy = new REthHoldingStrategyHarness(
            assetGroupRegistry,
            accessControl,
            assetGroupId,
            rocketSwapRouter,
            address(tokenWeth)
        );
        rEthHoldingStrategy.initialize("rETH-holding-strategy");
    }

    function test_depositToProtocol_withUniswap() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 100 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(rEthHoldingStrategy), toDeposit);

        uint256 rEthBalanceOfUniswapBefore = rEthToken.balanceOf(uniswapPool);
        uint256 rEthBalanceOfBalancerBefore = rEthToken.balanceOf(balancerVault);

        // act
        uint256[] memory slippages = new uint256[](7);
        slippages[3] = 100; // portion to swap on uniswap
        slippages[4] = 0; // portion to swap on balancer
        slippages[5] = 1; // min out
        slippages[6] = rEthToken.getRethValue(toDeposit) + 1; // ideal out - should be larger than internal price to swap

        rEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // assert
        uint256 rEthBalanceOfUniswapAfter = rEthToken.balanceOf(uniswapPool);
        uint256 rEthBalanceOfBalancerAfter = rEthToken.balanceOf(balancerVault);
        uint256 rEthBalanceOfStrategy = rEthToken.balanceOf(address(rEthHoldingStrategy));
        uint256 ethValueOfStrategy = rEthToken.getEthValue(rEthBalanceOfStrategy);
        uint256 rEthBalanceOfStrategyExpected = rEthToken.getRethValue(toDeposit);

        assertGt(rEthBalanceOfStrategy, 0);
        assertEq(rEthBalanceOfUniswapBefore - rEthBalanceOfUniswapAfter, rEthBalanceOfStrategy);
        assertEq(rEthBalanceOfBalancerAfter, rEthBalanceOfBalancerBefore);
        assertApproxEqRel(rEthBalanceOfStrategy, rEthBalanceOfStrategyExpected, 2e16); // 2 percent
        assertApproxEqRel(ethValueOfStrategy, toDeposit, 2e16); // 2 percent
    }

    function test_depositToProtocol_withBalancer() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 100 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(rEthHoldingStrategy), toDeposit);

        uint256 rEthBalanceOfUniswapBefore = rEthToken.balanceOf(uniswapPool);
        uint256 rEthBalanceOfBalancerBefore = rEthToken.balanceOf(balancerVault);

        // act
        uint256[] memory slippages = new uint256[](7);
        slippages[3] = 0; // portion to swap on uniswap
        slippages[4] = 100; // portion to swap on balancer
        slippages[5] = 1; // min out
        slippages[6] = rEthToken.getRethValue(toDeposit) + 1; // ideal out - should be larger than internal price to swap

        rEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // assert
        uint256 rEthBalanceOfUniswapAfter = rEthToken.balanceOf(uniswapPool);
        uint256 rEthBalanceOfBalancerAfter = rEthToken.balanceOf(balancerVault);
        uint256 rEthBalanceOfStrategy = rEthToken.balanceOf(address(rEthHoldingStrategy));
        uint256 ethValueOfStrategy = rEthToken.getEthValue(rEthBalanceOfStrategy);
        uint256 rEthBalanceOfStrategyExpected = rEthToken.getRethValue(toDeposit);

        assertGt(rEthBalanceOfStrategy, 0);
        assertEq(rEthBalanceOfUniswapAfter, rEthBalanceOfUniswapBefore);
        assertEq(rEthBalanceOfBalancerBefore - rEthBalanceOfBalancerAfter, rEthBalanceOfStrategy);
        assertApproxEqRel(rEthBalanceOfStrategy, rEthBalanceOfStrategyExpected, 2e16); // 2 percent
        assertApproxEqRel(ethValueOfStrategy, toDeposit, 2e16); // 2 percent
    }

    function test_redeemFromProtocol_withUniswap() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(rEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](7);
        slippages[3] = 100; // portion to swap on uniswap
        slippages[4] = 0; // portion to swap on balancer
        slippages[5] = 1; // min out
        slippages[6] = rEthToken.getRethValue(toDeposit) + 1; // ideal out
        rEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        rEthHoldingStrategy.exposed_mint(100);

        uint256 rEthBalanceOfStrategyBefore = rEthToken.balanceOf(address(rEthHoldingStrategy));
        uint256 rEthBalanceOfUniswapBefore = rEthToken.balanceOf(uniswapPool);
        uint256 rEthBalanceOfBalancerBefore = rEthToken.balanceOf(balancerVault);

        uint256 rEthRedeemedExpected = rEthBalanceOfStrategyBefore * 60 / 100;
        uint256 wethWithdrawnExpected = rEthToken.getEthValue(rEthRedeemedExpected);

        // act
        slippages[0] = 1;
        slippages[6] = wethWithdrawnExpected + 1; // ideal out - should be larger than internal price to swap
        rEthHoldingStrategy.exposed_redeemFromProtocol(assetGroup, 60, slippages);

        // assert
        uint256 rEthBalanceOfStrategyAfter = rEthToken.balanceOf(address(rEthHoldingStrategy));
        uint256 rEthBalanceOfUniswapAfter = rEthToken.balanceOf(uniswapPool);
        uint256 rEthBalanceOfBalancerAfter = rEthToken.balanceOf(balancerVault);
        uint256 wethBalanceOfStrategy = tokenWeth.balanceOf(address(rEthHoldingStrategy));

        assertGt(wethBalanceOfStrategy, 0);
        assertEq(rEthBalanceOfUniswapAfter - rEthBalanceOfUniswapBefore, rEthRedeemedExpected);
        assertEq(rEthBalanceOfBalancerAfter, rEthBalanceOfBalancerBefore);
        assertEq(rEthBalanceOfStrategyBefore - rEthBalanceOfStrategyAfter, rEthRedeemedExpected);
        assertApproxEqRel(wethBalanceOfStrategy, wethWithdrawnExpected, 2e16); // 2 percent
    }

    function test_redeemFromProtocol_withBalancer() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(rEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](7);
        slippages[3] = 0; // portion to swap on uniswap
        slippages[4] = 100; // portion to swap on balancer
        slippages[5] = 1; // min out
        slippages[6] = rEthToken.getRethValue(toDeposit) + 1; // ideal out
        rEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        rEthHoldingStrategy.exposed_mint(100);

        uint256 rEthBalanceOfStrategyBefore = rEthToken.balanceOf(address(rEthHoldingStrategy));
        uint256 rEthBalanceOfUniswapBefore = rEthToken.balanceOf(uniswapPool);
        uint256 rEthBalanceOfBalancerBefore = rEthToken.balanceOf(balancerVault);

        uint256 rEthRedeemedExpected = rEthBalanceOfStrategyBefore * 60 / 100;
        uint256 wethWithdrawnExpected = rEthToken.getEthValue(rEthRedeemedExpected);

        // act
        slippages[0] = 1;
        slippages[6] = wethWithdrawnExpected + 1; // ideal out - should be larger than internal price to swap
        rEthHoldingStrategy.exposed_redeemFromProtocol(assetGroup, 60, slippages);

        // assert
        uint256 rEthBalanceOfStrategyAfter = rEthToken.balanceOf(address(rEthHoldingStrategy));
        uint256 rEthBalanceOfUniswapAfter = rEthToken.balanceOf(uniswapPool);
        uint256 rEthBalanceOfBalancerAfter = rEthToken.balanceOf(balancerVault);
        uint256 wethBalanceOfStrategy = tokenWeth.balanceOf(address(rEthHoldingStrategy));

        assertGt(wethBalanceOfStrategy, 0);
        assertEq(rEthBalanceOfUniswapAfter, rEthBalanceOfUniswapBefore);
        assertEq(rEthBalanceOfBalancerAfter - rEthBalanceOfBalancerBefore, rEthRedeemedExpected);
        assertEq(rEthBalanceOfStrategyBefore - rEthBalanceOfStrategyAfter, rEthRedeemedExpected);
        assertApproxEqRel(wethBalanceOfStrategy, wethWithdrawnExpected, 2e16); // 2 percent
    }

    function test_redeemFromProtocol_withRocket() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(rEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](7);
        slippages[3] = 0; // portion to swap on uniswap
        slippages[4] = 100; // portion to swap on balancer
        slippages[5] = 1; // min out
        slippages[6] = rEthToken.getRethValue(toDeposit) + 1; // ideal out
        rEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        rEthHoldingStrategy.exposed_mint(100);

        uint256 rEthBalanceOfStrategyBefore = rEthToken.balanceOf(address(rEthHoldingStrategy));
        uint256 rEthBalanceOfUniswapBefore = rEthToken.balanceOf(uniswapPool);
        uint256 rEthBalanceOfBalancerBefore = rEthToken.balanceOf(balancerVault);

        uint256 rEthRedeemedExpected = rEthBalanceOfStrategyBefore * 60 / 100;
        uint256 wethWithdrawnExpected = rEthToken.getEthValue(rEthRedeemedExpected);

        // act
        slippages[0] = 1;
        slippages[6] = wethWithdrawnExpected; // ideal out - should not be larger than internal price to withdraw internally
        rEthHoldingStrategy.exposed_redeemFromProtocol(assetGroup, 60, slippages);

        // assert
        uint256 rEthBalanceOfStrategyAfter = rEthToken.balanceOf(address(rEthHoldingStrategy));
        uint256 rEthBalanceOfUniswapAfter = rEthToken.balanceOf(uniswapPool);
        uint256 rEthBalanceOfBalancerAfter = rEthToken.balanceOf(balancerVault);
        uint256 wethBalanceOfStrategy = tokenWeth.balanceOf(address(rEthHoldingStrategy));

        assertGt(wethBalanceOfStrategy, 0, "1");
        assertEq(rEthBalanceOfUniswapAfter, rEthBalanceOfUniswapBefore, "2");
        assertEq(rEthBalanceOfBalancerAfter, rEthBalanceOfBalancerBefore, "3");
        assertEq(rEthBalanceOfStrategyBefore - rEthBalanceOfStrategyAfter, rEthRedeemedExpected, "4");
        assertEq(wethBalanceOfStrategy, wethWithdrawnExpected, "5");
    }

    function test_emergencyWithdrawImpl_withUniswap() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(rEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](7);
        slippages[3] = 100; // portion to swap on uniswap
        slippages[4] = 0; // portion to swap on balancer
        slippages[5] = 1; // min out
        slippages[6] = rEthToken.getRethValue(toDeposit) + 1; // ideal out
        rEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        rEthHoldingStrategy.exposed_mint(100);

        uint256 rEthBalanceOfStrategyBefore = rEthToken.balanceOf(address(rEthHoldingStrategy));
        uint256 rEthBalanceOfUniswapBefore = rEthToken.balanceOf(uniswapPool);
        uint256 rEthBalanceOfBalancerBefore = rEthToken.balanceOf(balancerVault);

        uint256 wethWithdrawnExpected = rEthToken.getEthValue(rEthBalanceOfStrategyBefore);

        // act
        slippages = new uint256[](5);
        slippages[0] = 3;
        slippages[1] = 100; // portion to swap on uniswap
        slippages[2] = 0; // portion to swap on balancer
        slippages[3] = 1; // min out
        slippages[4] = wethWithdrawnExpected + 1; // ideal out - should be larger than internal price to swap
        rEthHoldingStrategy.exposed_emergencyWithdrawImpl(slippages, emergencyWithdrawalRecipient);

        // assert
        uint256 rEthBalanceOfStrategyAfter = rEthToken.balanceOf(address(rEthHoldingStrategy));
        uint256 rEthBalanceOfUniswapAfter = rEthToken.balanceOf(uniswapPool);
        uint256 rEthBalanceOfBalancerAfter = rEthToken.balanceOf(balancerVault);
        uint256 wethBalanceOfWithdrawalRecipient = tokenWeth.balanceOf(emergencyWithdrawalRecipient);
        uint256 wethBalanceOfStrategy = tokenWeth.balanceOf(address(rEthHoldingStrategy));

        assertGt(wethBalanceOfWithdrawalRecipient, 0);
        assertEq(rEthBalanceOfUniswapAfter - rEthBalanceOfUniswapBefore, rEthBalanceOfStrategyBefore);
        assertEq(rEthBalanceOfBalancerAfter, rEthBalanceOfBalancerBefore);
        assertEq(rEthBalanceOfStrategyAfter, 0);
        assertEq(wethBalanceOfStrategy, 0);
        assertApproxEqRel(wethBalanceOfWithdrawalRecipient, wethWithdrawnExpected, 2e16); // 2 percent
    }

    function test_getYieldPercentage() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(rEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](7);
        slippages[3] = 100; // portion to swap on uniswap
        slippages[4] = 0; // portion to swap on balancer
        slippages[5] = 1; // min out
        slippages[6] = rEthToken.getRethValue(toDeposit) + 1; // ideal out
        rEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        rEthHoldingStrategy.exposed_mint(100);

        // - generate 20% yield
        vm.record();
        uint256 totalEthBalanceBefore = rocketStorage.getUint(keccak256("network.balance.total"));
        uint256 priceBefore = rEthToken.getEthValue(1 ether);
        uint256 wethWithdrawnExpected =
            rEthToken.getEthValue(rEthToken.balanceOf(address(rEthHoldingStrategy))) * 120 / 100;

        (bytes32[] memory reads,) = vm.accesses(address(rocketStorage));
        vm.store(address(rocketStorage), reads[0], bytes32(totalEthBalanceBefore * 120 / 100));

        // act
        int256 yieldPercentage = rEthHoldingStrategy.exposed_getYieldPercentage(0);

        // assert
        uint256 totalEthBalanceAfter = rocketStorage.getUint(keccak256("network.balance.total"));
        uint256 priceAfter = rEthToken.getEthValue(1 ether);

        assertEq(totalEthBalanceAfter, totalEthBalanceBefore * 120 / 100);
        assertApproxEqAbs(priceAfter, priceBefore * 120 / 100, 10);
        assertEq(yieldPercentage, YIELD_FULL_PERCENT_INT / 5);

        slippages[0] = 1;
        slippages[6] = 1; // ideal out - should not be larger than internal price to withdraw internally
        rEthHoldingStrategy.exposed_redeemFromProtocol(assetGroup, 100, slippages);

        uint256 wethBalanceOfStrategy = tokenWeth.balanceOf(address(rEthHoldingStrategy));

        assertApproxEqAbs(wethBalanceOfStrategy, wethWithdrawnExpected, 10);
        assertApproxEqRel(wethBalanceOfStrategy, toDeposit * 120 / 100, 2e16); // 2 percent
    }

    function test_getUsdWorth() public {
        // arrange
        // - get weth to strategy
        uint256 toDeposit = 1 * tokenWethMultiplier;
        IWETH9(address(tokenWeth)).deposit{value: toDeposit}();
        tokenWeth.transfer(address(rEthHoldingStrategy), toDeposit);
        // - deposit
        uint256[] memory slippages = new uint256[](7);
        slippages[3] = 100; // portion to swap on uniswap
        slippages[4] = 0; // portion to swap on balancer
        slippages[5] = 1; // min out
        slippages[6] = rEthToken.getRethValue(toDeposit) + 1; // ideal out
        rEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);

        // act
        uint256 usdWorth = rEthHoldingStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        uint256 expectedWorth = priceFeedManager.assetToUsd(
            address(tokenWeth), rEthToken.getEthValue(rEthToken.balanceOf(address(rEthHoldingStrategy)))
        );
        uint256 expectedWorth2 = priceFeedManager.assetToUsd(address(tokenWeth), toDeposit);

        assertGt(usdWorth, 0);
        assertEq(usdWorth, expectedWorth);
        assertApproxEqRel(usdWorth, expectedWorth2, 2e16); // 2 percent
    }

    function _printState() internal {
        IRocketDepositPool rocketDepositPool = IRocketDepositPool(
            rocketStorage.getAddress(keccak256(abi.encodePacked("contract.address", "rocketDepositPool")))
        );
        IRocketDepositSettings rocketDepositSettings = IRocketDepositSettings(
            rocketStorage.getAddress(
                keccak256(abi.encodePacked("contract.address", "rocketDAOProtocolSettingsDeposit"))
            )
        );

        console2.log("rETH:", address(rEthToken));
        console2.log("  total collateral", rEthToken.getTotalCollateral());
        console2.log("rocket storage:", address(rocketStorage));
        console2.log("rocket deposit pool:", address(rocketDepositPool));
        console2.log("  balance:", rocketDepositPool.getBalance());
        console2.log("rocked deposit settings:", address(rocketDepositSettings));
        console2.log("  deposit enabled:", rocketDepositSettings.getDepositEnabled());
        console2.log("  max deposit pool size:", rocketDepositSettings.getMaximumDepositPoolSize());
        console2.log("");
    }
}

contract REthHoldingStrategyHarness is REthHoldingStrategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        uint256 assetGroupId_,
        IRocketSwapRouter rocketSwapRouter_,
        address weth_
    ) REthHoldingStrategy(assetGroupRegistry_, accessControl_, assetGroupId_, rocketSwapRouter_, weth_) {}
}

interface IRocketStorage {
    function getAddress(bytes32 _key) external returns (address);

    function getUint(bytes32 _key) external returns (uint256);
}

interface IRocketDepositPool {
    function getBalance() external returns (uint256);
}

interface IRocketDepositSettings {
    function getDepositEnabled() external returns (bool);

    function getMaximumDepositPoolSize() external returns (uint256);
}
