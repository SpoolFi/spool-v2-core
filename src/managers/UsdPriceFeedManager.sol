// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../external/interfaces/chainlink/AggregatorV3Interface.sol";
import "../interfaces/IUsdPriceFeedManager.sol";

/* ========== ERRORS ========== */

/**
 * @notice Emitted when asset is invalid.
 * @param asset Invalid asset.
 */
error InvalidAsset(address asset);

/**
 * @notice Emitted when price returned by price aggregator is negative or zero.
 * @param price Actual price returned by price aggregator.
 */
error NonPositivePrice(int256 price);

contract UsdPriceFeedManager is IUsdPriceFeedManager {
    /* ========== STATE VARIABLES ========== */

    uint256 private constant USD_DECIMALS = 26;

    mapping(address => uint256) public assetDecimals;
    mapping(address => uint256) public assetMultiplier;
    mapping(address => AggregatorV3Interface) public assetPriceAggregator;
    mapping(address => uint256) public assetPriceAggregatorMultiplier;
    mapping(address => bool) public assetValidity;

    /* ========== CONSTRUCTOR ========== */

    constructor() {}

    /* ========== ADMIN FUNCTIONS ========== */

    // TODO: access control
    function setAsset(
        address asset,
        uint256 decimals,
        AggregatorV3Interface priceAggregator,
        bool validity
    ) external {
        assetDecimals[asset] = decimals;
        assetMultiplier[asset] = 10 ** decimals;
        assetPriceAggregator[asset] = priceAggregator;
        assetPriceAggregatorMultiplier[asset] = 10 ** (USD_DECIMALS - priceAggregator.decimals());
        assetValidity[asset] = validity;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice Returns decimal places used for USD amount.
     * @return Decimal places used for USD.
     */
    function usdDecimals() external pure returns (uint256) {
        return USD_DECIMALS;
    }

    /**
     * @notice Calculates asset worth in USD.
     * @dev Requirements:
     * - asset must be valid
     * @param asset Asset used in conversion.
     * @param assetAmount Amount of asset to convert (in asset decimals).
     * @return USD amount (in USD decimals).
     */
    function assetToUsd(
        address asset,
        uint256 assetAmount
    ) external view onlyValidAsset(asset) returns (uint256) {
        return assetAmount * _getAssetPriceInUsd(asset) * assetPriceAggregatorMultiplier[asset] / assetMultiplier[asset];
    }

    /**
     * @notice Calculates USD worth in asset.
     * @dev Requirements:
     * - asset must be valid
     * @param asset Asset used in conversion.
     * @param usdAmount Amount of USD to convert (in USD decimals).
     * @return Asset amount (in asset decimals).
     */
    function usdToAsset(
        address asset,
        uint256 usdAmount
    ) external view onlyValidAsset(asset) returns (uint256) {
        return usdAmount * assetMultiplier[asset] / assetPriceAggregatorMultiplier[asset] / _getAssetPriceInUsd(asset);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @dev Gets latest asset price in USD from oracle.
     * @param asset Asset for price lookup.
     * @return Latest asset price.
     */
    function _getAssetPriceInUsd(address asset) private view returns (uint256) {
        (
            /* uint80 roundId */,
            int256 answer,
            /* uint256 startedAt */,
            /* uint256 updatedAt */,
            /* uint80 answeredInRound */
        ) = assetPriceAggregator[asset].latestRoundData();

        if (answer <= 0) {
            revert NonPositivePrice({
                price: answer
            });
        }

        return uint256(answer);
    }

    /**
     * @dev Ensures that the asset is valid.
     */
    function _onlyValidAsset(address asset) private view {
        if (!assetValidity[asset]) {
            revert InvalidAsset({
                asset: asset
            });
        }
    }

    /* ========== MODIFIERS ========== */

    /**
     * @notice Throws if the asset is not valid.
     */
    modifier onlyValidAsset(address asset) {
        _onlyValidAsset(asset);
        _;
    }
}
