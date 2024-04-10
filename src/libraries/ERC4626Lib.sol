// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/interfaces/IERC4626.sol";

library ERC4626Lib {
    function depositFull(IERC4626 vault, uint256 assets) internal view returns (bool) {
        return vault.maxDeposit(address(this)) < assets;
    }

    function redeemNotEnough(IERC4626 vault, uint256 shares) internal view returns (bool) {
        return vault.maxRedeem(address(this)) < shares;
    }
}
