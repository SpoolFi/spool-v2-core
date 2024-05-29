// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../MainnetExtendedSetup.s.sol";

contract EthenaStrategySetup is MainnetExtendedSetup {
    function execute() public override {
        StandardContracts memory contracts = StandardContracts({
            accessControl: spoolAccessControl,
            assetGroupRegistry: assetGroupRegistry,
            swapper: swapper,
            proxyAdmin: address(proxyAdmin),
            strategyRegistry: strategyRegistry
        });

        // reserialize strategies
        contractsJson().reserializeKeyAddress("strategies");

        string memory assetKey = vm.envString("ASSET_KEY");
        deployEthena(contracts, assetKey);
    }
}
