// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../../src/interfaces/IAssetGroupRegistry.sol";
import "../../src/managers/UsdPriceFeedManager.sol";
import "../helper/ArraysHelper.sol";
import "../helper/JsonHelper.sol";

contract AssetsInitial {
    function constantsJson() internal view virtual returns (JsonReader) {}

    mapping(string => address) public assets;
    mapping(string => uint256) internal _assetGroups;

    function setupAssets(IAssetGroupRegistry assetGroupRegistry, UsdPriceFeedManager priceFeedManager) public {
        setAssets(assetGroupRegistry, priceFeedManager);
        createAssetGroups(assetGroupRegistry);
    }

    function setAssets(IAssetGroupRegistry assetGroupRegistry, UsdPriceFeedManager priceFeedManager) public {
        string[] memory assetNames = new string[](4);
        assetNames[0] = "dai";
        assetNames[1] = "usdc";
        assetNames[2] = "usdt";
        assetNames[3] = "weth";

        address[] memory assetAddresses = new address[](assetNames.length);
        uint256[] memory assetDecimals = new uint256[](assetNames.length);
        address[] memory assetPriceAggregators = new address[](assetNames.length);
        for (uint256 i; i < assetNames.length; ++i) {
            assetAddresses[i] = constantsJson().getAddress(string.concat(".assets.", assetNames[i], ".address"));
            assetDecimals[i] = constantsJson().getUint256(string.concat(".assets.", assetNames[i], ".decimals"));
            assetPriceAggregators[i] =
                constantsJson().getAddress(string.concat(".assets.", assetNames[i], ".priceAggregator"));
        }

        assetGroupRegistry.allowTokenBatch(assetAddresses);

        for (uint256 i; i < assetNames.length; ++i) {
            assets[assetNames[i]] = assetAddresses[i];

            priceFeedManager.setAsset(
                assetAddresses[i], assetDecimals[i], AggregatorV3Interface(assetPriceAggregators[i]), true
            );
        }
    }

    function createAssetGroups(IAssetGroupRegistry assetGroupRegistry) public {
        address[] memory assetGroup = new address[](1);
        uint256 assetGroupId;

        assetGroup[0] = assets["weth"];
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        _assetGroups["weth"] = assetGroupId;

        assetGroup[0] = assets["usdc"];
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        _assetGroups["usdc"] = assetGroupId;

        assetGroup[0] = assets["usdt"];
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        _assetGroups["usdt"] = assetGroupId;

        assetGroup[0] = assets["dai"];
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        _assetGroups["dai"] = assetGroupId;

        assetGroup = new address[](3);
        assetGroup[0] = assets["dai"];
        assetGroup[1] = assets["usdc"];
        assetGroup[2] = assets["usdt"];
        assetGroup = ArraysHelper.sort(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        _assetGroups["dai-usdc-usdt"] = assetGroupId;
    }
}
