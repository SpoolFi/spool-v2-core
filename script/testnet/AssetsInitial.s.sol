// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../../src/interfaces/IAssetGroupRegistry.sol";
import "../../src/managers/UsdPriceFeedManager.sol";
import "../helper/ArraysHelper.sol";
import "../helper/JsonHelper.sol";
import "../../test/mocks/MockToken.sol";

string constant DAI_KEY = "dai";
string constant USDC_KEY = "usdc";
string constant USDT_KEY = "usdt";
string constant WETH_KEY = "weth";

contract AssetsInitial {
    function constantsJson() internal view virtual returns (JsonReader) {}

    mapping(string => address) internal _assets;
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
        address[] memory assetPriceAggregators = new address[](assetNames.length);
        uint256[] memory assetTimeLimits = new uint256[](assetNames.length);
        for (uint256 i; i < assetNames.length; ++i) {
            assetAddresses[i] = constantsJson().getAddress(string.concat(".assets.", assetNames[i], ".address"));
            assetPriceAggregators[i] =
                constantsJson().getAddress(string.concat(".assets.", assetNames[i], ".priceAggregator.address"));
            assetTimeLimits[i] = uint256(type(uint64).max);
        }

        assetGroupRegistry.allowTokenBatch(assetAddresses);

        for (uint256 i; i < assetNames.length; ++i) {
            _assets[assetNames[i]] = assetAddresses[i];

            priceFeedManager.setAsset(
                assetAddresses[i], AggregatorV3Interface(assetPriceAggregators[i]), true, assetTimeLimits[i]
            );
        }
    }

    function createAssetGroups(IAssetGroupRegistry assetGroupRegistry) public {
        address[] memory assetGroup = new address[](1);
        uint256 assetGroupId;

        assetGroup[0] = _assets[WETH_KEY];
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        _assetGroups[WETH_KEY] = assetGroupId;

        assetGroup[0] = _assets[USDC_KEY];
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        _assetGroups[USDC_KEY] = assetGroupId;

        assetGroup[0] = _assets[USDT_KEY];
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        _assetGroups[USDT_KEY] = assetGroupId;

        assetGroup[0] = _assets[DAI_KEY];
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        _assetGroups[DAI_KEY] = assetGroupId;
    }

    function loadAssets(IAssetGroupRegistry assetGroupRegistry) public {
        loadAssets();
        loadAssetGroups(assetGroupRegistry);
    }

    function loadAssets() public {
        string[] memory assetNames = new string[](4);
        assetNames[0] = DAI_KEY;
        assetNames[1] = USDC_KEY;
        assetNames[2] = USDT_KEY;
        assetNames[3] = WETH_KEY;

        for (uint256 i; i < assetNames.length; ++i) {
            _assets[assetNames[i]] = constantsJson().getAddress(string.concat(".assets.", assetNames[i], ".address"));
        }
    }

    function loadAssetGroups(IAssetGroupRegistry assetGroupRegistry) public {
        address[] memory assetGroup = new address[](1);

        assetGroup[0] = _assets[DAI_KEY];
        _assetGroups[DAI_KEY] = assetGroupRegistry.checkAssetGroupExists(assetGroup);

        assetGroup[0] = _assets[USDC_KEY];
        _assetGroups[USDC_KEY] = assetGroupRegistry.checkAssetGroupExists(assetGroup);

        assetGroup[0] = _assets[USDT_KEY];
        _assetGroups[USDT_KEY] = assetGroupRegistry.checkAssetGroupExists(assetGroup);

        assetGroup[0] = _assets[WETH_KEY];
        _assetGroups[WETH_KEY] = assetGroupRegistry.checkAssetGroupExists(assetGroup);
    }

    function test_mock_AssetsInitial() external pure {}
}
