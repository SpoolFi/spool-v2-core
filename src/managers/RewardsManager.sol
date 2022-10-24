// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "../interfaces/IRewardManager.sol";
import "../utils/Math.sol";

import "@openzeppelin/security/ReentrancyGuard.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";


    struct User { // TODO: Should this be some base class?
    uint128 instantDeposit; // used for calculating rewards
    uint128 activeDeposit; // users deposit after deposit process and claim
    uint128 owed; // users owed underlying amount after withdraw has been processed and claimed
    uint128 withdrawnDeposits; // users withdrawn deposit, used to calculate performance fees
    uint128 shares; // users shares after deposit process and claim
}

contract  RewardManager is IRewardManager, ReentrancyGuard {
    using SafeERC20 for IERC20;
    /* ========== CONSTANTS ========== */

    /// @notice Number of vault incentivized tokens
    mapping(address => uint8) public rewardTokensCount;

    /// @notice User vault state values
    mapping(address => mapping(address => User)) public users;

    /// @notice Total instant deposit, used to calculate vault reward incentives
    mapping(address => uint128) public totalInstantDeposit;

    /// @notice Multiplier used when dealing reward calculations
    uint256 constant private REWARD_ACCURACY = 1e18;

    /* ========== STATE VARIABLES ========== */

    /// @notice All reward tokens supported by the contract
    mapping(address => mapping(uint256 => IERC20)) public rewardTokens;

    /// @notice Vault reward token incentive configuration
    mapping(address => mapping(IERC20 => RewardConfiguration)) public rewardConfiguration;

    mapping(address => mapping(IERC20 => bool)) tokenBlacklist;
    /* ========== VIEWS ========== */

    function lastTimeRewardApplicable(address smartVault, IERC20 token)
    public
    view
    returns (uint32) {
        return uint32(Math.min(block.timestamp, rewardConfiguration[smartVault][token].periodFinish));
    }

    /// @notice Blacklisted force-removed tokens
    function tokenBlacklisted(address smartVault, IERC20 token) view external returns(bool) {
        return tokenBlacklist[smartVault][token];
    }

    function rewardPerToken(address smartVault, IERC20 token) public view returns (uint224) {
        RewardConfiguration storage config = rewardConfiguration[smartVault][token];

        if (totalInstantDeposit[smartVault] == 0)
            return config.rewardPerTokenStored;

        uint256 timeDelta = lastTimeRewardApplicable(smartVault, token) - config.lastUpdateTime;

        if (timeDelta == 0)
            return config.rewardPerTokenStored;

        return
        SafeCast.toUint224(
            config.rewardPerTokenStored +
            ((timeDelta
            * config.rewardRate)
            / totalInstantDeposit[smartVault])
        );
    }

    function earned(address smartVault, IERC20 token, address account)
    public
    view
    returns (uint256)
    {
        RewardConfiguration storage config = rewardConfiguration[smartVault][token];

        uint256 userShares = users[smartVault][account].instantDeposit;

        if (userShares == 0)
            return config.rewards[account];

        uint256 userRewardPerTokenPaid = config.userRewardPerTokenPaid[account];

        return
        ((userShares *
        (rewardPerToken(smartVault, token) - userRewardPerTokenPaid))
        / REWARD_ACCURACY)
        + config.rewards[account];
    }

    function getRewardForDuration(address smartVault, IERC20 token)
    external
    view
    returns (uint256)
    {
        RewardConfiguration storage config = rewardConfiguration[smartVault][token];
        return uint256(config.rewardRate) * config.rewardsDuration;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function getRewards(address smartVault, IERC20[] memory tokens) external nonReentrant {
        for (uint256 i; i < tokens.length; i++) {
            _getReward(smartVault, tokens[i], msg.sender);
        }
    }

    function getActiveRewards(address smartVault, address account) external override onlyController nonReentrant {
        uint256 _rewardTokensCount = rewardTokensCount[smartVault];
        for (uint256 i; i < _rewardTokensCount; i++) {
            _getReward(smartVault, rewardTokens[smartVault][i], account);
        }
    }

    function _getReward(address smartVault, IERC20 token, address account)
    internal
    updateReward(smartVault, token, account)
    {
        RewardConfiguration storage config = rewardConfiguration[smartVault][token];

        require(
            config.rewardsDuration != 0,
            "BTK"
        );

        uint256 reward = config.rewards[account];
        if (reward > 0) {
            config.rewards[account] = 0;
            token.safeTransfer(account, reward);
            emit RewardPaid(token, account, reward);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Allows a new token to be added to the reward system
     *
     * @dev
     * Emits an {TokenAdded} event indicating the newly added reward token
     * and configuration
     *
     * Requirements:
     *
     * - the caller must be the reward distributor
     * - the reward duration must be non-zero
     * - the token must not have already been added
     *
     */
    function addToken(
        address smartVault,
        IERC20 token,
        uint32 rewardsDuration,
        uint256 reward
    ) external
    /*onlyVaultOwnerOrSpoolOwner TODO acl */
    exceptUnderlying(token) {
        RewardConfiguration storage config = rewardConfiguration[smartVault][token];

        require(!tokenBlacklist[smartVault][token], "TOBL");
        require(
            rewardsDuration != 0 &&
            config.lastUpdateTime == 0,
            "BCFG"
        );
        require(
            rewardTokensCount[smartVault] <= 5,
            "TMAX"
        );

        rewardTokens[smartVault][rewardTokensCount[smartVault]] = token;
        rewardTokensCount[smartVault]++;

        config.rewardsDuration = rewardsDuration;

        if (reward > 0) {
            _notifyRewardAmount(smartVault, token, reward);
        }
    }

    function notifyRewardAmount(address smartVault, IERC20 token, uint256 reward, uint32 rewardsDuration)
    external
        /*onlyVaultOwnerOrSpoolOwner TODO acl */

    {
        rewardConfiguration[smartVault][token].rewardsDuration = rewardsDuration;
        _notifyRewardAmount(smartVault, token, reward);
    }

    function _notifyRewardAmount(address smartVault, IERC20 token, uint256 reward)
    private
    updateReward(smartVault, token, address(0))
    {
        RewardConfiguration storage config = rewardConfiguration[smartVault][token];

        require(
            config.rewardPerTokenStored + (reward * REWARD_ACCURACY) <= type(uint192).max,
            "RTB"
        );

        token.safeTransferFrom(msg.sender, address(this), reward);
        uint32 newPeriodFinish = uint32(block.timestamp) + config.rewardsDuration;

        if (block.timestamp >= config.periodFinish) {
            config.rewardRate = SafeCast.toUint192((reward * REWARD_ACCURACY) / config.rewardsDuration);
            emit RewardAdded(token, reward, config.rewardsDuration);
        } else {
            // If extending or adding additional rewards,
            // cannot set new finish time to be less than previously configured
            require(config.periodFinish <= newPeriodFinish, "PFS");
            uint256 remaining = config.periodFinish - block.timestamp;
            uint256 leftover = remaining * config.rewardRate;
            uint192 newRewardRate = SafeCast.toUint192((reward * REWARD_ACCURACY + leftover) / config.rewardsDuration);

            require(
                newRewardRate >= config.rewardRate,
                "LRR"
            );

            config.rewardRate = newRewardRate;
            emit RewardExtended(token, reward, leftover, config.rewardsDuration, newPeriodFinish);
        }

        config.lastUpdateTime = uint32(block.timestamp);
        config.periodFinish = newPeriodFinish;
    }

    // End rewards emission earlier
    function updatePeriodFinish(address smartVault, IERC20 token, uint32 timestamp)
    external
    /* onlyOwner TODO ACL */
    updateReward(smartVault, token, address(0))
    {
        if (rewardConfiguration[smartVault][token].lastUpdateTime > timestamp) {
            rewardConfiguration[smartVault][token].periodFinish = rewardConfiguration[smartVault][token].lastUpdateTime;
        } else {
            rewardConfiguration[smartVault][token].periodFinish = timestamp;
        }

        emit PeriodFinishUpdated(token, rewardConfiguration[smartVault][token].periodFinish);
    }

    /**
     * @notice Claim reward tokens
     * @dev
     * This is meant to be an emergency function to claim reward tokens.
     * Users that have not claimed yet will not be able to claim as
     * the rewards will be removed.
     *
     * Requirements:
     *
     * - the caller must be Spool DAO
     * - cannot claim vault underlying token
     * - cannot only execute if the reward finished
     *
     * @param token Token address to remove
     * @param amount Amount of tokens to claim
     */
    function claimFinishedRewards(address smartVault, IERC20 token, uint256 amount) external
        /* onlyOwner TODO ACL */
    exceptUnderlying(token)
    onlyFinished(smartVault, token) {
        token.safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Force remove reward from vault rewards configuration.
     * @dev This is meant to be an emergency function if a reward token breaks.
     *
     * Requirements:
     *
     * - the caller must be Spool DAO
     *
     * @param token Token address to remove
     */
    function forceRemoveReward(address smartVault, IERC20 token) external
        /* onlyOwner TODO ACL */
    {
        //tokenBlacklist.token] = true; add list + smartVault

        _removeReward(smartVault, token);

        delete rewardConfiguration[smartVault][token];
    }

    /**
     * @notice Remove reward from vault rewards configuration.
     * @dev
     * Used to sanitize vault and save on gas, after the reward has ended.
     * Users will be able to claim rewards
     *
     * Requirements:
     *
     * - the caller must be the spool owner or Spool DAO
     * - cannot claim vault underlying token
     * - cannot only execute if the reward finished
     *
     * @param token Token address to remove
     */
    function removeReward(address smartVault, IERC20 token)
    external
        /*onlyVaultOwnerOrSpoolOwner TODO acl */

    onlyFinished(smartVault, token)
    updateReward(smartVault, token, address(0))
    {
        _removeReward(smartVault, token);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @notice Syncs rewards across all tokens of the system
     *
     * This function is meant to be invoked every time the instant deposit
     * of a user changes.
     */
    function _updateRewards(address smartVault, address account) private {
        uint256 _rewardTokensCount = rewardTokensCount[smartVault];

        for (uint256 i; i < _rewardTokensCount; i++)
            _updateReward(smartVault, rewardTokens[smartVault][i], account);
    }

    function _updateReward(address smartVault, IERC20 token, address account) private {
        RewardConfiguration storage config = rewardConfiguration[smartVault][token];
        config.rewardPerTokenStored = rewardPerToken(smartVault, token);
        config.lastUpdateTime = lastTimeRewardApplicable(smartVault, token);
        if (account != address(0)) {
            config.rewards[account] = earned(smartVault, token, account);
            config.userRewardPerTokenPaid[account] = config
            .rewardPerTokenStored;
        }
    }

    function _removeReward(address smartVault, IERC20 token) private {
        uint256 _rewardTokensCount = rewardTokensCount[smartVault];
        for (uint256 i; i < _rewardTokensCount; i++) {
            if (rewardTokens[smartVault][i] == token) {
                rewardTokens[smartVault][i] = rewardTokens[smartVault][_rewardTokensCount - 1];

                delete rewardTokens[smartVault][_rewardTokensCount- 1];
                rewardTokensCount[smartVault]--;
                emit RewardRemoved(token);

                break;
            }
        }
    }

    function _exceptUnderlying(IERC20 token) private view {
       /* TODO add _underlying
       require(
            token != _underlying(),
            "NUT"
        );
        */
    }

    function _onlyFinished(address smartVault, IERC20 token) private view {
        require(
            block.timestamp > rewardConfiguration[smartVault][token].periodFinish,
            "RNF"
        );
    }

    /**
    * @notice Ensures that the caller is the controller
     */
    function _onlyController() private view {
       /* require(
            msg.sender == address(controller),
            "OCTRL"
        );
        */
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address smartVault, IERC20 token, address account) {
        _updateReward(smartVault, token, account);
        _;
    }

    modifier updateRewards(address smartVault) {
        _updateRewards(smartVault, msg.sender);
        _;
    }

    modifier exceptUnderlying(IERC20 token) {
        _exceptUnderlying(token);
        _;
    }

    modifier onlyFinished(address smartVault, IERC20 token) {
        _onlyFinished(smartVault, token);
        _;
    }

    /**
     * @notice Throws if called by anyone else other than the controller
     */
    modifier onlyController() {
        _onlyController();
        _;
    }
}