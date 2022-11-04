// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "../src/managers/AssetGroupRegistry.sol";
import "./mocks/MockToken.sol";

contract AssetGroupRegistryTest is Test {
    AssetGroupRegistry private assetGroupRegistry;

    IERC20 private tokenA;
    IERC20 private tokenB;
    IERC20 private tokenC;

    function setUp() public {
        assetGroupRegistry = new AssetGroupRegistry();

        tokenA = new MockToken("TokenA", "TA");
        tokenB = new MockToken("TokenB", "TB");
        tokenC = new MockToken("TokenC", "TC");
    }

    function test_registerAssetGroup_shouldRegisterAssetGroup() public {
        address[] memory assets1 = new address[](1);
        assets1[0] = address(tokenA);

        uint256 id1 = assetGroupRegistry.registerAssetGroup(assets1);

        assertEq(id1, 0);
        assertEq(assetGroupRegistry.numberOfAssetGroups(), 1);
        address[] memory retrievedAssets1 = assetGroupRegistry.listAssetGroup(id1);
        assertEq(retrievedAssets1.length, 1);
        assertEq(address(retrievedAssets1[0]), address(tokenA));

        address[] memory assets2 = new address[](2);
        assets2[0] = address(tokenB);
        assets2[1] = address(tokenC);

        uint256 id2 = assetGroupRegistry.registerAssetGroup(assets2);

        assertEq(id2, 1);
        assertEq(assetGroupRegistry.numberOfAssetGroups(), 2);
        address[] memory retrievedAssets2 = assetGroupRegistry.listAssetGroup(id2);
        assertEq(retrievedAssets2.length, 2);
        assertEq(address(retrievedAssets2[0]), address(tokenB));
        assertEq(address(retrievedAssets2[1]), address(tokenC));
    }

    function test_registerAssetGroup_shouldRevertWhenProvidedWithEmptyAssetGroup() public {
        address[] memory assets = new address[](0);

        vm.expectRevert(NoAssetsProvided.selector);
        assetGroupRegistry.registerAssetGroup(assets);
    }

    function test_listAssetGroup_shouldRevertWhenProvidedWithInvalidAssetGroupId() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAssetGroup.selector, 0));
        assetGroupRegistry.listAssetGroup(0);
    }
}
