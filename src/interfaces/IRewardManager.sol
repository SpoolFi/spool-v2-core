// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";

interface IRewardManager {
    /* ========== STRUCTS ========== */
    // The reward configuration struct, containing all the necessary data of a typical Synthetix StakingReward contract
    struct RewardConfiguration {
        uint32 rewardsDuration;
        uint32 periodFinish;
        uint192 rewardRate; // rewards per second multiplied by accuracy
        uint32 lastUpdateTime;
        uint224 rewardPerTokenStored;
        mapping(address => uint256) userRewardPerTokenPaid;
        mapping(address => uint256) rewards;
    }

    // dodaj vse funkcije ki so public in external

    /* ========== FUNCTIONS ========== */

    function getActiveRewards(address smartVault, address account) external;
    function tokenBlacklisted(address smartVault, IERC20 token) external view returns (bool);

    /* ========== EVENTS ========== */

    event RewardPaid(address smartVault, IERC20 token, address indexed user, uint256 reward);
    event RewardAdded(address smartVault, IERC20 indexed token, uint256 amount, uint256 duration);
    event RewardExtended(
        address smartVault,
        IERC20 indexed token,
        uint256 amount,
        uint256 leftover,
        uint256 duration,
        uint32 periodFinish
    );
    event RewardRemoved(address smartVault, IERC20 indexed token);
    event PeriodFinishUpdated(address smartVault, IERC20 indexed token, uint32 periodFinish);
}
