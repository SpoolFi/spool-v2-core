// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "./ISwapper.sol";
import "../libraries/uint16a16Lib.sol";

/* ========== ERRORS ========== */

/**
 * @notice Used when trying to register an already registered strategy.
 * @param address_ Address of already registered strategy.
 */
error StrategyAlreadyRegistered(address address_);

/**
 * @notice Used when DHW was not run yet for a strategy index.
 * @param strategy Address of the strategy.
 * @param strategyIndex Index of the strategy.
 */
error DhwNotRunYetForIndex(address strategy, uint256 strategyIndex);

/**
 * @notice Used when provided token list is invalid.
 */
error InvalidTokenList();

/**
 * @notice Used when ghost strategy is used.
 */
error GhostStrategyUsed();

/**
 * @notice Used when syncing vault that is already fully synced.
 */
error NothingToSync();

/// @notice Used when system tries to configure a too large ecosystem fee.
error EcosystemFeeTooLarge(uint256 ecosystemFeePct);

/// @notice Used when system tries to configure a too large treasury fee.
error TreasuryFeeTooLarge(uint256 treasuryFeePct);

/**
 * @notice Represents change of state for a strategy during a DHW.
 * @custom:member exchangeRates Exchange rates between assets and USD.
 * @custom:member assetsDeposited Amount of assets deposited into the strategy.
 * @custom:member sharesMinted Amount of strategy shares minted.
 * @custom:member totalStrategyValue Total strategy value at the end of the DHW.
 * @custom:member dhwYields DHW yield percentage from the previous DHW.
 */
struct StrategyAtIndex {
    uint256[] exchangeRates;
    uint256[] assetsDeposited;
    uint256 sharesMinted;
    uint256 totalSSTs;
    uint256 totalStrategyValue;
    int256 dhwYields;
}

/**
 * @notice Parameters for calling do hard work.
 * @custom:member strategies Strategies to do-hard-worked upon, grouped by their asset group.
 * @custom:member swapInfo Information for swapping assets before depositing into protocol. SwapInfo[] per each strategy.
 * @custom:member compoundSwapInfo Information for swapping rewards before depositing them back into the protocol. SwapInfo[] per each strategy.
 * @custom:member strategySlippages Slippages used to constrain depositing into and withdrawing from the protocol. uint256[] per strategy.
 * @custom:member tokens List of all asset tokens involved in the do hard work.
 * @custom:member exchangeRateSlippages Slippages used to constrain exchange rates for asset tokens. uint256[2] for each token.
 */
struct DoHardWorkParameterBag {
    address[][] strategies;
    SwapInfo[][][] swapInfo;
    SwapInfo[][][] compoundSwapInfo;
    uint256[][][] strategySlippages;
    address[] tokens;
    uint256[2][] exchangeRateSlippages;
}

/**
 * @notice Parameters for calling redeem fast.
 * @custom:member strategies Addresses of strategies.
 * @custom:member strategyShares Amount of shares to redeem.
 * @custom:member assetGroup Asset group of the smart vault.
 * @custom:member slippages Slippages to guard withdrawal.
 * @custom:member exchangeRateSlippages Slippages used to constrain exchange rates for asset tokens.
 */
struct RedeemFastParameterBag {
    address[] strategies;
    uint256[] strategyShares;
    address[] assetGroup;
    uint256[][] withdrawalSlippages;
    uint256[2][] exchangeRateSlippages;
}

struct PlatformFees {
    address ecosystemFeeReceiver;
    uint96 ecosystemFeePct;
    address treasuryFeeReceiver;
    uint96 treasuryFeePct;
}

/* ========== INTERFACES ========== */

interface IStrategyRegistry {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function emergencyWithdrawalWallet() external view returns (address);
    function currentIndex(address[] calldata strategies) external view returns (uint256[] memory);
    function depositedAssets(address strategy, uint256 dhwIndex) external view returns (uint256[] memory);
    function dhwTimestamps(address[] calldata strategies, uint16a16 dhwIndexes)
        external
        view
        returns (uint256[] memory);
    function strategyAtIndex(address strategy, uint256 dhwIndex) external view returns (StrategyAtIndex memory);
    function strategyAtIndexBatch(address[] calldata strategies, uint16a16 dhwIndexes)
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
    function setEcosystemFee(uint96 ecosystemFeePct_) external;
    function setEcosystemFeeReceiver(address ecosystemFeePct_) external;
    function setTreasuryFee(uint96 treasuryFeePct_) external;
    function setTreasuryFeeReceiver(address treasuryFeeReceiver_) external;

    /**
     * @notice Does hard work on multiple strategies.
     * @param dhwParams Parameters for do hard work.
     */
    function doHardWork(DoHardWorkParameterBag calldata dhwParams) external;

    function addDeposits(address[] memory strategies_, uint256[][] memory amounts) external returns (uint16a16);

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
        returns (uint16a16 strategyIndexes);

    /**
     * @notice Instantly redeems strategy shares for assets.
     * @param redeemFastParams Parameters for fast redeem.
     * @return withdrawnAssets Amount of assets withdrawn.
     */
    function redeemFast(RedeemFastParameterBag calldata redeemFastParams)
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
    function claimWithdrawals(address[] memory strategies_, uint16a16 dhwIndexes, uint256[] memory strategyShares)
        external
        view
        returns (uint256[] memory assetsWithdrawn);

    function platformFees() external view returns (PlatformFees memory);
}

interface IEmergencyWithdrawal {
    event StrategyEmergencyWithdrawn(address indexed strategy);

    /**
     * @notice Set a new address that will receive assets withdrawn if emergency withdrawal is executed
     * @param address_ address
     */
    function setEmergencyWithdrawalWallet(address address_) external;

    /**
     * @notice Instantly withdraws assets from a strategy, bypassing shares mechanism.
     * @param strategies Addresses of strategies.
     * @param assetGroup Asset group of the smart vault.
     * @param withdrawalSlippages Slippages to guard withdrawal.
     * @param removeStrategies Whether to remove strategies from the system after withdrawal.
     */
    function emergencyWithdraw(
        address[] calldata strategies,
        address[] calldata assetGroup,
        uint256[][] calldata withdrawalSlippages,
        bool removeStrategies
    ) external;
}
