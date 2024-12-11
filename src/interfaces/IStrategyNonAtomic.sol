// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./IUsdPriceFeedManager.sol";
import {PlatformFees, DhwInfo} from "./IStrategyRegistry.sol";

/**
 * @notice Parameters for calling do hard work continue on a strategy.
 * @custom:member assetGroup Asset group of the strategy.
 * @custom:member exchangeRates Exchange rates for assets.
 * @custom:member masterWallet Master wallet.
 * @custom:member priceFeedManager Price feed manager.
 * @custom:member baseYield Base yield value, manual input for specific strategies.
 * @custom:member platformFees Platform fees info.
 * @custom:member continuationData Any data needed for continuation. It is up to the strategy to interpret it.
 */
struct StrategyDhwContinueParameterBag {
    address[] assetGroup;
    uint256[] exchangeRates;
    address masterWallet;
    IUsdPriceFeedManager priceFeedManager;
    int256 baseYield;
    PlatformFees platformFees;
    bytes continuationData;
}

interface IStrategyNonAtomic {
    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when deposit into the underlying protocol is initiated.
     * @param assetsBeforeSwap Amount of assets available before swapping.
     * @param assetsDeposited Amount of assets deposited into the protocol.
     */
    event DepositInitiated(uint256[] assetsBeforeSwap, uint256[] assetsDeposited);

    /**
     * @notice Emitted when withdrawal from the underlying protocol is initiated.
     * @param withdrawnShares Amount of strategy shares withdrawn.
     */
    event WithdrawalInitiated(uint256 withdrawnShares);

    /* ========== MUTATIVE FUNCTIONS ========== */

    function doHardWorkContinue(StrategyDhwContinueParameterBag calldata params)
        external
        returns (DhwInfo memory dhwInfo);
}
