// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/interfaces/IERC4626.sol";

import "../../../src/external/interfaces/weth/IWETH9.sol";
import "../../../src/libraries/SpoolUtils.sol";
import "../../../src/interfaces/Constants.sol";
import "../../../src/strategies/ApxEthHoldingStrategy.sol";
import "../../fixtures/TestFixture.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../mocks/MockExchange.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";
import "../EthereumForkConstants.sol";

contract ApxEthHoldingStrategyTest is TestFixture, ForkTestFixture {
    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    ApxEthHoldingStrategyHarness apxEthHoldingStrategy;
    address implementation;
    IERC20Metadata poolToken;
    MockExchange pool_underlying_Exchange;
    IERC4626 vault;

    bytes eventSig = "SwapEstimation(address,address,uint256)";

    // ******* Underlying specific constants **************
    IERC20Metadata underlyingToken = IERC20Metadata(WETH);
    IPirexEth public pirexEth = IPirexEth(PIREXETH);
    uint256 toDeposit = 100000 ether;
    uint256 underlyingPriceUSD = 1001;
    // ****************************************************

    function setUpForkTestFixture() internal override {
        mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK_EXTENDED_5);
    }

    function setUp() public {
        // setup
        setUpForkTestFixture();
        vm.selectFork(mainnetForkId);
        setUpBase();

        assetGroup = Arrays.toArray(address(underlyingToken));
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        // create and initialize strategy
        implementation = address(
            new ApxEthHoldingStrategyHarness(
            assetGroupRegistry,
            accessControl,
            swapper,
            WETH
            )
        );

        apxEthHoldingStrategy = ApxEthHoldingStrategyHarness(payable(address(new ERC1967Proxy(implementation, ""))));

        apxEthHoldingStrategy.initialize("ApxEthHoldingStrategy", assetGroupId, pirexEth);

        // grant strategy role to the strategy
        vm.prank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(apxEthHoldingStrategy));

        // deal the strategy the underlying token
        _deal(address(underlyingToken), address(apxEthHoldingStrategy), toDeposit);

        // set the protocol token
        poolToken = IERC20Metadata(pirexEth.pxEth());
        vault = IERC4626(pirexEth.autoPxEth());

        // create a mock exchange for inter pool/underlying transfer
        pool_underlying_Exchange = new MockExchange(poolToken, underlyingToken, priceFeedManager);
        _deal(address(poolToken), address(pool_underlying_Exchange), 1_000_000 * 10 ** poolToken.decimals());
        _deal(address(underlyingToken), address(pool_underlying_Exchange), 1_000_000 * 10 ** underlyingToken.decimals());

        swapper.updateExchangeAllowlist(Arrays.toArray(address(pool_underlying_Exchange)), Arrays.toArray(true));

        // set exchange rate 1 to 1 for easier testing
        priceFeedManager.setExchangeRate(address(underlyingToken), USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(poolToken), USD_DECIMALS_MULTIPLIER);

        assetGroupExchangeRates = SpoolUtils.getExchangeRates(Arrays.toArray(address(poolToken)), priceFeedManager);
    }

    function _deal(address token, address to, uint256 amount) private {
        if (token == WETH) {
            deal(to, amount);
            vm.prank(to);
            IWETH9(WETH).deposit{value: amount}();
            return;
        } else {
            deal(token, to, amount, true);
        }
    }

    function _underlyingBalanceOfStrategy() private view returns (uint256) {
        uint256 balance = vault.balanceOf(address(apxEthHoldingStrategy));
        return vault.previewRedeem(balance);
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

    function _deposit() internal {
        vm.startPrank(address(0), address(0));
        uint256[] memory slippages = new uint256[](1);
        apxEthHoldingStrategy.exposed_depositToProtocol(assetGroup, Arrays.toArray(toDeposit), slippages);
        vm.stopPrank();
    }

    function _redeem(uint256 toRedeem) internal {
        uint256 snapshot = vm.snapshot();
        uint256[] memory slippages = new uint256[](1);
        slippages[0] = 1;
        vm.startPrank(address(0), address(0));
        vm.recordLogs();
        apxEthHoldingStrategy.exposed_redeemFromProtocol(assetGroup, toRedeem, slippages);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory data;
        bytes32 sig = keccak256(eventSig);
        bool found = false;
        for (uint256 i; i < entries.length; i++) {
            if (entries[i].topics[0] == sig) {
                data = entries[i].data;
                found = true;
                break;
            }
        }
        if (!found) {
            revert("event not found");
        }

        vm.stopPrank();
        vm.revertTo(snapshot);
        apxEthHoldingStrategy.exposed_redeemFromProtocol(
            assetGroup, toRedeem, buildSlippages(pool_underlying_Exchange, data)
        );
    }

    function _emergencyWithdraw() internal {
        uint256 snapshot = vm.snapshot();
        uint256[] memory slippages = new uint256[](1);
        slippages[0] = 1;
        vm.startPrank(address(0), address(0));
        vm.recordLogs();
        apxEthHoldingStrategy.exposed_emergencyWithdrawImpl(slippages, emergencyWithdrawalRecipient);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory data;
        bytes32 sig = keccak256(eventSig);
        bool found = false;
        for (uint256 i; i < entries.length; i++) {
            if (entries[i].topics[0] == sig) {
                data = entries[i].data;
                found = true;
                break;
            }
        }
        if (!found) {
            revert("event not found");
        }

        vm.stopPrank();
        vm.revertTo(snapshot);
        apxEthHoldingStrategy.exposed_emergencyWithdrawImpl(
            buildSlippages(pool_underlying_Exchange, data), emergencyWithdrawalRecipient
        );
    }

    function test_depositToProtocol() public {
        _deposit();

        // assert
        // act
        uint256[] memory getUnderlyingAssetAmounts = apxEthHoldingStrategy.getUnderlyingAssetAmounts();
        uint256 getUnderlyingAssetAmount = getUnderlyingAssetAmounts[0];
        uint256 diff = 2e15; // .2%
        assertApproxEqRel(getUnderlyingAssetAmount, toDeposit, diff);
    }

    function test_redeemFromProtocol() public {
        // arrange
        uint256 mintedShares = 100;
        uint256 withdrawnShares = 60;

        // - need to deposit into the protocol
        _deposit();
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        apxEthHoldingStrategy.exposed_mint(mintedShares);

        uint256 strategyDepositBalanceBefore = _underlyingBalanceOfStrategy();

        // act
        _redeem(withdrawnShares);

        // assert
        uint256 strategyDepositBalanceAfter = _underlyingBalanceOfStrategy();

        assertApproxEqAbs(
            strategyDepositBalanceBefore - strategyDepositBalanceAfter, toDeposit * withdrawnShares / mintedShares, 1
        );
        assertApproxEqAbs(strategyDepositBalanceAfter, toDeposit * (mintedShares - withdrawnShares) / mintedShares, 1);
    }

    function test_emergencyWithdrawImpl() public {
        // arrange
        uint256 mintedShares = 100;

        // - need to deposit into the protocol
        _deposit();
        // - normal deposit into protocol would mint SSTs
        //   which are needed when determining how much to redeem
        apxEthHoldingStrategy.exposed_mint(mintedShares);

        uint256 poolTokenBalanceOfVaultBefore = poolToken.balanceOf(address(vault));

        // act
        _emergencyWithdraw();

        // assert
        uint256 poolTokenBalanceOfVaultAfter = poolToken.balanceOf(address(vault));
        uint256 underlyingTokenBalanceOfEmergencyWithdrawalRecipient =
            underlyingToken.balanceOf(emergencyWithdrawalRecipient);

        uint256 poolTokenBalanceOfStrategy = poolToken.balanceOf(address(apxEthHoldingStrategy));
        uint256 vaultBalanceOfStrategy = vault.balanceOf(address(apxEthHoldingStrategy));

        assertApproxEqAbs(poolTokenBalanceOfVaultBefore - poolTokenBalanceOfVaultAfter, toDeposit, 1);
        assertApproxEqAbs(underlyingTokenBalanceOfEmergencyWithdrawalRecipient, toDeposit, 1);
        assertEq(poolTokenBalanceOfStrategy, 0);
        assertEq(vaultBalanceOfStrategy, 0);
    }

    //// base yield
    function test_getYieldPercentage() public {
        // - need to deposit into the protocol
        _deposit();

        uint256 balanceOfStrategyBefore = _underlyingBalanceOfStrategy();

        // - yield is gathered over time
        vm.warp(block.timestamp + 52 weeks);

        // act
        int256 yieldPercentage = apxEthHoldingStrategy.exposed_getYieldPercentage(0);

        // assert
        uint256 balanceOfStrategyAfter = _underlyingBalanceOfStrategy();

        uint256 calculatedYield = balanceOfStrategyBefore * uint256(yieldPercentage) / YIELD_FULL_PERCENT;
        uint256 expectedYield = balanceOfStrategyAfter - balanceOfStrategyBefore;

        assertGt(yieldPercentage, 0);
        assertApproxEqRel(calculatedYield, expectedYield, 10 ** 11);
    }

    function test_getUsdWorth() public {
        // - need to deposit into the protocol
        _deposit();

        // act
        uint256 usdWorth = apxEthHoldingStrategy.exposed_getUsdWorth(assetGroupExchangeRates, priceFeedManager);

        // assert
        assertApproxEqRel(usdWorth, priceFeedManager.assetToUsd(address(underlyingToken), toDeposit), 1e7);
    }
}

// Exposes protocol-specific functions for unit-testing.
contract ApxEthHoldingStrategyHarness is ApxEthHoldingStrategy, StrategyHarness {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        address weth_
    ) ApxEthHoldingStrategy(assetGroupRegistry_, accessControl_, swapper_, weth_) {}
}
