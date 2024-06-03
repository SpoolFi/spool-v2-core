// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./ERC4626StrategyDouble.sol";

contract YearnV3StrategyWithJuice is ERC4626StrategyDouble {
    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_)
        ERC4626StrategyDouble(assetGroupRegistry_, accessControl_)
    {}

    function initialize(
        string memory strategyName_,
        uint256 assetGroupId_,
        IERC4626 vault_,
        IERC4626 secondaryVault_,
        uint256 constantShareAmount_
    ) external initializer {
        __ERC4626StrategyDouble_init(strategyName_, assetGroupId_, vault_, secondaryVault_, constantShareAmount_);
    }
}
