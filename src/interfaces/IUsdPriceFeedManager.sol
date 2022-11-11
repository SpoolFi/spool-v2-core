// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

interface IUsdPriceFeedManager {
    /**
     * @notice Gets number of decimals for an asset.
     * @param asset Address of the asset.
     * @return assetDecimals Number of decimals for the asset.
     */
    function assetDecimals(address asset) external view returns (uint256 assetDecimals);

    /**
     * @notice Gets number of decimals for USD.
     * @return usdDecimals Number of decimals for USD.
     */
    function usdDecimals() external view returns (uint256 usdDecimals);

    /**
     * @notice Calculates asset value in USD using current price.
     * @param asset Address of asset.
     * @param assetAmount Amount of asset in asset decimals.
     * @return usdValue Value in USD in USD decimals.
     */
    function assetToUsd(address asset, uint256 assetAmount) external view returns (uint256 usdValue);

    /**
     * @notice Calculates USD value in asset using current price.
     * @param asset Address of asset.
     * @param usdAmount Amount of USD in USD decimals.
     * @return assetValue Value in asset in asset decimals.
     */
    function usdToAsset(address asset, uint256 usdAmount) external view returns (uint256 assetValue);

    /**
     * @notice Calculates asset value in USD using provided price.
     * @param asset Address of asset.
     * @param assetAmount Amount of asset in asset decimals.
     * @param price Price of asset in USD.
     * @return usdValue Value in USD in USD decimals.
     */
    function assetToUsdCustomPrice(address asset, uint256 assetAmount, uint256 price)
        external
        view
        returns (uint256 usdValue);

    /**
     * @notice Calculates USD value in asset using provided price.
     * @param asset Address of asset.
     * @param usdAmount Amount of USD in USD decimals.
     * @param price Price of asset in USD.
     * @return assetValue Value in asset in asset decimals.
     */
    function usdToAssetCustomPrice(address asset, uint256 usdAmount, uint256 price)
        external
        view
        returns (uint256 assetValue);
}
