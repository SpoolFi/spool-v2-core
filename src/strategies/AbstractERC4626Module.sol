// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "../interfaces/ISwapper.sol";

abstract contract AbstractERC4626Module {
    function beforeDepositCheck_(uint256 amount, uint256 slippage, uint256 shares) internal virtual;

    function beforeRedeemalCheck_(uint256 ssts, uint256 slippage, uint256 shares) internal virtual;

    function deposit_() internal virtual;

    function deposit_(uint256 assets) internal virtual returns (uint256 shares) {
        return assets;
    }

    function redeem_() internal virtual;

    function redeem_(uint256 shares) internal virtual returns (uint256 assets) {
        return shares;
    }

    function rewardInfo_() internal virtual returns (address, uint256);

    function compound_(address[] calldata tokens, SwapInfo[] calldata compoundSwapInfo, uint256[] calldata slippages)
        internal
        virtual
        returns (int256 compoundYield);

    /// @notice
    // should account for possible yield on share
    function vaultShareBalance_() internal view virtual returns (uint256);

    /// @notice
    // should return shares of primary erc4626 vault or derivative if present
    function previewRedeemSsts_(uint256 ssts) internal view virtual returns (uint256);
}
