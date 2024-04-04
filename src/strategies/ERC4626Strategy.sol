// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./AbstractERC4626Strategy.sol";
import "../external/interfaces/strategies/gearbox/v3/IFarmingPool.sol";

contract ERC4626Strategy is AbstractERC4626Strategy {
    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, IERC4626 vault_)
        AbstractERC4626Strategy(assetGroupRegistry_, accessControl_, vault_)
    {
        _disableInitializers();
    }

    function initialize(string memory strategyName_, uint256 assetGroupId_) external initializer {
        __ERC4626Strategy_init(strategyName_, assetGroupId_);
    }

    function beforeDepositCheck_(uint256, uint256, uint256) internal view override {}

    function beforeRedeemalCheck_(uint256, uint256, uint256) internal view override {}

    function deposit_() internal override {}

    function redeem_() internal override {}

    function compound_(address[] calldata tokens, SwapInfo[] calldata swapInfo, uint256[] calldata)
        internal
        override
        returns (int256 compoundedYieldPercentage)
    {}

    function rewardInfo_() internal override returns (address, uint256) {}

    function vaultShareBalance_() internal view virtual override returns (uint256) {
        return vault.balanceOf(address(this));
    }

    function previewRedeemSsts_(uint256 ssts) internal view override returns (uint256) {
        return (vault.balanceOf(address(this)) * ssts) / totalSupply();
    }
}
