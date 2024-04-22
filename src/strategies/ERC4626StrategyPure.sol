// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./ERC4626StrategyBase.sol";

//
/// @dev In case there is no rewards and depositing/staking of vault shares
// this barebone contract can be used for arbitrary ERC4626 vaults
//
contract ERC4626StrategyPure is ERC4626StrategyBase {
    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_)
        ERC4626StrategyBase(assetGroupRegistry_, accessControl_)
    {
        _disableInitializers();
    }

    function initialize(
        string memory strategyName_,
        uint256 assetGroupId_,
        IERC4626 vault_,
        uint256 constantShareAmount_
    ) external initializer {
        __ERC4626Strategy_init(strategyName_, assetGroupId_, vault_, constantShareAmount_);
    }
}
