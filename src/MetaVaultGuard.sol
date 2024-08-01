/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./interfaces/ISmartVaultManager.sol";
import "./interfaces/IAssetGroupRegistry.sol";
import "./interfaces/IGuardManager.sol";
import "./interfaces/IMetaVault.sol";
import "./interfaces/IMetaVaultGuard.sol";
import "./interfaces/CommonErrors.sol";

contract MetaVaultGuard is IMetaVaultGuard {
    /**
     * @dev SmartVaultManager contract
     */
    ISmartVaultManager internal immutable smartVaultManager;
    /**
     * @dev AssetGroupRegistry contract
     */
    IAssetGroupRegistry internal immutable assetGroupRegistry;
    /**
     * @dev GuardManager contract
     */
    IGuardManager internal immutable guardManager;

    /**
     * @dev Only SmartVaults with zero management fee are supported
     */
    error InvalidVaultManagementFee();
    /**
     * @dev Only SmartVaults with zero deposit fee are supported
     */
    error InvalidVaultDepositFee();
    /**
     * @dev Only SmartVaults with the same underlying assets are supported
     */
    error InvalidVaultAsset();
    /**
     * @dev Any guard on SmartVault is prohibited
     */
    error NoGuardsAllowed();

    // ========================== CONSTRUCTOR ==========================

    constructor(
        ISmartVaultManager smartVaultManager_,
        IAssetGroupRegistry assetGroupRegistry_,
        IGuardManager guardManager_
    ) {
        if (
            address(smartVaultManager_) == address(0) || address(assetGroupRegistry_) == address(0)
                || address(guardManager_) == address(0)
        ) revert ConfigurationAddressZero();
        smartVaultManager = smartVaultManager_;
        assetGroupRegistry = assetGroupRegistry_;
        guardManager = guardManager_;
    }

    /**
     * @dev Check if given smart vault can be managed by MetaVault
     * @param asset for MetaVault
     * @param smartVault to validate
     */
    function validateSmartVault(address asset, address smartVault) external view virtual returns (bool) {
        return _validateSmartVault(asset, smartVault);
    }

    /**
     * @dev Check if given smart vault can be managed by MetaVault
     * @param asset for MetaVault
     * @param smartVaults to validate
     */
    function validateSmartVaults(address asset, address[] calldata smartVaults) external view virtual returns (bool) {
        for (uint256 i; i < smartVaults.length; i++) {
            _validateSmartVault(asset, smartVaults[i]);
        }
        return true;
    }

    /**
     * @dev Check if given smart vault can be managed by MetaVault
     * @param asset for MetaVault
     * @param smartVault to validate
     */
    function _validateSmartVault(address asset, address smartVault) internal view returns (bool) {
        SmartVaultFees memory fees = smartVaultManager.getSmartVaultFees(smartVault);
        /// management and deposit fees should be zero
        if (fees.managementFeePct > 0) revert InvalidVaultManagementFee();
        if (fees.depositFeePct > 0) revert InvalidVaultDepositFee();
        address[] memory vaultAssets = assetGroupRegistry.listAssetGroup(smartVaultManager.assetGroupId(smartVault));
        /// assetGroup should match the underlying asset of MetaVault
        if (vaultAssets.length != 1 || vaultAssets[0] != asset) revert InvalidVaultAsset();
        /// no guards are allowed
        _validateSmartVaultGuards(smartVault, RequestType.Deposit);
        _validateSmartVaultGuards(smartVault, RequestType.Withdrawal);
        _validateSmartVaultGuards(smartVault, RequestType.TransferNFT);
        _validateSmartVaultGuards(smartVault, RequestType.BurnNFT);
        _validateSmartVaultGuards(smartVault, RequestType.TransferSVTs);
        return true;
    }

    function _validateSmartVaultGuards(address smartVault, RequestType requestType) internal view {
        GuardDefinition[] memory guards = guardManager.readGuards(smartVault, requestType);
        if (guards.length > 0) revert NoGuardsAllowed();
    }
}
