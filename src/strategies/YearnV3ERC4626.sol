// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/interfaces/IERC4626.sol";

import "./AbstractERC4626Strategy.sol";
import "../interfaces/ISwapper.sol";

contract YearnV3ERC4626 is AbstractERC4626Strategy {
    IERC4626 public immutable harvester;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IERC4626 vault_,
        IERC4626 harvester_
    ) AbstractERC4626Strategy(assetGroupRegistry_, accessControl_, vault_, 10 ** (harvester_.decimals() * 2)) {
        _disableInitializers();
        harvester = harvester_;
    }

    function initialize(string memory strategyName_, uint256 assetGroupId_) external initializer {
        __ERC4626Strategy_init(strategyName_, assetGroupId_);
    }

    function beforeDepositCheck_(uint256, uint256, uint256 shares) internal view override {
        uint256 maxDeposit = harvester.maxDeposit(address(this));
        if (maxDeposit < shares) revert BeforeDepositCheck();
    }

    function beforeRedeemalCheck_(uint256, uint256, uint256 shares) internal view override {
        uint256 maxRedeem = harvester.maxRedeem(address(this));
        if (maxRedeem < shares) revert BeforeRedeemalCheck();
    }

    function deposit_() internal override {
        deposit_(vault.balanceOf(address(this)));
    }

    function deposit_(uint256 shares) internal override returns (uint256) {
        _resetAndApprove(vault, address(harvester), shares);
        return harvester.deposit(shares, address(this));
    }

    function redeem_() internal override {
        redeem_(harvester.balanceOf(address(this)));
    }

    function redeem_(uint256 shares) internal override returns (uint256) {
        return harvester.redeem(shares, address(this), address(this));
    }

    function rewardInfo_() internal override returns (address, uint256) {}

    function compound_(address[] calldata tokens, SwapInfo[] calldata compoundSwapInfo, uint256[] calldata slippages)
        internal
        override
        returns (int256 compoundYield)
    {}

    function _previewConstantRedeem() internal view override returns (uint256) {
        return vault.previewRedeem(harvester.previewRedeem(CONSTANT_SHARE_AMOUNT));
    }

    function vaultShareBalance_() internal view override returns (uint256) {
        return harvester.previewRedeem(harvester.balanceOf(address(this)));
    }

    function previewRedeemSsts_(uint256 ssts) internal view override returns (uint256) {
        return (harvester.balanceOf(address(this)) * ssts) / totalSupply();
    }
}
