// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../interfaces/IStrategyManager.sol";

contract StrategyManager is IStrategyManager {
    mapping(address => bool) internal _strategies;

    mapping(address => address[]) _smartVaultStrategies;

    function isStrategy(address strategy) external view returns (bool) {
        return _strategies[strategy];
    }

    function registerStrategy(address strategy) external {
        _strategies[strategy] = true;
    }

    function removeStrategy(address strategy) external {
        _strategies[strategy] = false;
    }

    function getLatestIndexes(address smartVault) external view returns (uint256[] memory) {
        revert("0");
    }

    function strategies(address smartVault) external view returns (address[] memory strategyAddresses) {
        return _smartVaultStrategies[smartVault];
    }

    function setStrategies(address smartVault, address[] memory strategies_) external {
        _smartVaultStrategies[smartVault] = strategies_;
    }
}
