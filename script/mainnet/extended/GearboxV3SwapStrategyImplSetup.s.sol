// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../MainnetExtendedSetup.s.sol";

contract GearboxV3SwapStrategyImplSetup is MainnetExtendedSetup {
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

        // reserialize strategies
        contractsJson().reserializeKeyAddress("strategies");

        vm.broadcast(_deployerPrivateKey);
        address implementation = address(
            new GearboxV3SwapStrategy(contracts.assetGroupRegistry, contracts.accessControl, contracts.swapper, usdPriceFeedManager)
        );

        contractsJson().addVariantStrategyImplementation(GEARBOX_V3_KEY, "swap", implementation);
    }
}
