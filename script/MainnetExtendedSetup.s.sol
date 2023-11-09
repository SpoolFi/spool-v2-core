// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "./helper/JsonHelper.sol";
import "./DeploySpool.s.sol";
import "./mainnet/AssetsInitial.s.sol";
import "./mainnet/StrategiesInitial.s.sol";

contract MainnetExtendedSetup is Script, DeploySpool, AssetsInitial, StrategiesInitial {
    JsonReader internal _constantsJson;
    JsonReadWriter internal _contractsJson;

    function run() external virtual {
        init();

        doSetup();

        broadcast();

        execute();
    }

    function broadcast() public virtual {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
    }

    function init() public virtual {
        _constantsJson = new JsonReader(vm, string.concat("deploy/mainnet.constants.json"));
        _contractsJson = new JsonReadWriter(vm, string.concat("deploy/mainnet.contracts.json"));
    }

    function doSetup() public {
        loadSpool();

        loadAssets(assetGroupRegistry);
    }

    function execute() public virtual {}

    function assets(string memory assetKey) public view virtual override returns (address) {
        return _assets[assetKey];
    }

    function assetGroups(string memory assetGroupKey) public view virtual override returns (uint256) {
        return _assetGroups[assetGroupKey];
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

    function contractsJson() internal view virtual override(DeploySpool, StrategiesInitial) returns (JsonReadWriter) {
        return _contractsJson;
    }

    function test_mock_MainnetExtendedSetup() external pure {}
}
