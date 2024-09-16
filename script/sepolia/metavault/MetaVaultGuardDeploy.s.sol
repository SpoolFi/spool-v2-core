// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {MetaVaultGuard} from "../../../src/MetaVaultGuard.sol";
import "../SepoliaExtendedSetup.s.sol";

/**
 *  source .env && forge script script/sepolia/metavault/MetaVaultGuardDeploy.s.sol:MetaVaultGuardDeploy --rpc-url=$SEPOLIA_RPC_URL --with-gas-price 2000000000 --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract MetaVaultGuardDeploy is SepoliaExtendedSetup {
    uint256 _deployerPrivateKey;

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        vm.startBroadcast(_deployerPrivateKey);
        address implementation = address(new MetaVaultGuard(smartVaultManager, assetGroupRegistry, guardManager));
        address proxy = address(new TransparentUpgradeableProxy(implementation, address(proxyAdmin), ""));
        vm.stopBroadcast();
        contractsJson().addProxy("MetaVaultGuard", implementation, proxy);
    }
}
