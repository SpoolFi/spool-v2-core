// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {MockToken} from "./MockToken.sol";
import {MockProtocolNonAtomic} from "./MockStrategyNonAtomic.sol";
import "../../src/interfaces/Constants.sol";

contract MockProtocolNonAtomicTest is Test {
    address private alice;

    MockToken private tokenA;

    function setUp() public {
        alice = address(0xa);

        tokenA = new MockToken("Token A", "TA");

        deal(address(tokenA), alice, 1000 ether, true);
    }

    function test_investDivest_atomic() public {
        MockProtocolNonAtomic protocol = new MockProtocolNonAtomic(address(tokenA), ATOMIC_STRATEGY, 2_00);

        // invest
        vm.startPrank(alice);
        tokenA.approve(address(protocol), 100 ether);
        protocol.invest(100 ether);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(address(protocol)), 100 ether);
        assertEq(tokenA.balanceOf(alice), 900 ether);

        assertEq(protocol.totalUnderlying(), 98 ether);
        assertEq(protocol.fees(), 2 ether);
        assertEq(protocol.totalShares(), 98 ether * protocol.PROTOCOL_INITIAL_SHARE_MULTIPLIER());

        assertEq(protocol.shares(alice), 98 ether * protocol.PROTOCOL_INITIAL_SHARE_MULTIPLIER());

        // divest
        vm.startPrank(alice);
        protocol.divest(50 ether * protocol.PROTOCOL_INITIAL_SHARE_MULTIPLIER());
        vm.stopPrank();

        assertEq(tokenA.balanceOf(address(protocol)), 51 ether);
        assertEq(tokenA.balanceOf(alice), 949 ether);

        assertEq(protocol.totalUnderlying(), 48 ether);
        assertEq(protocol.fees(), 3 ether);
        assertEq(protocol.totalShares(), 48 ether * protocol.PROTOCOL_INITIAL_SHARE_MULTIPLIER());

        assertEq(protocol.shares(alice), 48 ether * protocol.PROTOCOL_INITIAL_SHARE_MULTIPLIER());
    }

    function test_investDivest_nonAtomic() public {
        MockProtocolNonAtomic protocol = new MockProtocolNonAtomic(address(tokenA), NON_ATOMIC_STRATEGY, 2_00);

        // invest
        vm.startPrank(alice);
        tokenA.approve(address(protocol), 100 ether);
        protocol.invest(100 ether);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(address(protocol)), 100 ether, "invest protocol balance");
        assertEq(tokenA.balanceOf(alice), 900 ether, "invest alice balance");

        assertEq(protocol.totalUnderlying(), 0 ether, "invest total underlying");
        assertEq(protocol.fees(), 0 ether, "invest fees");
        assertEq(protocol.totalShares(), 0 ether * protocol.PROTOCOL_INITIAL_SHARE_MULTIPLIER(), "invest total shares");
        assertEq(protocol.pendingInvestments(alice), 100 ether, "invest pending investments");

        assertEq(protocol.shares(alice), 0 ether * protocol.PROTOCOL_INITIAL_SHARE_MULTIPLIER(), "invest alice shares");

        // claim investment
        vm.startPrank(alice);
        protocol.claimInvestment();
        vm.stopPrank();

        assertEq(tokenA.balanceOf(address(protocol)), 100 ether, "invest claim protocol balance");
        assertEq(tokenA.balanceOf(alice), 900 ether, "invest claim alice balance");

        assertEq(protocol.totalUnderlying(), 98 ether, "invest claim total underlying");
        assertEq(protocol.fees(), 2 ether, "invest claim fees");
        assertEq(
            protocol.totalShares(), 98 ether * protocol.PROTOCOL_INITIAL_SHARE_MULTIPLIER(), "invest claim total shares"
        );
        assertEq(protocol.pendingInvestments(alice), 0 ether, "invest claim pending investments");

        assertEq(
            protocol.shares(alice), 98 ether * protocol.PROTOCOL_INITIAL_SHARE_MULTIPLIER(), "invest claim alice shares"
        );

        // divest
        vm.startPrank(alice);
        protocol.divest(50 ether * protocol.PROTOCOL_INITIAL_SHARE_MULTIPLIER());
        vm.stopPrank();

        assertEq(tokenA.balanceOf(address(protocol)), 100 ether, "divest protocol balance");
        assertEq(tokenA.balanceOf(alice), 900 ether, "divest alice balance");

        assertEq(protocol.totalUnderlying(), 98 ether, "divest total underlying");
        assertEq(protocol.fees(), 2 ether, "divest fees");
        assertEq(protocol.totalShares(), 98 ether * protocol.PROTOCOL_INITIAL_SHARE_MULTIPLIER(), "divest total shares");
        assertEq(
            protocol.pendingDivestments(alice),
            50 ether * protocol.PROTOCOL_INITIAL_SHARE_MULTIPLIER(),
            "divest pending divestments"
        );

        assertEq(protocol.shares(alice), 48 ether * protocol.PROTOCOL_INITIAL_SHARE_MULTIPLIER(), "divest alice shares");

        // claim divestment
        vm.startPrank(alice);
        protocol.claimDivestment();
        vm.stopPrank();

        assertEq(tokenA.balanceOf(address(protocol)), 51 ether, "divest claim protocol balance");
        assertEq(tokenA.balanceOf(alice), 949 ether, "divest claim alice balance");

        assertEq(protocol.totalUnderlying(), 48 ether, "divest claim total underlying");
        assertEq(protocol.fees(), 3 ether, "divest claim fees");
        assertEq(
            protocol.totalShares(), 48 ether * protocol.PROTOCOL_INITIAL_SHARE_MULTIPLIER(), "divest claim total shares"
        );
        assertEq(
            protocol.pendingDivestments(alice),
            0 ether * protocol.PROTOCOL_INITIAL_SHARE_MULTIPLIER(),
            "divest claim pending divestments"
        );

        assertEq(
            protocol.shares(alice), 48 ether * protocol.PROTOCOL_INITIAL_SHARE_MULTIPLIER(), "divest claim alice shares"
        );
    }
}
