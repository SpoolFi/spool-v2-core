// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {MetaVaultGuard} from "../../../src/MetaVaultGuard.sol";
import "../MainnetExtendedSetup.s.sol";

/**
 *  source .env && forge script script/mainnet/metavault/MetaVaultGuardDeploy.s.sol:MetaVaultGuardDeploy --rpc-url=$MAINNET_RPC_URL --with-gas-price 10000000000 --slow --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract MetaVaultGuardDeploy is MainnetExtendedSetup {
    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function doSetup() public override {
        loadSpool();
        loadAssets(assetGroupRegistry, Extended.INITIAL);
    }

    function execute() public override {
        vm.startBroadcast(_deployerPrivateKey);
        address implementation = address(new MetaVaultGuard(smartVaultManager, assetGroupRegistry, guardManager));
        address proxy = address(new TransparentUpgradeableProxy(implementation, address(proxyAdmin), ""));
        vm.stopBroadcast();
        contractsJson().addProxy("MetaVaultGuard", implementation, proxy);
    }
}
