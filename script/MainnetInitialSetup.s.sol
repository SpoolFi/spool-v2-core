// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "./helper/JsonHelper.sol";
import "./DeploySpool.s.sol";
import "./mainnet/AssetsInitial.s.sol";
import "./mainnet/StrategiesInitial.s.sol";

contract MainnetInitialSetup is Script, DeploySpool, AssetsInitial, StrategiesInitial {
    JsonReader internal _constantsJson;
    JsonWriter internal _contractsJson;

    function run() external virtual {
        init();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        doSetup(deployerAddress);
    }

    function init() public virtual {
        _constantsJson = new JsonReader(vm, string.concat("deploy/mainnet.constants.json"));
        _contractsJson = new JsonWriter(string.concat("deploy/mainnet.contracts.json"));
    }

    function doSetup(address deployerAddress) public {
        deploySpool();

        setupAssets(assetGroupRegistry, usdPriceFeedManager);

        deployStrategies(spoolAccessControl, assetGroupRegistry, address(proxyAdmin), strategyRegistry);

        postDeploySpool(deployerAddress);
    }

    function assetGroups(string memory assetGroup) public view virtual override returns (uint256) {
        return _assetGroups[assetGroup];
    }

    function constantsJson()
        internal
        view
        virtual
        override(AssetsInitial, DeploySpool, StrategiesInitial)
        returns (JsonReader)
    {
        return _constantsJson;
    }

    function contractsJson() internal view virtual override(DeploySpool, StrategiesInitial) returns (JsonWriter) {
        return _contractsJson;
    }

    function test_mock_MainnetInitialSetup() external pure {}
}
