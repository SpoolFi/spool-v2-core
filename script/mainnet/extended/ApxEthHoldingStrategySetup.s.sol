// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../MainnetExtendedSetup.s.sol";

contract ApxEthHoldingStrategySetup is MainnetExtendedSetup {
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

        deployApxEth(contracts, false);
    }

    function _deployApxEthImplementation(StandardContracts memory contracts)
        internal
        override
        returns (ApxEthHoldingStrategy implementation)
    {
        vm.startBroadcast(_deployerPrivateKey);
        implementation = super._deployApxEthImplementation(contracts);
        vm.stopBroadcast();
    }

    function _deployApxEthProxyAndInitialize(
        StandardContracts memory contracts,
        ApxEthHoldingStrategy implementation,
        string memory variantName,
        uint256 assetGroupId,
        IPirexEth pirexEth
    ) internal override returns (address variant) {
        vm.startBroadcast(_deployerPrivateKey);
        variant = super._deployApxEthProxyAndInitialize(contracts, implementation, variantName, assetGroupId, pirexEth);
        vm.stopBroadcast();
    }
}
