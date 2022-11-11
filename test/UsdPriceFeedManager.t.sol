// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/external/interfaces/chainlink/AggregatorV3Interface.sol";
import "../src/managers/UsdPriceFeedManager.sol";
import "./mocks/MockAggregatorV3.sol";

contract UsdPriceFeedManagerTest is Test {
    address daiAddress = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    MockAggregatorV3 daiUsdPriceAggregator;

    UsdPriceFeedManager usdPriceFeedManager;

    function setUp() public {
        usdPriceFeedManager = new UsdPriceFeedManager();
        daiUsdPriceAggregator = new MockAggregatorV3(8, "Dai-Usd", 1);
    }

    function _setDaiAsset() public {
        usdPriceFeedManager.setAsset(daiAddress, 18, daiUsdPriceAggregator, true);
    }

    function test_usdDecimals_shouldReturnDecimals() public {
        assertEq(usdPriceFeedManager.usdDecimals(), 26);
    }

    function test_setAsset_shouldSetAsset() public {
        _setDaiAsset();

        assertEq(usdPriceFeedManager.assetDecimals(daiAddress), 18);
        assertEq(usdPriceFeedManager.assetMultiplier(daiAddress), 10 ** 18);
        assertEq(address(usdPriceFeedManager.assetPriceAggregator(daiAddress)), address(daiUsdPriceAggregator));
        assertEq(usdPriceFeedManager.assetPriceAggregatorMultiplier(daiAddress), 10 ** 18);
        assertEq(usdPriceFeedManager.assetValidity(daiAddress), true);
    }

    function test_assetToUsd_shouldConvert() public {
        _setDaiAsset();
        daiUsdPriceAggregator.pushAnswer(1_00007408);

        assertEq(usdPriceFeedManager.assetToUsd(daiAddress, 1_854895125485269876), 1_85503253611616582479241408);
    }

    function test_assetToUsd_shouldRevertWhenAssetIsNotValid() public {
        daiUsdPriceAggregator.pushAnswer(1_00007408);

        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector, daiAddress));
        usdPriceFeedManager.assetToUsd(daiAddress, 1);
    }

    function test_assetToUsd_shouldRevertWhenPriceIsZero() public {
        _setDaiAsset();
        daiUsdPriceAggregator.pushAnswer(0);

        vm.expectRevert(abi.encodeWithSelector(NonPositivePrice.selector, 0));
        usdPriceFeedManager.assetToUsd(daiAddress, 1);
    }

    function test_assetToUsd_shouldRevertWhenPriceIsNegative() public {
        _setDaiAsset();
        daiUsdPriceAggregator.pushAnswer(-1);

        vm.expectRevert(abi.encodeWithSelector(NonPositivePrice.selector, -1));
        usdPriceFeedManager.assetToUsd(daiAddress, 1);
    }

    function test_usdToAsset_shouldConvert() public {
        _setDaiAsset();
        daiUsdPriceAggregator.pushAnswer(1_00007408);

        assertEq(usdPriceFeedManager.usdToAsset(daiAddress, 1_85503253611616582479241408), 1_854895125485269876);
    }

    function test_usdToAsset_shouldRevertWhenAssetIsNotValid() public {
        daiUsdPriceAggregator.pushAnswer(1_00007408);

        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector, daiAddress));
        usdPriceFeedManager.usdToAsset(daiAddress, 1);
    }

    function test_usdToAsset_shouldRevertWhenPriceIsZero() public {
        _setDaiAsset();
        daiUsdPriceAggregator.pushAnswer(0);

        vm.expectRevert(abi.encodeWithSelector(NonPositivePrice.selector, 0));
        usdPriceFeedManager.usdToAsset(daiAddress, 1);
    }

    function test_usdToAsset_shouldRevertWhenPriceIsNegative() public {
        _setDaiAsset();
        daiUsdPriceAggregator.pushAnswer(-1);

        vm.expectRevert(abi.encodeWithSelector(NonPositivePrice.selector, -1));
        usdPriceFeedManager.usdToAsset(daiAddress, 1);
    }

    function test_assetToUsdCustomPrice_shouldConvert() public {
        _setDaiAsset();
        daiUsdPriceAggregator.pushAnswer(1_00007408);

        uint256 price = usdPriceFeedManager.assetToUsd(daiAddress, 10 ** usdPriceFeedManager.assetDecimals(daiAddress));

        assertEq(
            usdPriceFeedManager.assetToUsdCustomPrice(daiAddress, 1_854895125485269876, price),
            1_85503253611616582479241408
        );
    }

    function test_assetToUsdCustomPrice_shouldRevertWhenAssetIsNotValid() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector, daiAddress));
        usdPriceFeedManager.assetToUsdCustomPrice(daiAddress, 1, 1);
    }

    function test_usdToAssetCustomPrice_shouldConvert() public {
        _setDaiAsset();
        daiUsdPriceAggregator.pushAnswer(1_00007408);

        uint256 price = usdPriceFeedManager.assetToUsd(daiAddress, 10 ** usdPriceFeedManager.assetDecimals(daiAddress));

        assertEq(
            usdPriceFeedManager.usdToAssetCustomPrice(daiAddress, 1_85503253611616582479241408, price),
            1_854895125485269876
        );
    }

    function test_usdToAssetCustomPrice_shouldRevertWhenAssetIsNotValid() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector, daiAddress));
        usdPriceFeedManager.usdToAssetCustomPrice(daiAddress, 1, 1);
    }
}
