// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../SepoliaExtendedSetup.s.sol";

// source .env && FOUNDRY_PROFILE=sepolia-production forge script Mock2StrategyDeployment --slow --broadcast --legacy
contract Mock2StrategyDeployment is SepoliaExtendedSetup {
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

        deployMock(contracts);
    }
}
