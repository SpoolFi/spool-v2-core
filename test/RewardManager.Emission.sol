// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/managers/RewardManager.sol";
import "../src/interfaces/IRewardManager.sol";
import "./mocks/MockToken.sol";
import "./mocks/Constants.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

contract RewardManagerEmissionTests is Test {

    function test_getActiveRewards_Fails_When_Not_Invoked_From_Controller() public {
        RewardManager rewardManager = new RewardManager();

        uint256 rewardAmount = 100000 ether;
        uint32 rewardDuration = SECONDS_IN_DAY * 10;

        address smartVault = address(1);
        address user = address(100);

        MockToken rewardToken = new MockToken("REWARD", "REWARD");

        deal(address(rewardToken), user, rewardAmount, true);

        vm.startPrank(user);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, rewardDuration, rewardAmount/2);
//        rewardToken.transfer(address(rewardManager), rewardAmount/2);
        vm.stopPrank();

        vm.prank(user);
        rewardManager.getActiveRewards(smartVault, user); // TODO expectRevert when ACL is complete
    }

    function test() public {
        RewardManager rewardManager = new RewardManager();

        uint256 rewardAmount = 100000 ether;
        uint32 rewardDuration = SECONDS_IN_DAY * 10;

        address smartVault = address(1);
        address vaultOwner = address(100);
        address user = address(101);

        MockToken rewardToken = new MockToken("R", "R");
        MockToken underlying = new MockToken("U", "U");
        deal(address(rewardToken), vaultOwner, rewardAmount, true);
        deal(address(underlying), user, rewardAmount, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, rewardDuration, rewardAmount);
        vm.stopPrank();

        vm.startPrank(user);
        underlying.transfer(address(rewardManager), rewardAmount);
        vm.stopPrank();

        console.log(underlying.balanceOf(address(rewardManager)));
        console.log(underlying.balanceOf(address(user)));
        console.log("current block.timestamp:");
        console.log(block.timestamp);
        skip(rewardDuration * 2);

//        vm.prank(user);
        rewardManager.getActiveRewards(smartVault, user);
        console.log("underlying token <rewardManager> balance");

        console.log(underlying.balanceOf(address(rewardManager)));
        console.log("underlying token <user> balance");

        console.log(underlying.balanceOf(address(user)));
        console.log("reward token <rewardManager> balance");
        console.log(rewardToken.balanceOf(address(rewardManager)));
        console.log("reward token <user> balance");
        console.log(rewardToken.balanceOf(address(user)));

        console.log(block.timestamp);
        (uint32 configurationRewardsDuration,
        uint32 configurationPeriodFinish,
        uint192 configurationRewardRate, // rewards per second multiplied by accuracy
        uint32 configurationLastUpdateTime,
        uint224 configurationRewardPerTokenStored)  = rewardManager.rewardConfiguration(smartVault, IERC20(rewardToken));
        console.log(configurationRewardsDuration);
        console.log(configurationPeriodFinish);
        console.log(configurationRewardRate);
        console.log(configurationLastUpdateTime);
        console.log(configurationRewardPerTokenStored);


        console.log(rewardManager.earned(smartVault, IERC20(rewardToken), user));
    }
}