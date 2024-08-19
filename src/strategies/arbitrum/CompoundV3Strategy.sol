// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./base/CompoundV3StrategyBase.sol";

// one asset
// One reward (COMP)
// no slippages needed
// Same asset group token and underlying token on the Compound pool.
contract CompoundV3Strategy is CompoundV3StrategyBase {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        IERC20 comp_,
        IRewards rewards_
    ) CompoundV3StrategyBase(assetGroupRegistry_, accessControl_, swapper_, comp_, rewards_) {}
}
