// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "./ISwapper.sol";

/* ========== ERRORS ========== */

error InvalidStrategy(address address_);
error StrategyAlreadyRegistered(address address_);

/**
 * @notice Used when DHW was not run yet for a strategy index.
 * @param strategy Address of the strategy.
 * @param strategyIndex Index of the strategy.
 */
error DhwNotRunYetForIndex(address strategy, uint256 strategyIndex);

/**
 * @notice Represents change of state for a strategy during a DHW.
 * @custom:member exchangeRates Exchange rates between assets and USD.
 * @custom:member assetsDeposited Amount of assets deposited into the strategy.
 * @custom:member sharesMinted Amount of strategy shares minted.
 */
struct StrategyAtIndex {
    uint256[] exchangeRates;
    uint256[] assetsDeposited;
    uint256 sharesMinted;
    uint256 dhwTimestamp;
}

/* ========== INTERFACES ========== */

interface IStrategyRegistry {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function isStrategy(address strategy) external view returns (bool);
    function currentIndex(address[] calldata strategies) external view returns (uint256[] memory);
    function depositedAssets(address strategy, uint256 dhwIndex) external view returns (uint256[] memory);
    function strategyAtIndex(address strategy, uint256 dhwIndex) external view returns (StrategyAtIndex memory);
    function strategyAtIndexBatch(address[] calldata strategies, uint256[] calldata dhwIndexes)
        external
        view
        returns (StrategyAtIndex[] memory);

    /**
     * @notice Gets required asset ratio for strategy at last DHW.
     * @param strategy Address of the strategy.
     * @return assetRatio Asset ratio.
     */
    function assetRatioAtLastDhw(address strategy) external view returns (uint256[] memory assetRatio);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function registerStrategy(address strategy) external;
    function removeStrategy(address strategy) external;
    function doHardWork(address[] calldata strategies_, SwapInfo[][] calldata swapInfo) external;
    function addDeposits(address[] memory strategies_, uint256[][] memory amounts)
        external
        returns (uint256[] memory);

    /**
     * @notice Adds withdrawals to the strategies to be processed on DHW.
     * @dev Reqirements:
     * - must be called by SmartVaultManager
     * @param strategies_ Addresses of strategies from which to withdraw.
     * @param strategyShares Amount of strategy shares to be withdrawns.
     * @return strategyIndexes Current indexes for the strategies.
     */
    function addWithdrawals(address[] memory strategies_, uint256[] memory strategyShares)
        external
        returns (uint256[] memory strategyIndexes);

    /**
     * @notice Instantly redeems strategy shares for assets.
     * @param strategies_ Addresses of strategies.
     * @param strategyShares Amount of shares to redeem.
     * @param assetGroup Asset group of the smart vault.
     * @return withdrawnAssets Amount of assets withdrawn.
     */
    function redeemFast(address[] memory strategies_, uint256[] memory strategyShares, address[] memory assetGroup)
        external
        returns (uint256[] memory withdrawnAssets);

    /**
     * @notice Claims withdrawals from the strategies.
     * @dev Requirements:
     * - must be called by SmartVaultManager
     * - DHWs must be run for withdrawal indexes.
     * @param strategies_ Addresses if strategies from which to claim withdrawal.
     * @param dhwIndexes Indexes of strategies when withdrawal was made.
     * @param strategyShares Amount of strategy shares that was withdrawn.
     * @return assetsWithdrawn Amount of assets withdrawn from strategies.
     */
    function claimWithdrawals(
        address[] memory strategies_,
        uint256[] memory dhwIndexes,
        uint256[] memory strategyShares
    ) external view returns (uint256[] memory assetsWithdrawn);
}
