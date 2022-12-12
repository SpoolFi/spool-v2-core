// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";

/* ========== ERRORS ========== */

/**
 * @notice Used when invalid ID for asset group is provided.
 * @param assetGroupId Invalid ID for asset group.
 */
error InvalidAssetGroup(uint256 assetGroupId);

/**
 * @notice Used when no assets are provided for an asset group.
 */
error NoAssetsProvided();

/* ========== INTERFACES ========== */

interface IAssetGroupRegistry {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Gets number of registered asset groups.
     * @return Number of registered asset groups.
     */
    function numberOfAssetGroups() external view returns (uint256);

    /**
     * @notice Gets asset group by its ID.
     * @dev Requirements:
     * - must provide a valid ID for the asset group
     * @return Array of assets in the asset group.
     */
    function listAssetGroup(uint256 assetGroupId) external view returns (address[] memory);

    /**
     * @notice Gets asset group length.
     * @dev Requirements:
     * - must provide a valid ID for the asset group
     */
    function assetGroupLength(uint256 assetGroupId) external view returns (uint256);

    /**
     * @notice Validates that provided ID represents an asset group.
     * @dev Function reverts when ID does not represent an asset group.
     * @param assetGroupId ID to validate.
     */
    function validateAssetGroup(uint256 assetGroupId) external view;

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Registers a new asset group.
     * @dev Requirements:
     * - must provide at least one asset
     * @param assets Array of assets in the asset group.
     * @return Sequential ID assigned to the asset group.
     */
    function registerAssetGroup(address[] calldata assets) external returns (uint256);
}
