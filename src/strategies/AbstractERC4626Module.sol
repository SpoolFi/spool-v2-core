// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "../interfaces/ISwapper.sol";

abstract contract AbstractERC4626Module {
    function beforeDepositCheck_(uint256[] memory amounts, uint256[] calldata slippages) internal virtual;

    function beforeRedeemalCheck_(uint256 ssts, uint256[] calldata slippages) internal virtual;

    function deposit_() internal virtual;

    function deposit_(uint256 shares) internal virtual;

    function withdraw_() internal virtual;

    function withdraw_(uint256 sharesToGet) internal virtual;

    function rewardInfo_() internal virtual returns (address, uint256);

    function compound_(address[] calldata tokens, SwapInfo[] calldata compoundSwapInfo, uint256[] calldata slippages)
        internal
        virtual
        returns (int256 compoundYield);

    function vaultShareBalance_() internal view virtual returns (uint256);
}
