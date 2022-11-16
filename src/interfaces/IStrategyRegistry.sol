// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

/* ========== ERRORS ========== */

error InvalidStrategy(address address_);
error StrategyAlreadyRegistered(address address_);

/**
 * @notice Used when DHW was not run yet for a strategy index.
 * @param strategy Address of the strategy.
 * @param strategyIndex Index of the strategy.
 */
error DhwNotRunYetForIndex(address strategy, uint256 strategyIndex);

struct StrategyAtIndex {
    uint256 sharesMinted;
    uint256[] depositedAssets;
    uint256[] slippages;
    uint256[] exchangeRates;
}

/* ========== INTERFACES ========== */

interface IStrategyRegistry {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function isStrategy(address strategy) external view returns (bool);
    function currentIndex(address strategy) external view returns (uint256);
    function depositedAssets(address strategy, uint256 dhwIndex) external view returns (uint256[] memory);
    function strategyAtIndex(address strategy, uint256 dhwIndex) external view returns (StrategyAtIndex memory);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function registerStrategy(address strategy) external;
    function removeStrategy(address strategy) external;
    function doHardWork(address[] memory strategies_) external;
    function addDeposits(address[] memory strategies_, uint256[][] memory amounts)
        external
        returns (uint256[] memory);

    /**
     * @notice Adds withdrawals to the strategies to be processed on DHW.
     * @dev Reqirements:
     * - must be called by SmartVaultManager
     * @param strategies_ Addresses of strategies from which to withdraw.
     * @param strategyShares Amount of strategy shares to be withdrawns.
     * @return Current indexes for the strategies.
     */
    function addWithdrawals(address[] memory strategies_, uint256[] memory strategyShares)
        external
        returns (uint256[] memory);

    /**
     * @notice Claims withdrawals from the strategies.
     * @dev Requirements:
     * - must be called by SmartVaultManager
     * - DHWs must be run for withdrawal indexes.
     * @param strategies_ Addresses if strategies from which to claim withdrawal.
     * @param dhwIndexes Indexes of strategies when withdrawal was made.
     * @param strategyShares Amount of strategy shares that was withdrawn.
     * @return Amount of assets withdrawn from strategies.
     */
    function claimWithdrawals(
        address[] memory strategies_,
        uint256[] memory dhwIndexes,
        uint256[] memory strategyShares
    ) external view returns (uint256[] memory);
}
