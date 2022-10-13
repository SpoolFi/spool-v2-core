// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IUsdPriceFeedManager {
    function usdDecimals() external view returns (uint256 usdDecimals);
    function assetToUsd(address asset, uint256 assetAmount) external view returns (uint256 usdAmount);
    function usdToAsset(address asset, uint256 usdAmount) external view returns (uint256 assetAmount);
}
