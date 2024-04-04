// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/interfaces/IERC4626.sol";

import "./AbstractERC4626Strategy.sol";
import "../interfaces/ISwapper.sol";

contract ERC4626Module is AbstractERC4626Strategy {
    IERC4626 public immutable erc4626;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IERC4626 vault_,
        IERC4626 erc4626_
    ) AbstractERC4626Strategy(assetGroupRegistry_, accessControl_, vault_) {
        _disableInitializers();
        erc4626 = erc4626_;
    }

    function beforeDepositCheck_(uint256, uint256, uint256 shares) internal view override {
        uint256 maxDeposit = erc4626.maxDeposit(address(this));
        if (maxDeposit < shares) revert BeforeDepositCheck();
    }

    function beforeRedeemalCheck_(uint256, uint256, uint256 shares) internal view override {
        uint256 maxRedeem = erc4626.maxRedeem(address(this));
        if (maxRedeem < shares) revert BeforeRedeemalCheck();
    }

    function deposit_() internal override {
        deposit_(vault.balanceOf(address(this)));
    }

    function deposit_(uint256 shares) internal override returns (uint256) {
        _resetAndApprove(vault, address(erc4626), shares);
        return erc4626.deposit(shares, address(this));
    }

    function redeem_() internal override {
        redeem_(erc4626.balanceOf(address(this)));
    }

    function redeem_(uint256 shares) internal override returns (uint256) {
        return erc4626.redeem(shares, address(this), address(this));
    }

    function rewardInfo_() internal override returns (address, uint256) {}

    function compound_(address[] calldata tokens, SwapInfo[] calldata compoundSwapInfo, uint256[] calldata slippages)
        internal
        override
        returns (int256 compoundYield)
    {}

    function vaultShareBalance_() internal view override returns (uint256) {
        return erc4626.previewRedeem(erc4626.balanceOf(address(this)));
    }

    function previewRedeemSsts_(uint256 ssts) internal view override returns (uint256) {
        return (erc4626.balanceOf(address(this)) * ssts) / totalSupply();
    }
}
