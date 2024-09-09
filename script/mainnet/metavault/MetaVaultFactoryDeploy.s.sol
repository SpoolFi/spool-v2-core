// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {MetaVaultFactory} from "../../../src/MetaVaultFactory.sol";
import "../MainnetExtendedSetup.s.sol";

/**
 *  source .env && forge script script/mainnet/metavault/MetaVaultFactoryDeploy.s.sol:MetaVaultFactoryDeploy --rpc-url=$MAINNET_RPC_URL --with-gas-price 10000000000 --slow --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract MetaVaultFactoryDeploy is MainnetExtendedSetup {
    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function doSetup() public override {
        loadSpool();
        loadAssets(assetGroupRegistry, Extended.INITIAL);
    }

    function execute() public override {
        address metaVaultImplementation = contractsJson().getAddress(".MetaVaultImplementation");

        vm.startBroadcast(_deployerPrivateKey);
        address factory = address(new MetaVaultFactory(metaVaultImplementation, spoolAccessControl, assetGroupRegistry));
        vm.stopBroadcast();

        contractsJson().add("MetaVaultFactory", factory);
    }
}
