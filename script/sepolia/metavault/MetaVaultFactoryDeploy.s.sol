// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {MetaVaultFactory} from "../../../src/MetaVaultFactory.sol";
import "../SepoliaExtendedSetup.s.sol";

/**
 *  source .env && forge script script/sepolia/metavault/MetaVaultFactoryDeploy.s.sol:MetaVaultFactoryDeploy --rpc-url=$SEPOLIA_RPC_URL --with-gas-price 2000000000 --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract MetaVaultFactoryDeploy is SepoliaExtendedSetup {
    uint256 _deployerPrivateKey;

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        address metaVaultImplementation = contractsJson().getAddress(".MetaVaultImplementation");

        vm.startBroadcast(_deployerPrivateKey);
        address factory = address(new MetaVaultFactory(metaVaultImplementation, spoolAccessControl, assetGroupRegistry));
        vm.stopBroadcast();

        contractsJson().add("MetaVaultFactory", factory);
    }
}
