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

        deployYearnV3WithGauge(contracts, false);
    }

    function test_mock_MetamorphoGauntletStrategySetup() external pure {}
}
