// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../MainnetExtendedSetup.s.sol";

contract AaveGhoStakingStrategyRound0Setup is MainnetExtendedSetup {
    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        StandardContracts memory contracts = StandardContracts({
            accessControl: spoolAccessControl,
            assetGroupRegistry: assetGroupRegistry,
            swapper: swapper,
            proxyAdmin: address(proxyAdmin),
            strategyRegistry: strategyRegistry
        });

        contractsJson().reserializeKeyAddress("strategies");

        AaveGhoStakingStrategy implementation = deployAaveGhoStakingImplementation(contracts, usdPriceFeedManager);
        deployAaveGhoStakingVariants(contracts, implementation, false, 0);
    }
}
