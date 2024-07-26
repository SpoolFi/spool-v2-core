/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/proxy/beacon/UpgradeableBeacon.sol";

import "./MetaVault.sol";
import "./managers/AssetGroupRegistry.sol";
import "./access/SpoolAccessControllable.sol";

contract MetaVaultFactory is UpgradeableBeacon, SpoolAccessControllable {
    /**
     * @dev Emitted when a new MetaVault is deployed
     * @param metaVault Address of the newly deployed MetaVault
     * @param deployer Address of the deployer
     */
    event MetaVaultDeployed(address indexed metaVault, address indexed deployer);

    /**
     * @dev only assets listed in AssetGroupRegistry are supported
     */
    error UnsupportedAsset();

    /**
     * @dev AssetGroupRegistry contract
     */
    IAssetGroupRegistry internal immutable assetGroupRegistry;

    constructor(
        address implementation,
        ISpoolAccessControl spoolAccessControl_,
        IAssetGroupRegistry assetGroupRegistry_
    ) UpgradeableBeacon(implementation) SpoolAccessControllable(spoolAccessControl_) {
        if (address(assetGroupRegistry_) == address(0)) revert ConfigurationAddressZero();
        assetGroupRegistry = assetGroupRegistry_;
    }

    /**
     * @dev Deploys a new MetaVault
     * @param asset address
     * @param name for MetaVault
     * @param symbol for MetaVault
     * @return metaVault deployed
     */
    function deployMetaVault(
        address asset,
        string memory name,
        string memory symbol,
        address[] calldata vaults,
        uint256[] calldata allocations
    ) external onlyRole(ROLE_META_VAULT_DEPLOYER, msg.sender) returns (MetaVault) {
        _validateAsset(asset);

        address metaVault = address(
            new BeaconProxy(address(this), _encodeInitializationCalldata(asset, name, symbol, vaults, allocations))
        );

        emit MetaVaultDeployed(metaVault, msg.sender);

        return MetaVault(metaVault);
    }

    /**
     * @dev Deploys a new MetaVault to a deterministic address
     * @param asset address
     * @param name for MetaVault
     * @param symbol for MetaVault
     * @param salt for address determination
     * @return metaVault deployed
     */
    function deployMetaVaultDeterministically(
        address asset,
        string memory name,
        string memory symbol,
        bytes32 salt,
        address[] calldata vaults,
        uint256[] calldata allocations
    ) external onlyRole(ROLE_META_VAULT_DEPLOYER, msg.sender) returns (MetaVault) {
        _validateAsset(asset);

        address metaVaultAddress = address(
            new BeaconProxy{salt: salt}(
                address(this), _encodeInitializationCalldata(asset, name, symbol, vaults, allocations)
            )
        );

        emit MetaVaultDeployed(metaVaultAddress, msg.sender);

        return MetaVault(metaVaultAddress);
    }

    /**
     * @dev Predicts deployment address deterministically
     * @param asset address
     * @param name for MetaVault
     * @param symbol for MetaVault
     * @param salt for address determination
     * @return predictedAddress
     */
    function predictDeterministicAddress(
        address asset,
        string memory name,
        string memory symbol,
        bytes32 salt,
        address[] calldata vaults,
        uint256[] calldata allocations
    ) external view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(
                                abi.encodePacked(
                                    type(BeaconProxy).creationCode,
                                    abi.encode(
                                        address(this),
                                        _encodeInitializationCalldata(asset, name, symbol, vaults, allocations)
                                    )
                                )
                            )
                        )
                    )
                )
            )
        );
    }

    /**
     * @dev Encodes calldata for MetaVault initialization
     * @param asset address
     * @param name for MetaVault
     * @param symbol for MetaVault
     * @return initializationCalldata
     */
    function _encodeInitializationCalldata(
        address asset,
        string memory name,
        string memory symbol,
        address[] calldata vaults,
        uint256[] calldata allocations
    ) private pure returns (bytes memory) {
        return abi.encodeWithSignature(
            "initialize(address,string,string,address[],uint256[])", asset, name, symbol, vaults, allocations
        );
    }

    /**
     * @dev Validates asset for MetaVault
     * @param asset address
     */
    function _validateAsset(address asset) private view {
        if (!assetGroupRegistry.isTokenAllowed(asset)) revert UnsupportedAsset();
    }
}
