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

contract RewardManagerEmissionTests is RewardManagerTests {

    function test_getActiveRewards_failsWhenNotInvokedController() public {
        deal(address(rewardToken), vaultOwner, rewardAmount, true);

        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, rewardDuration, rewardAmount / 2);
        vm.stopPrank();

        vm.prank(user);
        //rewardManager.getActiveRewards(smartVault, user); // TODO expectRevert when ACL is complete
    }

    function test_getActiveRewards_userGetsRewards() public {
        deal(address(rewardToken), vaultOwner, rewardAmount, true);
        deal(address(smartVault), user, rewardAmount, true); // Depositing into a vault.
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, rewardDuration, rewardAmount);
        vm.stopPrank();

        uint256 userRewardTokenBalanceBefore = rewardToken.balanceOf(user);
        console.log(userRewardTokenBalanceBefore);
        skip(rewardDuration * 2);
//        console.log(rewardManager.rewardPerToken(smartVault, rewardToken));
        //    function rewardPerToken(address smartVault, IERC20 token) public view returns (uint224) {

//        console.log(rewardManager.earned(smartVault, rewardToken, user));

        //        vm.prank(user);
        rewardManager.getActiveRewards(smartVault, user);

        uint256 userRewardTokenBalance = rewardToken.balanceOf(user);
        assertGt(userRewardTokenBalance, 0);
    }
}
