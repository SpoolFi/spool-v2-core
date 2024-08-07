// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../MainnetExtendedSetup.s.sol";

contract MetamorphoGauntletStrategySetup is MainnetExtendedSetup {
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

        MetamorphoStrategy implementation = deployMetamorphoImplementation(contracts);

        deployMetamorpho(contracts, implementation, false, 0);
    }

    function test_mock_MetamorphoGauntletStrategySetup() external pure {}
}
