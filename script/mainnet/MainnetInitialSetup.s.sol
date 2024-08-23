// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/utils/Strings.sol";
import "forge-std/Script.sol";
import "../helper/JsonHelper.sol";
import "../DeploySpool.s.sol";
import "./AssetsInitial.s.sol";
import "./StrategiesInitial.s.sol";

contract MainnetInitialSetup is Script, DeploySpool, AssetsInitial, StrategiesInitial {
    JsonReader internal _constantsJson;
    JsonReadWriter internal _contractsJson;

    function run() external virtual {
        init();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        doSetup(deployerAddress, Extended.CURRENT);
    }

    function init() public virtual {
        string memory profile = vm.envString("FOUNDRY_PROFILE");
        require(
            Strings.equal(profile, "mainnet-production") || Strings.equal(profile, "mainnet-staging"),
            "Mainnet Foundry profile is not set"
        );
        _constantsJson = new JsonReader(vm, string.concat("deploy/", profile, ".constants.json"));
        _contractsJson = new JsonReadWriter(vm, string.concat("deploy/", profile, ".contracts.json"));
    }

    function doSetup(address deployerAddress, Extended extended) public {
        deploySpool();

        setupAssets(assetGroupRegistry, usdPriceFeedManager, extended);

        deployStrategies(
            spoolAccessControl,
            assetGroupRegistry,
            swapper,
            address(proxyAdmin),
            strategyRegistry,
            usdPriceFeedManager,
            extended
        );

        string memory profile = vm.envString("FOUNDRY_PROFILE");
        if (!Strings.equal(profile, "mainnet-staging")) {
            postDeploySpool(deployerAddress);
        }
    }

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

    function test_mock_MainnetInitialSetup() external pure {}
}
