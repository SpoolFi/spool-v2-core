// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../SepoliaExtendedSetup.s.sol";

contract UpgradeWETH is SepoliaExtendedSetup {
    uint256 deployerPrivateKey;

    function broadcast() public override {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        // Deploy new implementation
        vm.broadcast(deployerPrivateKey);
        MockStrategy implementation = new MockStrategy(
            assetGroupRegistry,
            spoolAccessControl
        );

        address beacon = contractsJson().getAddress(".strategies.mock.beacon");

        vm.broadcast(deployerPrivateKey);
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(beacon)), address(implementation));
    }
}
