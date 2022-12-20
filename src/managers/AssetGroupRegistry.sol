// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "../interfaces/IAssetGroupRegistry.sol";

/* ========== CONTRACTS ========== */

contract AssetGroupRegistry is IAssetGroupRegistry {
    // TODO: asset allowlist
    // TODO: access control
    // TODO: events
    // TODO: asset group -> smart vault mapping
    // TODO: asset group -> strategy mapping

    /* ========== STATE VARIABLES ========== */

    address[][] private _assetGroups;

    /* ========== CONSTRUCTOR ========== */

    constructor() {}

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function numberOfAssetGroups() external view returns (uint256) {
        return _assetGroups.length;
    }

    function listAssetGroup(uint256 assetGroupId)
        external
        view
        validAssetGroup(assetGroupId)
        returns (address[] memory)
    {
        return _assetGroups[assetGroupId];
    }

    function assetGroupLength(uint256 assetGroupId) external view validAssetGroup(assetGroupId) returns (uint256) {
        return _assetGroups[assetGroupId].length;
    }

    function validateAssetGroup(uint256 assetGroupId) external view {
        _checkIsValidAssetGroup(assetGroupId);
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function registerAssetGroup(address[] calldata assets) external returns (uint256) {
        if (assets.length == 0) {
            revert NoAssetsProvided();
        }

        // NOTE: verify the group doesn't exist (hash)
        _assetGroups.push(assets);

        return _assetGroups.length - 1;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _checkIsValidAssetGroup(uint256 assetGroupId) private view {
        if (assetGroupId >= _assetGroups.length) {
            revert InvalidAssetGroup(assetGroupId);
        }
    }

    /* ========== MODIFIERS ========== */

    modifier validAssetGroup(uint256 assetGroupId) {
        _checkIsValidAssetGroup(assetGroupId);
        _;
    }
}
