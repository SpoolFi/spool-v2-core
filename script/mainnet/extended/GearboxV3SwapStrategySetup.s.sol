// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../MainnetExtendedSetup.s.sol";

contract GearboxV3SwapStrategySetup is MainnetExtendedSetup {
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

        GearboxV3SwapStrategy implementation = getGearboxV3SwapImplementation();
        deployGearboxV3Swap(contracts, implementation, false, 0);
    }

    function _createAndInitializeGearboxV3Swap(
        StandardContracts memory contracts,
        GearboxV3SwapStrategy implementation,
        string memory variantName,
        uint256 assetGroupId,
        IFarmingPool sdToken
    ) internal override returns (address variant) {
        vm.startBroadcast(_deployerPrivateKey);
        variant = super._createAndInitializeGearboxV3Swap(contracts, implementation, variantName, assetGroupId, sdToken);
        vm.stopBroadcast();
    }
}
