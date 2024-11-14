// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../SepoliaExtendedSetup.s.sol";

import "../../../src/guards/TimelockGuard.sol";
import "../../../src/SmartVaultFactory.sol";

contract DeployTimelockGuard is SepoliaExtendedSetup {
    uint256 privKey;

    function broadcast() public override {
        privKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        // deploy TimelockGuard contract
        vm.broadcast(privKey);
        TimelockGuard guard = new TimelockGuard(spoolAccessControl);
        console.log("Deployed TimelockGuard with address: ", address(guard));
    }
}
