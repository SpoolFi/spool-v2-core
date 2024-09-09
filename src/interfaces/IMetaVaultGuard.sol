// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

interface IMetaVaultGuard {
    // ========================== ERRORS ==========================

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

    // ========================== FUNCTIONS ==========================

    /**
     * @notice Check if given smart vault can be managed by MetaVault
     * @param asset for MetaVault
     * @param smartVault to validate
     */
    function validateSmartVault(address asset, address smartVault) external view returns (bool);

    /**
     * @notice Check if given smart vault can be managed by MetaVault
     * @param asset for MetaVault
     * @param smartVaults to validate
     */
    function validateSmartVaults(address asset, address[] calldata smartVaults) external view returns (bool);
}
