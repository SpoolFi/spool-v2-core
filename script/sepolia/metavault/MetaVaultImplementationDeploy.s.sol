// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {MetaVault} from "../../../src/MetaVault.sol";
import "../SepoliaExtendedSetup.s.sol";

/**
 *  source .env && forge script script/sepolia/metavault/MetaVaultImplementationDeploy.s.sol:MetaVaultImplementationDeploy --rpc-url=$SEPOLIA_RPC_URL --with-gas-price 2000000000 --slow --broadcast --legacy --optimizer-runs 200 --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract MetaVaultImplementationDeploy is SepoliaExtendedSetup {
    uint256 _deployerPrivateKey;

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        vm.startBroadcast(_deployerPrivateKey);
        address implementation =
            address(new MetaVault(smartVaultManager, spoolAccessControl, metaVaultGuard, spoolLens));
        vm.stopBroadcast();

        contractsJson().add("MetaVaultImplementation", implementation);
    }
}
