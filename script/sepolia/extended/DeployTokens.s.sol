// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "src/Token.sol";
import "forge-std/Script.sol";

contract DeployTokens is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Token usdc = new Token("USDC", "USDC", 18);

        console.log("USDC address: %s", address(usdc));
    }
}
