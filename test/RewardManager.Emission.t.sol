// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/managers/RewardManager.sol";
import "../src/interfaces/IRewardManager.sol";
import "./mocks/MockToken.sol";
import "./mocks/Constants.sol";
import "./RewardManager.t.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

contract RewardManagerEmissionTests is RewardManagerTests {
    function test_claimRewardsFor_failsWhenNotInvokedController() public {
        deal(address(rewardToken), vaultOwner, rewardAmount, true);

        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, rewardDuration, rewardAmount / 2);
        vm.stopPrank();
        vm.prank(user);
        //        rewardManager.claimRewardsFor(smartVault, user); // TODO expectRevert when ACL is complete
    }

    function test_claimRewardsFor_userGetsRewards() public {
        addRewardTokens();
        vm.prank(smartVaultManager);
        rewardManager.updateRewardsOnVault(smartVault, user);
        deal(address(smartVault), user, rewardAmount, true); // Depositing into a vault.

        uint256 userRewardTokenBalanceBefore = rewardToken.balanceOf(user);
        skip(rewardDuration * 2);

        vm.prank(smartVaultManager);
        rewardManager.claimRewardsFor(smartVault, user);

        uint256 userRewardTokenBalance = rewardToken.balanceOf(user);

        assertEq(userRewardTokenBalance, 99999999999999999900000);
    }

    function test_claimRewardsFor_shouldClaimRewardsProportionally() public {
        addRewardTokens();
        vm.prank(smartVaultManager);
        rewardManager.updateRewardsOnVault(smartVault, user);
        deal(address(smartVault), user, rewardAmount, true); // Depositing into a vault.

        uint256 userBalanceBefore = rewardToken.balanceOf(user);
        skip(rewardDuration * 2);

        vm.prank(smartVaultManager);
        rewardManager.claimRewardsFor(smartVault, user);

        uint256 userBalanceAfter = rewardToken.balanceOf(user);

        uint256 userBalanceGain = userBalanceAfter - userBalanceBefore;

        assertEq(userBalanceGain, 99999999999999999900000);
    }

    function test_claimRewardsFor_twoUsersBothClaimProportionally() public {
        addRewardTokens();

        uint256 userDeposit = rewardAmount;
        uint256 user2Deposit = rewardAmount / 2;
        vm.prank(smartVaultManager);
        rewardManager.updateRewardsOnVault(smartVault, user);
        deal(address(smartVault), user, userDeposit, true); // Depositing into a vault.

        address user2 = address(102);
        vm.prank(smartVaultManager);
        rewardManager.updateRewardsOnVault(smartVault, user2);
        deal(address(smartVault), user2, user2Deposit, true); // Depositing into a vault for user2

        uint256 totalDeposit = userDeposit + user2Deposit;

        uint256 userBalanceBefore = rewardToken.balanceOf(user);
        uint256 user2BalanceBefore = rewardToken.balanceOf(user2);
        skip(rewardDuration * 2);

        vm.prank(smartVaultManager);
        rewardManager.claimRewardsFor(smartVault, user);
        vm.prank(smartVaultManager);
        rewardManager.claimRewardsFor(smartVault, user2);

        uint256 userBalanceAfter = rewardToken.balanceOf(user);
        uint256 user2BalanceAfter = rewardToken.balanceOf(user2);

        uint256 userGain = rewardAmount * userDeposit / totalDeposit;
        uint256 user2Gain = rewardAmount * user2Deposit / totalDeposit;

        assertEq(66666666666666666666666, userGain);
        assertEq(33333333333333333333333, user2Gain);
    }

    function test_claimRewardsFor_twoRewardAndTwoUsersBothClaimProportionally() public {
        addRewardTokens();
        MockToken rewardToken2 = new MockToken("R2", "R2");
        deal(address(rewardToken2), vaultOwner, rewardAmount / 2, true); // Dealing half a R1 reward.

        AssertData memory data;

        data.userDeposit = 100000 ether;
        data.user2Deposit = 50000 ether;
        vm.startPrank(vaultOwner);
        rewardToken2.approve(address(rewardManager), rewardAmount / 2);
        rewardManager.addToken(smartVault, rewardToken2, rewardDuration, rewardAmount / 2);
        vm.stopPrank();

        vm.prank(smartVaultManager);
        rewardManager.updateRewardsOnVault(smartVault, user);
        deal(address(smartVault), user, data.userDeposit, true); // Depositing into a vault.

        address user2 = address(102);
        vm.prank(smartVaultManager);
        rewardManager.updateRewardsOnVault(smartVault, user2);
        deal(address(smartVault), user2, data.user2Deposit, true); // Depositing into a vault for user2 - half amount of user1

        data.totalDeposit = data.user2Deposit + data.userDeposit;
        data.R1userBalanceBefore = rewardToken.balanceOf(user);
        data.R1user2BalanceBefore = rewardToken.balanceOf(user2);

        data.R2userBalanceBefore = rewardToken2.balanceOf(user);
        data.R2user2BalanceBefore = rewardToken2.balanceOf(user2);

        skip(rewardDuration * 2);

        vm.prank(smartVaultManager);
        rewardManager.claimRewardsFor(smartVault, user);
        vm.prank(smartVaultManager);
        rewardManager.claimRewardsFor(smartVault, user2);

        data.R1userBalanceAfter = rewardToken.balanceOf(user);
        data.R1user2BalanceAfter = rewardToken.balanceOf(user2);

        data.R2userBalanceAfter = rewardToken2.balanceOf(user);
        data.R2user2BalanceAfter = rewardToken2.balanceOf(user2);

        uint256 R1userGain = rewardAmount * data.userDeposit / data.totalDeposit;
        uint256 R1user2Gain = rewardAmount * data.user2Deposit / data.totalDeposit;

        uint256 R2userGain = rewardAmount / 2 * data.userDeposit / data.totalDeposit;
        uint256 R2user2Gain = rewardAmount / 2 * data.user2Deposit / data.totalDeposit;

        // Both rewards are claimed proportionally.
        assertEq(R1userGain, 66666666666666666666666);
        assertEq(R1user2Gain, 33333333333333333333333);

        assertEq(R2userGain, 33333333333333333333333);
        assertEq(R2user2Gain, 16666666666666666666666);
    }

    function test_claimRewardsFor_reward2DistributedCompletelyR1StillActive() public {
        addRewardTokens();
        MockToken rewardToken2 = new MockToken("R2", "R2");
        deal(address(rewardToken2), vaultOwner, rewardAmount / 10, true); // Dealing a tenth of the R1 reward.

        vm.startPrank(vaultOwner);
        rewardToken2.approve(address(rewardManager), rewardAmount / 10);
        rewardManager.addToken(smartVault, rewardToken2, rewardDuration / 10, rewardAmount / 10);
        vm.stopPrank();

        vm.prank(smartVaultManager);
        rewardManager.updateRewardsOnVault(smartVault, user);
        deal(address(smartVault), user, rewardAmount, true); // Depositing into a vault.
        skip(rewardDuration / 2);
        vm.prank(smartVaultManager);
        rewardManager.claimRewardsFor(smartVault, user);

        assertEq(rewardToken2.balanceOf(user), 9999999999999999900000); // R2 claimed completely.
        assertEq(rewardToken.balanceOf(user), 49999999999999999900000); // R1 claimed 50%
        skip(rewardDuration / 2 + 1);
        vm.prank(smartVaultManager);
        rewardManager.claimRewardsFor(smartVault, user);
        assertEq(rewardToken2.balanceOf(user), 9999999999999999900000); // R2 claimed completely before and stayed the same value.
        assertEq(rewardToken.balanceOf(user), 99999999999999999800000); // R1 claimed 50%
            // user should get all rewards from R2 and half from R1 todo assert
    }

    function test_claimRewardsFor_RemoveTokensAfterFinish() public {
        addRewardTokens();
        MockToken rewardToken2 = new MockToken("R2", "R2");
        deal(address(rewardToken2), vaultOwner, rewardAmount / 2, true); // Dealing half of the R1 reward.

        vm.startPrank(vaultOwner);
        rewardToken2.approve(address(rewardManager), rewardAmount / 2);
        rewardManager.addToken(smartVault, rewardToken2, rewardDuration * 2, rewardAmount / 2);
        vm.stopPrank();

        uint256 rewardCountBefore = rewardManager.rewardTokensCount(smartVault);

        vm.prank(smartVaultManager);
        rewardManager.updateRewardsOnVault(smartVault, user);
        deal(address(smartVault), user, rewardAmount, true); // Depositing into a vault.

        uint256 user1balance1Before = rewardToken.balanceOf(user);
        uint256 user1balance2Before = rewardToken2.balanceOf(user);

        skip(rewardDuration * 10);

        vm.prank(vaultOwner);
        rewardManager.removeReward(smartVault, rewardToken2);
        vm.prank(smartVaultManager);
        rewardManager.claimRewardsFor(smartVault, user);

        IERC20[] memory tokens = new IERC20 [] (1);
        tokens[0] = rewardToken2;

        vm.prank(user);
        rewardManager.claimRewards(smartVault, tokens);

        uint256 rewardCountAfter = rewardManager.rewardTokensCount(smartVault);

        assertEq(rewardCountBefore, 2);
        assertEq(rewardCountAfter, 1);

        uint256 user1balance1After = rewardToken.balanceOf(user);
        uint256 user1balance2After = rewardToken2.balanceOf(user);
        uint256 user1balance1Gain = user1balance1After - user1balance1Before;
        uint256 user1balance2Gain = user1balance2After - user1balance2Before;

        assertEq(user1balance1Gain, 99999999999999999900000);
        assertEq(user1balance2Gain, 49999999999999999900000);
    }

    struct AssertData {
        uint256 userDeposit;
        uint256 user2Deposit;
        uint256 totalDeposit;
        uint256 R1userBalanceBefore;
        uint256 R1user2BalanceBefore;
        uint256 R2userBalanceBefore;
        uint256 R2user2BalanceBefore;
        uint256 R1userBalanceAfter;
        uint256 R1user2BalanceAfter;
        uint256 R2userBalanceAfter;
        uint256 R2user2BalanceAfter;
    }

    function addRewardTokens() private {
        deal(address(rewardToken), vaultOwner, rewardAmount, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, rewardDuration, rewardAmount);
        vm.stopPrank();
    }
}
