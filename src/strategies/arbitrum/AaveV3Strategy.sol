// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./base/AaveV3StrategyBase.sol";

// only uses one asset
// no rewards
// no slippages needed
// Same asset group and underlying token on the Aave pool.
contract AaveV3Strategy is AaveV3StrategyBase {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IPoolAddressesProvider provider_
    ) AaveV3StrategyBase(assetGroupRegistry_, accessControl_, provider_) {}
}
