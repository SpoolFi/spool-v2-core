// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../../mainnet/MainnetExtendedSetup.s.sol";

contract YearnV3WithGaugeStrategySetup is MainnetExtendedSetup {
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

        string memory environment = vm.envString("ENVIRONMENT");
        deployYearnV3WithGauge(contracts, Strings.equal(environment, "staging"));
    }

    function test_mock_strategySetup() external pure {}
}
