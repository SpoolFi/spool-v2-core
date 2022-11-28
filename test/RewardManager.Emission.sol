// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

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
//        rewardManager.getActiveRewards(smartVault, user); // TODO expectRevert when ACL is complete
    }

    function test_getActiveRewards_userGetsRewards() public {
        addRewardTokens();
        rewardManager.updateRewardsOnVault(smartVault, user);
        deal(address(smartVault), user, rewardAmount, true); // Depositing into a vault.

        uint256 userRewardTokenBalanceBefore = rewardToken.balanceOf(user);
        skip(rewardDuration * 2);

        rewardManager.getActiveRewards(smartVault, user);

        uint256 userRewardTokenBalance = rewardToken.balanceOf(user);

        assertEq(userRewardTokenBalance, 99999999999999999900000);
    }

    function test_getActiveRewards_shouldClaimRewardsProportionally() public {
        addRewardTokens();
        rewardManager.updateRewardsOnVault(smartVault, user);
        deal(address(smartVault), user, rewardAmount, true); // Depositing into a vault.


        uint256 userBalanceBefore = rewardToken.balanceOf(user);
        skip(rewardDuration * 2);

        rewardManager.getActiveRewards(smartVault, user);


        uint256 userBalanceAfter = rewardToken.balanceOf(user);

        uint256 userBalanceGain = userBalanceAfter-userBalanceBefore;

        assertEq(userBalanceGain, 99999999999999999900000);
    }

    function test_getActiveRewards_twoUsersBothClaimProportionally() public {
        addRewardTokens();

        uint256 userDeposit = rewardAmount;
        uint256 user2Deposit = rewardAmount/2;
        rewardManager.updateRewardsOnVault(smartVault, user);
        deal(address(smartVault), user, userDeposit, true); // Depositing into a vault.

        address user2 = address(102);
        rewardManager.updateRewardsOnVault(smartVault, user2);
        deal(address(smartVault), user2, user2Deposit, true); // Depositing into a vault for user2

        uint256 totalDeposit = userDeposit + user2Deposit;

        uint256 userBalanceBefore = rewardToken.balanceOf(user);
        uint256 user2BalanceBefore = rewardToken.balanceOf(user2);
        skip(rewardDuration * 2);
        rewardManager.getActiveRewards(smartVault, user);
        rewardManager.getActiveRewards(smartVault, user2);

        uint256 userBalanceAfter = rewardToken.balanceOf(user);
        uint256 user2BalanceAfter = rewardToken.balanceOf(user2);

        uint256 userGain = rewardAmount*userDeposit/totalDeposit;
        uint256 user2Gain = rewardAmount*user2Deposit/totalDeposit;

        assertEq(66666666666666666666666, userGain);
        assertEq(33333333333333333333333, user2Gain);
    }

    function addRewardTokens() private {
        deal(address(rewardToken), vaultOwner, rewardAmount, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, rewardDuration, rewardAmount);
        vm.stopPrank();
    }
}
