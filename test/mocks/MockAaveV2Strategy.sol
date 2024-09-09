// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../src/strategies/AaveV2Strategy.sol";

contract MockAaveV2Strategy is AaveV2Strategy {
    using SafeERC20 for IERC20;

    uint256 public loss;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ILendingPoolAddressesProvider provider_
    ) AaveV2Strategy(assetGroupRegistry_, accessControl_, provider_) {}

    function setLoss(uint256 loss_) external {
        loss = loss_;
    }

    function _redeemShares(
        uint256 shares,
        address shareOwner,
        address recipient,
        address[] calldata assetGroup,
        uint256[] calldata slippages
    ) internal override returns (uint256[] memory) {
        // redeem shares from protocol
        uint256[] memory assetsWithdrawn = _redeemFromProtocolAndReturnAssets(assetGroup, shares, slippages);
        _burn(shareOwner, shares);

        unchecked {
            for (uint256 i; i < assetGroup.length; ++i) {
                assetsWithdrawn[i] -= assetsWithdrawn[i] * loss / 100_00;
                // emulate loss on redeemFast
                IERC20(assetGroup[i]).safeTransfer(recipient, assetsWithdrawn[i]);
            }
        }

        return assetsWithdrawn;
    }
}
