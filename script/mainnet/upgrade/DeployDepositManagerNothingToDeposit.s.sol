// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../../../src/managers/DepositManager.sol";
import "../MainnetExtendedSetup.s.sol";

contract DeployDepositManagerNothingToDeposit is MainnetExtendedSetup {
    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        vm.broadcast(_deployerPrivateKey);
        DepositManager implementation = new DepositManager(
            strategyRegistry,
            usdPriceFeedManager,
            guardManager,
            actionManager,
            spoolAccessControl,
            masterWallet,
            address(ghostStrategy)
        );

        _contractsJson.addProxy("DepositManager", address(implementation), address(depositManager));
    }
}
