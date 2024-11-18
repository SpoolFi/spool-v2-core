// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../MainnetExtendedSetup.s.sol";

contract GearboxV3ExtraStrategySetup is MainnetExtendedSetup {
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

        deployGearboxV3Round1(contracts, false);
    }

    function _createAndInitializeGearboxV3(
        StandardContracts memory contracts,
        GearboxV3Strategy implementation,
        string memory variantName,
        uint256 assetGroupId,
        IFarmingPool sdToken
    ) internal override returns (address variant) {
        vm.startBroadcast(_deployerPrivateKey);
        variant = super._createAndInitializeGearboxV3(contracts, implementation, variantName, assetGroupId, sdToken);
        vm.stopBroadcast();
    }
}
