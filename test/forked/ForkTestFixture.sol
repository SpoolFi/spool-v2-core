// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "./EthereumForkConstants.sol";

contract ForkTestFixture is Test {
    uint256 internal mainnetForkId;

    function setUpForkTestFixture() internal {
        mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK);
    }
}
