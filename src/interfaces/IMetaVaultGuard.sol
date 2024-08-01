// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

interface IMetaVaultGuard {
    /**
     * @notice validates smart vault addition to particular MetaVault
     * @return address of asset
     */
    function validateSmartVault(address metaVault, address smartVault) external view returns (bool);

    /**
     * @dev Check if given smart vault can be managed by MetaVault
     * @param metaVault manager
     * @param smartVaults to validate
     */
    function validateSmartVaults(address metaVault, address[] calldata smartVaults) external view returns (bool);
}
