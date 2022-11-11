// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "../../src/managers/UsdPriceFeedManager.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

contract MockPriceFeedManager is IUsdPriceFeedManager {
    uint256 private constant USD_DECIMALS = 26;
    mapping(address => uint256) public exchangeRates;

    constructor() {}

    function assetDecimals(address asset) external view returns (uint256) {
        return ERC20(asset).decimals();
    }

    function usdDecimals() external pure returns (uint256) {
        return USD_DECIMALS;
    }

    function setExchangeRate(address asset, uint256 rate) external {
        exchangeRates[asset] = rate;
    }

    function assetToUsd(address asset, uint256 assetAmount) external view returns (uint256) {
        return exchangeRates[asset] * assetAmount / 10 ** ERC20(asset).decimals();
    }

    function usdToAsset(address asset, uint256 usdAmount) external view returns (uint256) {
        return usdAmount * 10 ** ERC20(asset).decimals() / exchangeRates[asset];
    }

    function assetToUsdCustomPrice(address asset, uint256 assetAmount, uint256 price) external view returns (uint256) {
        return assetAmount * price / ERC20(asset).decimals();
    }

    function usdToAssetCustomPrice(address asset, uint256 usdAmount, uint256 price) external view returns (uint256) {
        return usdAmount * ERC20(asset).decimals() / price;
    }
}
