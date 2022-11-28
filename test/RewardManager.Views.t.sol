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

contract RewardManagerViewsTests is RewardManagerTests {
    function _setUp() public {
        deal(address(rewardToken), vaultOwner, rewardAmount, true);
        rewardManager.updateRewardsOnVault(smartVault, user);
        deal(address(smartVault), user, rewardAmount, true); // Depositing into a vault.
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, rewardDuration, rewardAmount);
        vm.stopPrank();
    }

    function test_lastTimeRewardApplicable_returnsTimeWhenRewardsEnded() public {
        _setUp();
        assertEq(rewardManager.lastTimeRewardApplicable(smartVault, rewardToken), 1);
        skip(rewardDuration * 2);
        rewardManager.getActiveRewards(smartVault, user);
        assertEq(rewardManager.lastTimeRewardApplicable(smartVault, rewardToken), 864001);
        skip(1000);
        assertEq(rewardManager.lastTimeRewardApplicable(smartVault, rewardToken), 864001);
    }

    function test_rewardPerToken_returnsTimeWhenRewardsEnded() public {
        _setUp();
        skip(1);
        uint256 rpt = 1157407407407;
        assertEq(rewardManager.rewardPerToken(smartVault, rewardToken), rpt);
        skip(1);
        assertEq(rewardManager.rewardPerToken(smartVault, rewardToken), rpt * 2);
    }

    function test_rewardPerToken_secondUserDepositsLater() public {
        _setUp();

        skip(1);
        uint256 rpt = 1157407407407;
        assertEq(rewardManager.rewardPerToken(smartVault, rewardToken), rpt);
        skip(1000);
        address secondUser = address(122);

        rewardManager.updateRewardsOnVault(smartVault, secondUser);
        deal(address(smartVault), secondUser, rewardAmount, true); // "Depositing" into a vault.

        assertEq(rewardManager.earned(smartVault, rewardToken, user), 115856481481481400000);
        assertEq(rewardManager.earned(smartVault, rewardToken, secondUser), 0); // Second user has not earned any rewards yet.
        skip(1000);
        assertEq(rewardManager.earned(smartVault, rewardToken, user), 173726851851851700000);

        assertEq(rewardManager.earned(smartVault, rewardToken, secondUser), 57870370370370300000);
    }
}
