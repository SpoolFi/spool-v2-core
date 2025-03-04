// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "./EthereumForkConstants.sol";
import "./arbitrum/ArbitrumForkConstants.sol";
import "./sepolia/SepoliaForkConstants.sol";

contract ForkTestFixture is Test {
    uint256 internal mainnetForkId;

    function setUpForkTestFixture() internal virtual {
        mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK);
    }

    function setUpForkTestFixtureArbitrum() internal virtual {
        mainnetForkId = vm.createFork(vm.rpcUrl("arbitrum"), ARBITRUM_FORK_BLOCK);
    }

    function setUpForkTestFixtureSepolia() internal virtual {
        mainnetForkId = vm.createFork(vm.rpcUrl("sepolia"), SEPOLIA_FORK_BLOCK);
    }

    function test_mock_ForkTestFixture() external pure {}
}
