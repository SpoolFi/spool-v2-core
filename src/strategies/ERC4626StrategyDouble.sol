// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./ERC4626StrategyBase.sol";

//
/// @dev module for reinvesting vault shares in another ERC4626 vault
// all rewards are automatically included into secondaryVault
// therefore there is no explicit compounding
// for instance Yearn V3 vaults have this implementation and call it "juiced yield"
//
contract ERC4626StrategyDouble is ERC4626StrategyBase {
    /// @custom:storage-location erc7201:spool.storage.ERC4626StrategyBase
    struct ERC4626StrategyDoubleStorage {
        IERC4626 secondaryVault;
    }

    // keccak256(abi.encode(uint256(keccak256("spool.storage.ERC4626StrategyDouble")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC4626StrategyDoubleStorageLocation =
        0x99fc71582f8bc7d4a372020c56e2655b3e081c8ec292596fe631934be1165b00;

    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_)
        ERC4626StrategyBase(assetGroupRegistry_, accessControl_)
    {}

    function _getERC4626StrategyDoubleStorage() private pure returns (ERC4626StrategyDoubleStorage storage $) {
        assembly {
            $.slot := ERC4626StrategyDoubleStorageLocation
        }
    }

    function __ERC4626StrategyDouble_init(
        string memory strategyName_,
        uint256 assetGroupId_,
        IERC4626 vault_,
        IERC4626 secondaryVault_,
        uint256 constantShareAmount_
    ) internal onlyInitializing {
        __ERC4626StrategyDouble_init_unchained(
            strategyName_, assetGroupId_, vault_, secondaryVault_, constantShareAmount_
        );
    }

    function __ERC4626StrategyDouble_init_unchained(
        string memory strategyName_,
        uint256 assetGroupId_,
        IERC4626 vault_,
        IERC4626 secondaryVault_,
        uint256 constantShareAmount_
    ) internal onlyInitializing {
        ERC4626StrategyDoubleStorage storage $ = _getERC4626StrategyDoubleStorage();
        $.secondaryVault = secondaryVault_;
        __ERC4626Strategy_init(strategyName_, assetGroupId_, vault_, constantShareAmount_);
    }

    function secondaryVault() public view returns (IERC4626) {
        return _getERC4626StrategyDoubleStorage().secondaryVault;
    }

    function beforeDepositCheck_(uint256 assets) internal view virtual override {
        if (ERC4626Lib.isDepositFull(secondaryVault(), assets)) revert BeforeDepositCheck();
    }

    function beforeRedeemalCheck_(uint256 shares) internal view virtual override returns (uint256) {
        IERC4626 secondaryVault_ = secondaryVault();
        if (ERC4626Lib.isRedeemalEmpty(secondaryVault_, shares)) revert BeforeRedeemalCheck();
        return secondaryVault_.previewRedeem(shares);
    }

    function deposit_(uint256 shares) internal virtual override returns (uint256) {
        IERC4626 secondaryVault_ = secondaryVault();
        _resetAndApprove(vault(), address(secondaryVault_), shares);
        return secondaryVault_.deposit(shares, address(this));
    }

    function previewConstantRedeem_() internal view virtual override returns (uint256) {
        return vault().previewRedeem(secondaryVault().previewRedeem(constantShareAmount()));
    }

    function previewRedeemSSTs_(uint256 ssts) internal view virtual override returns (uint256) {
        return (secondaryVault().balanceOf(address(this)) * ssts) / totalSupply();
    }

    function redeem_() internal virtual override {
        redeem_(ERC4626Lib.getMaxRedeem(secondaryVault()));
    }

    function redeem_(uint256 shares) internal virtual override returns (uint256) {
        return secondaryVault().redeem(shares, address(this), address(this));
    }

    function underlyingAssetAmount_() internal view virtual override returns (uint256) {
        IERC4626 secondaryVault_ = secondaryVault();
        return vault().previewRedeem(secondaryVault_.previewRedeem(secondaryVault_.balanceOf(address(this))));
    }
}
