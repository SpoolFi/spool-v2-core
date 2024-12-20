// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../MainnetExtendedSetup.s.sol";

contract MetamorphoRound2StrategySetup is MainnetExtendedSetup {
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

        deployMetamorphoRound2(contracts, getMetamorphoImplementation(), false);
    }

    function _createAndInitializeMetamorpho(
        StandardContracts memory contracts,
        MetamorphoStrategy implementation,
        string memory variantName,
        uint256 assetGroupId,
        IERC4626 vault,
        address[] memory rewards
    ) internal override returns (address variant) {
        vm.startBroadcast(_deployerPrivateKey);
        variant =
            super._createAndInitializeMetamorpho(contracts, implementation, variantName, assetGroupId, vault, rewards);
        vm.stopBroadcast();
    }
}
