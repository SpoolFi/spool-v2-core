// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../../src/interfaces/IAssetGroupRegistry.sol";
import "../../src/managers/UsdPriceFeedManager.sol";
import "../helper/ArraysHelper.sol";
import "../helper/JsonHelper.sol";

string constant DAI_KEY = "dai";
string constant USDC_KEY = "usdc";
string constant USDT_KEY = "usdt";
string constant WETH_KEY = "weth";

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
        assetNames[0] = DAI_KEY;
        assetNames[1] = USDC_KEY;
        assetNames[2] = USDT_KEY;
        assetNames[3] = WETH_KEY;

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

        assetGroup[0] = assets[WETH_KEY];
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        _assetGroups[WETH_KEY] = assetGroupId;

        assetGroup[0] = assets[USDC_KEY];
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        _assetGroups[USDC_KEY] = assetGroupId;

        assetGroup[0] = assets[USDT_KEY];
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        _assetGroups[USDT_KEY] = assetGroupId;

        assetGroup[0] = assets[DAI_KEY];
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        _assetGroups[DAI_KEY] = assetGroupId;

        assetGroup = new address[](3);
        assetGroup[0] = assets[DAI_KEY];
        assetGroup[1] = assets[USDC_KEY];
        assetGroup[2] = assets[USDT_KEY];
        assetGroup = ArraysHelper.sort(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        _assetGroups["dai-usdc-usdt"] = assetGroupId;
    }

    function test_mock_AssetsInitial() external pure {}
}
