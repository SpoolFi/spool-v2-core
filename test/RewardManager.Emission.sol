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
    function test_getActiveRewards_failsWhenNotInvokedController() public {
        RewardManager rewardManager = new RewardManager();

        uint256 rewardAmount = 100000 ether;
        uint32 rewardDuration = SECONDS_IN_DAY * 10;

        address smartVault = address(1);
        address user = address(100);

        MockToken rewardToken = new MockToken("REWARD", "REWARD");

        deal(address(rewardToken), user, rewardAmount, true);

        vm.startPrank(user);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, rewardDuration, rewardAmount / 2);
        //        rewardToken.transfer(address(rewardManager), rewardAmount/2);
        vm.stopPrank();

        vm.prank(user);
        //        rewardManager.getActiveRewards(smartVault, user); // TODO expectRevert when ACL is complete
    }

    function testA() public {
        RewardManager rewardManager = new RewardManager();

        uint256 rewardAmount = 1000000 ether;
        uint32 rewardDuration = SECONDS_IN_DAY * 10;
        address vaultOwner = address(100);
        address user = address(101);

        MockToken rewardToken = new MockToken("R", "R");
        MockToken smartVaultToken = new MockToken("SVT", "SVT");
        address smartVault = address(smartVaultToken);

        deal(address(rewardToken), vaultOwner, rewardAmount, true);
        deal(address(smartVault), user, rewardAmount, true); // Depositing into a vault.

        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, rewardDuration, rewardAmount);
        vm.stopPrank();

//        console.log(rewardManager.rewardPerToken(smartVault, rewardToken));
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


        console.log(userRewardTokenBalance);
    }
}
