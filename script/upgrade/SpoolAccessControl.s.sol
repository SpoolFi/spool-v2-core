// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {SpoolAccessControl} from "../../src/access/SpoolAccessControl.sol";

/**
 *  source .env && forge script script/upgrade/SpoolAccessControl.s.sol:SpoolAccessControlUpgrade --rpc-url=$MAINNET_RPC_URL --with-gas-price 10000000000 --slow --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract SpoolAccessControlUpgrade is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        SpoolAccessControl spoolAccessControl = new SpoolAccessControl();
        console.log("SpoolAccessControl implementation deployed at: %s", address(spoolAccessControl));
    }
}
