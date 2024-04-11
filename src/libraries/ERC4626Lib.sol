// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/interfaces/IERC4626.sol";

library ERC4626Lib {
    function getMaxRedeem(IERC4626 vault) internal view returns (uint256) {
        // not all funds can be available for withdrawal
        uint256 maxRedeem = vault.maxRedeem(address(this));
        uint256 totalShares = vault.balanceOf(address(this));
        // maxRedeem can be slightly lower so check for minimal difference - 3 decimals
        if (totalShares - maxRedeem < 10 ** (vault.decimals() - 3)) {
            maxRedeem = totalShares;
        }
        return maxRedeem;
    }

    function depositFull(IERC4626 vault, uint256 assets) internal view returns (bool) {
        return vault.maxDeposit(address(this)) < assets;
    }

    function redeemNotEnough(IERC4626 vault, uint256 shares) internal view returns (bool) {
        return vault.maxRedeem(address(this)) < shares;
    }
}
