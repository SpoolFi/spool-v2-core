// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {
    MetamorphoStrategyV2,
    IAssetGroupRegistry,
    ISpoolAccessControl,
    ISwapper
} from "../../../src/strategies/MetamorphoStrategyV2.sol";

/**
 * source .env && FOUNDRY_PROFILE=mainnet-production forge script script/mainnet/upgrade/DeployMetamorphoStrategyV2.s.sol:DeployMetamorphoStrategyV2 --optimizer-runs 1000 --rpc-url=$MAINNET_RPC_URL --with-gas-price 2000000000 --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployMetamorphoStrategyV2 is Script {
    function run() external {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        MetamorphoStrategyV2 implementation = new MetamorphoStrategyV2(
            IAssetGroupRegistry(0x1Aa2a802BA25669531Ffd2b1fF8ae94f3D87f41A),
            ISpoolAccessControl(0x7b533e72E0cDC63AacD8cDB926AC402b846Fbd13),
            ISwapper(0x33E52c206d584550193E642C8982f2Fff6339994)
        );
        console.log("MetamorphoStrategyV2 implementation deployed at: %s", address(implementation));
    }
}
