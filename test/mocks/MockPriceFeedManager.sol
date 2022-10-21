pragma solidity ^0.8.13;

import "../../src/managers/UsdPriceFeedManager.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

contract MockPriceFeedManager is IUsdPriceFeedManager {
    uint256 private constant USD_DECIMALS = 26;
    mapping(address => uint256) public exchangeRates;

    constructor() {}

    function usdDecimals() external view returns (uint256 usdDecimals) {
        return USD_DECIMALS;
    }

    function setExchangeRate(address asset, uint256 rate) external {
        exchangeRates[asset] = rate;
    }

    function assetToUsd(address asset, uint256 assetAmount) external view returns (uint256 usdAmount) {
        return exchangeRates[asset] * assetAmount / 10 ** ERC20(asset).decimals();
    }

    function usdToAsset(address asset, uint256 usdAmount) external view returns (uint256 assetAmount) {
        return usdAmount * 10 ** ERC20(asset).decimals() / exchangeRates[asset];
    }
}
