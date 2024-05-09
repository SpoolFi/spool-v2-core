// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/interfaces/IERC4626.sol";

import "./ERC4626StrategyBase.sol";
import "../libraries/ERC4626Lib.sol";

//
/// @dev module for reinvesting vault shares in another ERC4626 vault
// all rewards are automatically included into secondaryVault
// therefore there is no explicit compounding
// for instance Yearn V3 vaults have this implementation and call it "juiced yield"
//
contract ERC4626StrategyDouble is ERC4626StrategyBase {
    IERC4626 public immutable secondaryVault;

    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, IERC4626 secondaryVault_)
        ERC4626StrategyBase(assetGroupRegistry_, accessControl_)
    {
        _disableInitializers();
        secondaryVault = secondaryVault_;
    }

    function initialize(
        string memory strategyName_,
        uint256 assetGroupId_,
        IERC4626 vault_,
        uint256 constantShareAmount_
    ) external initializer {
        __ERC4626Strategy_init(strategyName_, assetGroupId_, vault_, constantShareAmount_);
    }

    function beforeDepositCheck_(uint256 assets) internal view override {
        if (ERC4626Lib.isDepositFull(secondaryVault, assets)) revert BeforeDepositCheck();
    }

    function beforeRedeemalCheck_(uint256 shares) internal view override returns (uint256) {
        if (ERC4626Lib.isRedeemalEmpty(secondaryVault, shares)) revert BeforeRedeemalCheck();
        return secondaryVault.previewRedeem(shares);
    }

    function deposit_(uint256 shares) internal override returns (uint256) {
        _resetAndApprove(vault(), address(secondaryVault), shares);
        return secondaryVault.deposit(shares, address(this));
    }

    function previewConstantRedeem_() internal view override returns (uint256) {
        return vault().previewRedeem(secondaryVault.previewRedeem(constantShareAmount()));
    }

    function previewRedeemSSTs_(uint256 ssts) internal view override returns (uint256) {
        return (secondaryVault.balanceOf(address(this)) * ssts) / totalSupply();
    }

    function redeem_() internal override {
        redeem_(ERC4626Lib.getMaxRedeem(secondaryVault));
    }

    function redeem_(uint256 shares) internal override returns (uint256) {
        return secondaryVault.redeem(shares, address(this), address(this));
    }

    function underlyingAssetAmount_() internal view override returns (uint256) {
        return vault().previewRedeem(secondaryVault.previewRedeem(secondaryVault.balanceOf(address(this))));
    }
}