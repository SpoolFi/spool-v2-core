// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../SepoliaExtendedSetup.s.sol";

contract ClientStrategyDeployment is SepoliaExtendedSetup {
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

        // change string to client ID as needed
        deployClientMock(contracts, "mock");
    }
}
