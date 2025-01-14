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
string constant DAI_USDC_USDT_KEY = "dai-usdc-usdt";
string constant USDE_KEY = "usde";
string constant PYUSD_KEY = "pyusd";
string constant WBTC_KEY = "wbtc";
string constant GHO_KEY = "gho";

enum Extended {
    INITIAL,
    OETH,
    CONVEX_STETH_FRXETH,
    GEARBOX_V3_ROUND_0,
    METAMORPHO_ROUND_0,
    USDE,
    METAMORPHO_ROUND_1,
    GEARBOX_V3_ROUND_1,
    GEARBOX_V3_SWAP,
    METAMORPHO_ROUND_2,
    APXETH,
    AAVE_GHO_STAKING_ROUND_0,
    CURRENT
}

contract AssetsInitial {
    function constantsJson() internal view virtual returns (JsonReader) {}

    mapping(string => address) internal _assets;
    mapping(string => uint256) internal _assetGroups;

    function setupAssets(
        IAssetGroupRegistry assetGroupRegistry,
        UsdPriceFeedManager priceFeedManager,
        Extended extended
    ) public {
        setAssets(assetGroupRegistry, priceFeedManager, extended);
        createAssetGroups(assetGroupRegistry, extended);
    }

    function setAssets(IAssetGroupRegistry assetGroupRegistry, UsdPriceFeedManager priceFeedManager, Extended extended)
        public
    {
        uint256 numAssets = getNumAssets(extended);
        string[] memory assetNames = new string[](numAssets);
        assetNames[0] = DAI_KEY;
        assetNames[1] = USDC_KEY;
        assetNames[2] = USDT_KEY;
        assetNames[3] = WETH_KEY;
        if (extended >= Extended.USDE) {
            assetNames[4] = USDE_KEY;
        }
        if (extended >= Extended.METAMORPHO_ROUND_1) {
            assetNames[5] = PYUSD_KEY;
        }
        if (extended >= Extended.METAMORPHO_ROUND_2) {
            assetNames[6] = WBTC_KEY;
        }
        if (extended >= Extended.AAVE_GHO_STAKING_ROUND_0) {
            assetNames[7] = GHO_KEY;
        }

        _setAssets(assetGroupRegistry, priceFeedManager, assetNames);
    }

    function _setAssets(
        IAssetGroupRegistry assetGroupRegistry,
        UsdPriceFeedManager priceFeedManager,
        string[] memory assetNames
    ) internal {
        address[] memory assetAddresses = new address[](assetNames.length);
        address[] memory assetPriceAggregators = new address[](assetNames.length);
        uint256[] memory assetTimeLimits = new uint256[](assetNames.length);
        for (uint256 i; i < assetNames.length; ++i) {
            assetAddresses[i] = constantsJson().getAddress(string.concat(".assets.", assetNames[i], ".address"));
            assetPriceAggregators[i] =
                constantsJson().getAddress(string.concat(".assets.", assetNames[i], ".priceAggregator.address"));
            assetTimeLimits[i] =
                constantsJson().getUint256(string.concat(".assets.", assetNames[i], ".priceAggregator.timeLimit"));
        }

        assetGroupRegistry.allowTokenBatch(assetAddresses);

        for (uint256 i; i < assetNames.length; ++i) {
            _assets[assetNames[i]] = assetAddresses[i];

            priceFeedManager.setAsset(
                assetAddresses[i], AggregatorV3Interface(assetPriceAggregators[i]), true, assetTimeLimits[i]
            );
        }
    }

    function createAssetGroups(IAssetGroupRegistry assetGroupRegistry, Extended extended) public {
        _createAssetGroup(assetGroupRegistry, ArraysHelper.toArray(WETH_KEY));

        _createAssetGroup(assetGroupRegistry, ArraysHelper.toArray(USDC_KEY));

        _createAssetGroup(assetGroupRegistry, ArraysHelper.toArray(USDT_KEY));

        _createAssetGroup(assetGroupRegistry, ArraysHelper.toArray(DAI_KEY));

        _createAssetGroup(assetGroupRegistry, ArraysHelper.toArray(DAI_KEY, USDC_KEY, USDT_KEY));

        if (extended >= Extended.USDE) {
            _createAssetGroup(assetGroupRegistry, ArraysHelper.toArray(USDE_KEY));
        }

        if (extended >= Extended.METAMORPHO_ROUND_1) {
            _createAssetGroup(assetGroupRegistry, ArraysHelper.toArray(PYUSD_KEY));
        }
        if (extended >= Extended.METAMORPHO_ROUND_2) {
            _createAssetGroup(assetGroupRegistry, ArraysHelper.toArray(WBTC_KEY));
        }
    }

    function _createAssetGroup(IAssetGroupRegistry assetGroupRegistry, string[] memory keys) internal {
        address[] memory assetGroup = new address[](keys.length);
        string memory key;
        for (uint256 i; i < keys.length; ++i) {
            assetGroup[i] = _assets[keys[i]];
            key = string.concat(key, keys[i], (i < keys.length - 1) ? "-" : "");
        }
        assetGroup = ArraysHelper.sort(assetGroup);
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        _assetGroups[key] = assetGroupId;
    }

    function loadAssets(IAssetGroupRegistry assetGroupRegistry, Extended extended) public {
        loadAssets(extended);
        loadAssetGroups(assetGroupRegistry, extended);
    }

    function loadAssets(Extended extended) public {
        uint256 numAssets = getNumAssets(extended);
        string[] memory assetNames = new string[](numAssets);
        assetNames[0] = DAI_KEY;
        assetNames[1] = USDC_KEY;
        assetNames[2] = USDT_KEY;
        assetNames[3] = WETH_KEY;
        if (extended >= Extended.USDE) {
            assetNames[4] = USDE_KEY;
        }
        if (extended >= Extended.METAMORPHO_ROUND_1) {
            assetNames[5] = PYUSD_KEY;
        }
        if (extended >= Extended.METAMORPHO_ROUND_2) {
            assetNames[6] = WBTC_KEY;
        }

        for (uint256 i; i < assetNames.length; ++i) {
            _assets[assetNames[i]] = constantsJson().getAddress(string.concat(".assets.", assetNames[i], ".address"));
        }
    }

    function loadAssetGroups(IAssetGroupRegistry assetGroupRegistry, Extended extended) public {
        address[] memory assetGroup = new address[](1);

        assetGroup[0] = _assets[DAI_KEY];
        _assetGroups[DAI_KEY] = assetGroupRegistry.checkAssetGroupExists(assetGroup);

        assetGroup[0] = _assets[USDC_KEY];
        _assetGroups[USDC_KEY] = assetGroupRegistry.checkAssetGroupExists(assetGroup);

        assetGroup[0] = _assets[USDT_KEY];
        _assetGroups[USDT_KEY] = assetGroupRegistry.checkAssetGroupExists(assetGroup);

        assetGroup[0] = _assets[WETH_KEY];
        _assetGroups[WETH_KEY] = assetGroupRegistry.checkAssetGroupExists(assetGroup);

        assetGroup = new address[](3);
        assetGroup[0] = _assets[DAI_KEY];
        assetGroup[1] = _assets[USDC_KEY];
        assetGroup[2] = _assets[USDT_KEY];
        assetGroup = ArraysHelper.sort(assetGroup);
        _assetGroups[DAI_USDC_USDT_KEY] = assetGroupRegistry.checkAssetGroupExists(assetGroup);

        assetGroup = new address[](1);
        if (extended >= Extended.USDE) {
            assetGroup[0] = _assets[USDE_KEY];
            _assetGroups[USDE_KEY] = assetGroupRegistry.checkAssetGroupExists(assetGroup);
        }

        if (extended >= Extended.METAMORPHO_ROUND_1) {
            assetGroup[0] = _assets[PYUSD_KEY];
            _assetGroups[PYUSD_KEY] = assetGroupRegistry.checkAssetGroupExists(assetGroup);
        }

        if (extended >= Extended.METAMORPHO_ROUND_2) {
            assetGroup[0] = _assets[WBTC_KEY];
            _assetGroups[WBTC_KEY] = assetGroupRegistry.checkAssetGroupExists(assetGroup);
        }
    }

    function getNumAssets(Extended extended) internal pure returns (uint256 numAssets) {
        numAssets = 4; // initial asset length
        if (extended >= Extended.USDE) {
            numAssets++;
        }
        if (extended >= Extended.METAMORPHO_ROUND_1) {
            numAssets++;
        }
        if (extended >= Extended.METAMORPHO_ROUND_2) {
            numAssets++;
        }
        if (extended >= Extended.AAVE_GHO_STAKING_ROUND_0) {
            numAssets++;
        }
    }

    function test_mock_AssetsInitial() external pure {}
}
