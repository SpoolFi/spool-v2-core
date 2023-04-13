// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../external/interfaces/strategies/morpho/compound/ILens.sol";
import "../strategies/MorphoStrategyBase.sol";

contract MorphoCompoundV2Strategy is MorphoStrategyBase {
    using SafeERC20 for IERC20;

    /// @notice Morpho Lens contract
    ILens public immutable lens;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IMorpho morpho_,
        IERC20 poolRewardToken_,
        ISwapper swapper_,
        uint256 assetGroupId_,
        ILens lens_
    ) MorphoStrategyBase(assetGroupRegistry_, accessControl_, morpho_, poolRewardToken_, swapper_, assetGroupId_) {
        lens = lens_;
    }

    function initialize(string memory strategyName_, address poolTokenAddress_) external initializer {
        __MorphoStrategyBase_init(strategyName_, poolTokenAddress_);
    }

    function _getTotalBalance() internal view override returns (uint256) {
        (,, uint256 totalBalance) = lens.getCurrentSupplyBalanceInOf(poolTokenAddress, address(this));
        return totalBalance;
    }
}