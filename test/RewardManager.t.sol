// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/managers/RewardManager.sol";
import "../src/interfaces/IRewardManager.sol";
import "./mocks/MockToken.sol";
import "./mocks/Constants.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

contract RewardManagerTest is Test {

    function test_Configuration_ShouldAddOneToken() public {
        RewardManager rewardManager = new RewardManager();

        uint256 rewardAmount = 100000 ether;
        uint32 rewardDuration = SECONDS_IN_DAY * 10;

        address smartVault = address(1);
        address user = address(100);

        MockToken mockToken = new MockToken("REWARD", "REWARD");

        deal(address(mockToken), user, rewardAmount, true);
        vm.startPrank(user);
        mockToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, mockToken, rewardDuration, rewardAmount);
        vm.stopPrank();

        assertEq(1, rewardManager.rewardTokensCount(smartVault));
        assertEq(address(mockToken), address(rewardManager.rewardTokens(smartVault, 0)));
        (uint32 configurationRewardsDuration,
        uint32 configurationPeriodFinish,
        uint192 configurationRewardRate, // rewards per second multiplied by accuracy
        uint32 configurationLastUpdateTime,
        uint224 configurationRewardPerTokenStored)  = rewardManager.rewardConfiguration(smartVault, IERC20(mockToken));


        assertEq(rewardDuration, configurationRewardsDuration);

        uint256 rate = rewardAmount * 1 ether / rewardDuration;
        assertEq(rate, configurationRewardRate);
    }

    function test_Adding_Two_Tokens() public {
        RewardManager rewardManager = new RewardManager();

        uint256 rewardAmount = 100000 ether;
        uint32 rewardDuration = SECONDS_IN_DAY * 10;

        address smartVault = address(1);
        address user = address(100);
        MockToken rToken = new MockToken("R", "R");
        MockToken r2Token = new MockToken("R2", "R2");
        deal(address(rToken), user, rewardAmount, true);
        deal(address(r2Token), user, rewardAmount, true);
        vm.startPrank(user);
        rToken.approve(address(rewardManager), rewardAmount);
        r2Token.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rToken, rewardDuration, rewardAmount);
        rewardManager.addToken(smartVault, r2Token, rewardDuration, rewardAmount);
        vm.stopPrank();

        assertEq(2, rewardManager.rewardTokensCount(smartVault));
        assertEq(address(rToken), address(rewardManager.rewardTokens(smartVault, 0)));
        assertEq(address(r2Token), address(rewardManager.rewardTokens(smartVault, 1)));
        (uint32 configurationRewardsDuration,
        uint32 configurationPeriodFinish,
        uint192 configurationRewardRate, // rewards per second multiplied by accuracy
        uint32 configurationLastUpdateTime,
        uint224 configurationRewardPerTokenStored)  = rewardManager.rewardConfiguration(smartVault, IERC20(rToken));


        assertEq(rewardDuration, configurationRewardsDuration);

        uint256 rate = rewardAmount * 1 ether / rewardDuration;
        assertEq(rate, configurationRewardRate);

        assertEq(rToken.balanceOf(address(rewardManager)), rewardAmount);
        assertEq(r2Token.balanceOf(address(rewardManager)), rewardAmount);
    }
}