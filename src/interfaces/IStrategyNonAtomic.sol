// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./IUsdPriceFeedManager.sol";
import {PlatformFees, DhwInfo} from "./IStrategyRegistry.sol";

struct StrategyDhwContinuationParameterBag {
    address[] assetGroup;
    uint256[] exchangeRates;
    address masterWallet;
    IUsdPriceFeedManager priceFeedManager;
    int256 baseYield;
    PlatformFees platformFees;
    bytes continuationData;
}

interface IStrategyNonAtomic {
    function doHardWorkContinue(StrategyDhwContinuationParameterBag calldata params)
        external
        returns (DhwInfo memory dhwInfo);
}
