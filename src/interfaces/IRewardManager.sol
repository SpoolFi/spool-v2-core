// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";

error AssetGroupToken(address token);
error RewardTokenBlacklisted(address token);
error RewardTokenAlreadyAdded(address token);
error InvalidEndTimestamp();
error InvalidRewardToken(address token);
error RewardTokenCapReached();
error RewardsNotFinished();
error NewRewardRateLessThanBefore();
error NewPeriodFinishLessThanBefore();
error TokenNotBlacklisted();

interface IRewardManager {
    /* ========== STRUCTS ========== */

    // The reward configuration struct, containing all the necessary data of a typical Synthetix StakingReward contract
    struct RewardConfiguration {
        uint32 rewardsDuration;
        uint32 periodFinish;
        uint192 rewardRate; // rewards per second multiplied by accuracy
        uint32 tokenAdded;
    }

    /* ========== FUNCTIONS ========== */

    /**
     * @notice Returns true if the given token is blacklisted
     * @param smartVault Smart vault for which the token should be blacklisted
     * @param token Token address
     */
    function tokenBlacklisted(address smartVault, IERC20 token) external view returns (bool);

    /**
     * @notice Forcibly remove a reward token for a given vault
     * @param token Token rewards to be removed
     */
    function forceRemoveReward(address smartVault, IERC20 token) external;

    /**
     * @notice Extend reward emissions
     * @param smartVault Smart vault address
     * @param reward Token reward amount
     * @param endTimestamp Reward end time
     */
    function extendRewardEmission(address smartVault, IERC20 token, uint256 reward, uint256 endTimestamp) external;

    /**
     * @notice Add reward token for vault
     * @param smartVault Vault address
     * @param token Token address
     * @param reward Token reward amount
     */
    function addToken(address smartVault, IERC20 token, uint256 endTimestamp, uint256 reward) external;

    /**
     * @notice Remove token from blacklist
     * @param smartVault Smart vault address
     * @param token Token address
     */
    function removeFromBlacklist(address smartVault, IERC20 token) external;

    /* ========== EVENTS ========== */

    event RewardAdded(
        address indexed smartVault,
        IERC20 indexed token,
        uint256 amount,
        uint256 duration,
        uint256 periodFinish,
        uint256 rewardRate
    );

    event RewardExtended(
        address indexed smartVault,
        IERC20 indexed token,
        uint256 amount,
        uint256 leftover,
        uint256 duration,
        uint256 periodFinish,
        uint256 rewardRate
    );

    event RewardRemoved(address indexed smartVault, IERC20 indexed token);
}
