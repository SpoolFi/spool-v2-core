// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../SepoliaExtendedSetup.s.sol";

import "../../../src/guards/UnlockGuard.sol";
import "../../../src/SmartVaultFactory.sol";

contract DeployUnlockGuard is SepoliaExtendedSetup {
    uint256 privKey;

    function broadcast() public override {
        privKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        // deploy UnlockGuard contract
        vm.startBroadcast(privKey);
        address implementation = address(new UnlockGuard(spoolAccessControl));
        address proxy = address(new TransparentUpgradeableProxy(implementation, address(proxyAdmin), ""));
        vm.stopBroadcast();

        contractsJson().reserializeKeyAddress("guards");
        contractsJson().addProxyGuard("UnlockGuard", implementation, proxy);
    }
}
