// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/interfaces/IERC4626.sol";

/**
 * @dev Basic library for ERC4626 vaults to check limits for deposit and redeem
 */
library ERC4626Lib {
    /**
     * @dev in certain vaults maxRedeem can return slightly lower amount of shares to redeem than users actual balance
     * @dev it is a helper to introduce small difference check and apply balanceOf in case it is negligible
     * @param vault to perform check on
     * @return max amount of shares to redeem
     */
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

    /**
     * @dev checks whether the limit of assets which can be deposited into vault is reached
     * @param vault to perform check on
     * @param assets to deposit
     * @return true - deposit is full, false - deposit will go through
     */
    function isDepositFull(IERC4626 vault, uint256 assets) internal view returns (bool) {
        return vault.maxDeposit(address(this)) < assets;
    }

    /**
     * @dev checks whether the are less assets in the vault than would be redeemed
     * @param vault to perform check on
     * @param shares to redeem
     * @return true - not enough assets, false - provided shares can be redeemed
     */
    function isRedeemalEmpty(IERC4626 vault, uint256 shares) internal view returns (bool) {
        return getMaxRedeem(vault) < shares;
    }
}
