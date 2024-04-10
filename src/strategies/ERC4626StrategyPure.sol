// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./ERC4626StrategyBase.sol";
import "../external/interfaces/strategies/gearbox/v3/IFarmingPool.sol";

contract ERC4626StrategyPure is ERC4626StrategyBase {
    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, IERC4626 vault_)
        ERC4626StrategyBase(assetGroupRegistry_, accessControl_, vault_, 10 ** (vault_.decimals() * 2))
    {
        _disableInitializers();
    }

    function initialize(string memory strategyName_, uint256 assetGroupId_) external initializer {
        __ERC4626Strategy_init(strategyName_, assetGroupId_);
    }
}
