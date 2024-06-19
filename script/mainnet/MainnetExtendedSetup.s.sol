// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/utils/Strings.sol";
import "forge-std/Script.sol";
import "../helper/JsonHelper.sol";
import "../DeploySpool.s.sol";
import "./AssetsInitial.s.sol";
import "./StrategiesInitial.s.sol";

contract MainnetExtendedSetup is Script, DeploySpool, AssetsInitial, StrategiesInitial {
    JsonReader internal _constantsJson;
    JsonReadWriter internal _contractsJson;

    uint256 internal _deployerPrivateKey;

    function run() external virtual {
        init();

        doSetup();

        broadcast();

        execute();
    }

    function broadcast() public virtual {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(_deployerPrivateKey);
    }

    function init() public virtual {
        string memory environment = vm.envString("ENVIRONMENT");
        require(
            Strings.equal(environment, "production") || Strings.equal(environment, "staging"), "Environment is not set"
        );
        _constantsJson = new JsonReader(vm, string.concat("deploy/mainnet.", environment, ".constants.json"));
        _contractsJson = new JsonReadWriter(vm, string.concat("deploy/mainnet.", environment, ".contracts.json"));
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
