// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/managers/RewardManager.sol";
import "../src/interfaces/IRewardManager.sol";
import "./mocks/MockToken.sol";
import "./mocks/Constants.sol";
import "./RewardManager.t.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

contract RewardManagerConfigurationTests is RewardManagerTests {

    function test_Configuration_shouldAddOneToken() public {


        deal(address(rewardToken), vaultOwner, rewardAmount, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, rewardDuration, rewardAmount);
        vm.stopPrank();

        assertEq(1, rewardManager.rewardTokensCount(smartVault));
        assertEq(address(rewardToken), address(rewardManager.rewardTokens(smartVault, 0)));
        (
            uint32 configurationRewardsDuration,
            uint32 configurationPeriodFinish,
            uint192 configurationRewardRate, // rewards per second multiplied by accuracy
            uint32 configurationLastUpdateTime,
            uint224 configurationRewardPerTokenStored
        ) = rewardManager.rewardConfiguration(smartVault, IERC20(rewardToken));

        assertEq(rewardDuration, configurationRewardsDuration);

        uint256 rate = rewardAmount * 1 ether / rewardDuration;
        assertEq(rate, configurationRewardRate);
    }

    function test_Configruation_addingTwoRewardTokens() public {
        MockToken r2Token = new MockToken("R2", "R2");

        deal(address(rewardToken), vaultOwner, rewardAmount, true);
        deal(address(r2Token), vaultOwner, rewardAmount, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        r2Token.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, rewardDuration, rewardAmount);
        rewardManager.addToken(smartVault, r2Token, rewardDuration, rewardAmount);
        vm.stopPrank();

        assertEq(2, rewardManager.rewardTokensCount(smartVault));
        assertEq(address(rewardToken), address(rewardManager.rewardTokens(smartVault, 0)));
        assertEq(address(r2Token), address(rewardManager.rewardTokens(smartVault, 1)));
        (
            uint32 configurationRewardsDuration,
            uint32 configurationPeriodFinish,
            uint192 configurationRewardRate, // rewards per second multiplied by accuracy
            uint32 configurationLastUpdateTime,
            uint224 configurationRewardPerTokenStored
        ) = rewardManager.rewardConfiguration(smartVault, IERC20(rewardToken));

        assertEq(rewardDuration, configurationRewardsDuration);

        uint256 rate = rewardAmount * 1 ether / rewardDuration;
        assertEq(rate, configurationRewardRate);

        assertEq(rewardToken.balanceOf(address(rewardManager)), rewardAmount);
        assertEq(r2Token.balanceOf(address(rewardManager)), rewardAmount);
    }

    function test_Force_Removed_Tokens_Are_Not_Added() public {
        deal(address(rewardToken), vaultOwner, rewardAmount, true);

        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, rewardDuration, rewardAmount);
        rewardManager.forceRemoveReward(smartVault, rewardToken);
        vm.expectRevert(bytes("TOBL"));
        rewardManager.addToken(smartVault, rewardToken, rewardDuration, rewardAmount);
        vm.stopPrank();

        assertEq(true, rewardManager.tokenBlacklisted(smartVault, rewardToken));

        (
            uint32 configurationRewardsDuration,
            uint32 configurationPeriodFinish,
            uint192 configurationRewardRate, // rewards per second multiplied by accuracy
            uint32 configurationLastUpdateTime,
            uint224 configurationRewardPerTokenStored
        ) = rewardManager.rewardConfiguration(smartVault, IERC20(rewardToken));

        assertEq(0, configurationRewardsDuration);
        assertEq(0, configurationPeriodFinish);
        assertEq(0, configurationRewardRate);
        assertEq(0, configurationLastUpdateTime);
        assertEq(0, configurationRewardPerTokenStored);
    }
}
