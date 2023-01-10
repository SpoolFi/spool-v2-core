// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Test} from "forge-std/Test.sol";
import {SwapInfo} from "../src/interfaces/ISwapper.sol";
import {Swapper} from "../src/Swapper.sol";
import {Arrays} from "./libraries/Arrays.sol";
import {USD_DECIMALS_MULTIPLIER} from "./libraries/Constants.sol";
import {MockExchange} from "./mocks/MockExchange.sol";
import {MockPriceFeedManager} from "./mocks/MockPriceFeedManager.sol";
import {MockToken} from "./mocks/MockToken.sol";

contract SwapperTest is Test {
    address alice;
    address bob;

    Swapper swapper;

    MockToken tokenA;
    MockToken tokenB;
    MockToken tokenC;

    MockExchange exchangeAB;
    MockExchange exchangeBC;

    function setUp() public {
        alice = address(0xa);
        bob = address(0xb);

        swapper = new Swapper();

        tokenA = new MockToken("Token A", "TA");
        tokenB = new MockToken("Token B", "TB");
        tokenC = new MockToken("Token C", "TC");

        MockPriceFeedManager priceFeedManager = new MockPriceFeedManager();
        priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(tokenB), 1 * USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(tokenC), 1 * USD_DECIMALS_MULTIPLIER);

        exchangeAB = new MockExchange(tokenA, tokenB, priceFeedManager);
        exchangeBC = new MockExchange(tokenB, tokenC, priceFeedManager);

        deal(address(tokenA), address(exchangeAB), 100 ether, true);
        deal(address(tokenB), address(exchangeAB), 100 ether, true);
        deal(address(tokenB), address(exchangeBC), 100 ether, true);
        deal(address(tokenC), address(exchangeBC), 100 ether, true);

        deal(address(tokenA), alice, 10 ether, true);
    }

    function test_swap_shouldSwapCorrectly() public {
        address[] memory tokens = Arrays.toArray(address(tokenA), address(tokenB), address(tokenC));

        SwapInfo[] memory swapInfo = new SwapInfo[](2);
        swapInfo[0] = SwapInfo({
            swapTarget: address(exchangeAB),
            token: address(tokenA),
            amountIn: 10 ether,
            swapCallData: abi.encodeWithSelector(exchangeAB.swap.selector, address(tokenA), 10 ether, address(swapper))
        });
        swapInfo[1] = SwapInfo({
            swapTarget: address(exchangeBC),
            token: address(tokenB),
            amountIn: 10 ether,
            swapCallData: abi.encodeWithSelector(exchangeBC.swap.selector, address(tokenB), 10 ether, bob)
        });

        vm.startPrank(alice);
        tokenA.transfer(address(swapper), 10 ether);
        swapper.swap(tokens, swapInfo, bob);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(alice), 0);
        assertEq(tokenC.balanceOf(bob), 10 ether);
    }

    function test_swap_shouldRevertWhenSwapReverts() public {
        address[] memory tokens = Arrays.toArray(address(tokenA), address(tokenB), address(tokenC));

        SwapInfo[] memory swapInfo = new SwapInfo[](2);
        swapInfo[0] = SwapInfo({
            swapTarget: address(exchangeAB),
            token: address(tokenA),
            amountIn: 10 ether,
            swapCallData: abi.encodeWithSelector(exchangeAB.swap.selector, address(tokenA), 11 ether, address(swapper))
        });
        swapInfo[1] = SwapInfo({
            swapTarget: address(exchangeBC),
            token: address(tokenB),
            amountIn: 10 ether,
            swapCallData: abi.encodeWithSelector(exchangeBC.swap.selector, address(tokenB), 11 ether, bob)
        });

        vm.startPrank(alice);
        tokenA.transfer(address(swapper), 10 ether);

        vm.expectRevert();
        swapper.swap(tokens, swapInfo, bob);
        vm.stopPrank();
    }

    function test_swap_shouldReturnUnswappedTokens() public {
        address[] memory tokens = Arrays.toArray(address(tokenA), address(tokenB), address(tokenC));

        SwapInfo[] memory swapInfo = new SwapInfo[](2);
        swapInfo[0] = SwapInfo({
            swapTarget: address(exchangeAB),
            token: address(tokenA),
            amountIn: 9 ether,
            swapCallData: abi.encodeWithSelector(exchangeAB.swap.selector, address(tokenA), 9 ether, address(swapper))
        });
        swapInfo[1] = SwapInfo({
            swapTarget: address(exchangeBC),
            token: address(tokenB),
            amountIn: 8 ether,
            swapCallData: abi.encodeWithSelector(exchangeBC.swap.selector, address(tokenB), 8 ether, address(swapper))
        });

        vm.startPrank(alice);
        tokenA.transfer(address(swapper), 10 ether);
        swapper.swap(tokens, swapInfo, bob);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(alice), 0);
        assertEq(tokenA.balanceOf(bob), 1 ether);
        assertEq(tokenB.balanceOf(bob), 1 ether);
        assertEq(tokenC.balanceOf(bob), 8 ether);
    }
}
