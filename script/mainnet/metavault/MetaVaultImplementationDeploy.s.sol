// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {MetaVault} from "../../../src/MetaVault.sol";
import "../MainnetExtendedSetup.s.sol";

/**
 *  source .env && forge script script/mainnet/metavault/MetaVaultImplementationDeploy.s.sol:MetaVaultImplementationDeploy --rpc-url=$MAINNET_RPC_URL --with-gas-price 2000000000 --slow --broadcast --legacy --optimizer-runs 200 --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract MetaVaultImplementationDeploy is MainnetExtendedSetup {
    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function doSetup() public override {
        loadSpool();
        loadAssets(assetGroupRegistry, Extended.INITIAL);
    }

    function execute() public override {
        vm.startBroadcast(_deployerPrivateKey);
        address implementation =
            address(new MetaVault(smartVaultManager, spoolAccessControl, metaVaultGuard, spoolLens));
        vm.stopBroadcast();

        contractsJson().add("MetaVaultImplementation", implementation);
    }
}
