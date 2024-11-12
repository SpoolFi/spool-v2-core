// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../../src/access/SpoolAccessControl.sol";
import "../../../../src/interfaces/Constants.sol";
import "../../../../src/libraries/SpoolUtils.sol";
import "../../../../src/managers/AssetGroupRegistry.sol";
import "../../../../src/strategies/mocks/MockProtocol.sol";
import "../../../external/interfaces/IUSDC.sol";
import "../../../libraries/Arrays.sol";
import "../../../libraries/Constants.sol";
import "../../../mocks/MockExchange.sol";
import "../../../fixtures/TestFixture.sol";
import "../../ForkTestFixture.sol";
import "../../StrategyHarness.sol";
import "../SepoliaForkConstants.sol";

contract MockProtocolTest is TestFixture, ForkTestFixture {
    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;
    MockProtocol private protocol;
    address user1 = address(0x1);
    address user2 = address(0x2);

    uint256 apy = 800;
    IERC20Metadata tokenUnderlying = IERC20Metadata(USDC_SEPOLIA);

    function setUp() public {
        setUpForkTestFixtureSepolia();
        vm.selectFork(mainnetForkId);
        setUpBase();

        protocol = new MockProtocol(address(tokenUnderlying), apy);

        vm.prank(address(user1));
        tokenUnderlying.approve(address(protocol), type(uint256).max);

        vm.prank(address(user2));
        tokenUnderlying.approve(address(protocol), type(uint256).max);
    }

    function _deal(address to, uint256 amount) private {
        IUSDC(address(tokenUnderlying)).mint(to, amount);
    }

    function _protocolBalance() private view returns (uint256) {
        return tokenUnderlying.balanceOf(address(protocol));
    }

    function test_deposit() public {
        uint256 amount = 1000;
        _deal(user1, amount);
        _deal(user2, amount);

        vm.prank(address(user1));
        protocol.deposit(amount);

        vm.prank(address(user2));
        protocol.deposit(amount);

        assertEq(_protocolBalance(), amount * 2);
        assertEq(protocol.balanceOf(user1), amount);
        assertEq(protocol.balanceOf(user2), amount);
    }

    function test_apy() public {
        uint256 amount = 1000;
        uint256 yield = amount * apy / FULL_PERCENT;

        _deal(user1, amount);
        _deal(user2, amount);

        vm.prank(address(user1));
        protocol.deposit(amount);

        vm.prank(address(user2));
        protocol.deposit(amount);

        vm.warp(block.timestamp + 52 weeks);

        assertEq(protocol.rewards(), yield * 2);

        vm.prank(address(user1));
        protocol.withdraw(amount);

        vm.prank(address(user2));
        protocol.withdraw(amount);

        assertEq(_protocolBalance(), 0);
        assertEq(protocol.balanceOf(user1), 0);
        assertEq(protocol.balanceOf(user2), 0);
        assertEq(tokenUnderlying.balanceOf(address(user1)), amount + yield);
        assertEq(tokenUnderlying.balanceOf(address(user2)), amount + yield);
    }

    function test_apy2() public {
        uint256 amount = 1000;
        uint256 yield = amount * apy / FULL_PERCENT;

        _deal(user1, amount);
        _deal(user2, amount);

        vm.prank(address(user1));
        protocol.deposit(amount);

        vm.warp(block.timestamp + 26 weeks);

        uint256 cumulativeYield = protocol.rewards();

        vm.prank(address(user2));
        protocol.deposit(amount);

        vm.warp(block.timestamp + 26 weeks);

        cumulativeYield += protocol.rewards();
        assertEq(cumulativeYield, ((yield * 3) / 2));

        vm.prank(address(user1));
        protocol.withdraw(amount);

        vm.prank(address(user2));
        protocol.withdraw(amount);

        assertEq(_protocolBalance(), 0);
        assertEq(protocol.balanceOf(user1), 0);
        assertEq(protocol.balanceOf(user2), 0);
        assertEq(tokenUnderlying.balanceOf(address(user1)), amount + yield);
        assertEq(tokenUnderlying.balanceOf(address(user2)), amount + (yield / 2));
    }
}
