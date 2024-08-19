// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../../../src/strategies/GearboxV3AirdropStrategy.sol";
import "../MainnetExtendedSetup.s.sol";

contract DeployGearboxV3AirdropImplementation is MainnetExtendedSetup {
    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        vm.broadcast(_deployerPrivateKey);
        GearboxV3AirdropStrategy implementation = new GearboxV3AirdropStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            swapper
        );

        // reserialize strategies
        _contractsJson.reserializeKeyAddress("strategies");
        _contractsJson.addVariantStrategyVariant("gearbox-v3", "implementation-airdrop", address(implementation));
    }
}
