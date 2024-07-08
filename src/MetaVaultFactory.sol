/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import "./MetaVault.sol";
import "./managers/SmartVaultManager.sol";
import "./managers/AssetGroupRegistry.sol";
import "./access/SpoolAccessControl.sol";

contract MetaVaultFactory is UpgradeableBeacon {
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
     * @dev SmartVaultManager contract
     */
    ISmartVaultManager internal immutable smartVaultManager;
    /**
     * @dev AssetGroupRegistry contract
     */
    IAssetGroupRegistry internal immutable assetGroupRegistry;
    /**
     * @dev AssetGroupRegistry contract
     */
    ISpoolAccessControl internal immutable spoolAccessControl;

    constructor(
        address implementation,
        ISmartVaultManager smartVaultManager_,
        ISpoolAccessControl spoolAccessControl_,
        IAssetGroupRegistry assetGroupRegistry_
    ) UpgradeableBeacon(implementation) {
        if (address(smartVaultManager_) == address(0)) revert ConfigurationAddressZero();
        if (address(spoolAccessControl_) == address(0)) revert ConfigurationAddressZero();
        if (address(assetGroupRegistry_) == address(0)) revert ConfigurationAddressZero();

        smartVaultManager = smartVaultManager_;
        assetGroupRegistry = assetGroupRegistry_;
        spoolAccessControl = spoolAccessControl_;
    }

    /**
     * @dev Deploys a new MetaVault
     * @param asset address
     * @param name for MetaVault
     * @param symbol for MetaVault
     * @return metaVault Deployed MetaVault
     */
    function deployMetaVault(address asset, string memory name, string memory symbol) external returns (MetaVault) {
        _validateAsset(asset);

        address metaVault = address(new BeaconProxy(address(this), _encodeInitializationCalldata(asset, name, symbol)));

        emit MetaVaultDeployed(metaVault, msg.sender);

        return MetaVault(metaVault);
    }

    /**
     * @dev Deploys a new MetaVault to a deterministic address
     * @param asset address
     * @param name for MetaVault
     * @param symbol for MetaVault
     * @param salt for address determination
     * @return metaVault Deployed MetaVault
     */
    function deploySmartVaultDeterministically(address asset, string memory name, string memory symbol, bytes32 salt)
        external
        returns (MetaVault)
    {
        _validateAsset(asset);

        address metaVaultAddress =
            address(new BeaconProxy{salt: salt}(address(this), _encodeInitializationCalldata(asset, name, symbol)));

        emit MetaVaultDeployed(metaVaultAddress, msg.sender);

        return MetaVault(metaVaultAddress);
    }

    /**
     * @dev Predicts deployment address deterministically
     * @param asset address
     * @param name for MetaVault
     * @param symbol for MetaVault
     * @param salt Salt for address determination.
     * @return predictedAddress Predicted address.
     */
    function predictDeterministicAddress(address asset, string memory name, string memory symbol, bytes32 salt)
        external
        view
        returns (address)
    {
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
                                    abi.encode(address(this), _encodeInitializationCalldata(asset, name, symbol))
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
     * @return initializationCalldata Encoded initialization calldata
     */
    function _encodeInitializationCalldata(address asset, string memory name, string memory symbol)
        private
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature("initialize(address,string,string)", asset, name, symbol);
    }

    /**
     * @dev Validates asset for MetaVault
     * @param asset address
     */
    function _validateAsset(address asset) private view {
        if (!assetGroupRegistry.isTokenAllowed(asset)) revert UnsupportedAsset();
    }
}
