// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {SpoolMulticall} from "../../../src/SpoolMulticall.sol";
import "../SepoliaExtendedSetup.s.sol";

/**
 *  source .env && forge script script/sepolia/metavault/SpoolMulticallDeploy.s.sol:SpoolMulticallDeploy --rpc-url=$SEPOLIA_RPC_URL --with-gas-price 2000000000 --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract SpoolMulticallDeploy is SepoliaExtendedSetup {
    uint256 _deployerPrivateKey;

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        vm.startBroadcast(_deployerPrivateKey);
        address spoolMulticall = address(new SpoolMulticall(spoolAccessControl));
        vm.stopBroadcast();

        contractsJson().add("SpoolMulticall", spoolMulticall);
    }
}
