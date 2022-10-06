// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../interfaces/IStrategyManager.sol";

contract StrategyManager is IStrategyManager {
    /* ========== STATE VARIABLES ========== */

    /// @notice TODO
    mapping(address => bool) internal _strategies;

    /// @notice TODO
    mapping(address => address[]) _smartVaultStrategies;

    /// @notice TODO
    mapping(address => uint256) _latestIndexes;

    /// @notice TODO strategy => index => token => amount
    mapping(address => mapping(uint256 => mapping(address => uint256))) _strategyDeposits;

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice TODO
     */
    function isStrategy(address strategy) external view returns (bool) {
        return _strategies[strategy];
    }

    /**
     * @notice TODO
     */
    function getLatestIndexes(address smartVault) external view returns (uint256[] memory) {
        revert("0");
    }

    /**
     * @notice TODO
     */
    function strategies(address smartVault) external view returns (address[] memory strategyAddresses) {
        return _smartVaultStrategies[smartVault];
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice TODO
     */
    function registerStrategy(address strategy) external {
        _strategies[strategy] = true;
    }

    /**
     * @notice TODO
     */
    function removeStrategy(address strategy) external {
        _strategies[strategy] = false;
    }

    /**
     * @notice TODO
     */
    function setStrategies(address smartVault, address[] memory strategies_) external {
        _smartVaultStrategies[smartVault] = strategies_;
    }

    /**
     * @notice TODO
     */
    function addStrategyDeposits(
        address smartVault,
        uint256[] memory allocations,
        uint256[] memory amounts,
        address[] memory tokens
    ) external {
        require(tokens.length == amounts.length, "StrategyManager::addStrategyDeposit: Invalid length");
        // address[] memory strategies = _smartVaultStrategies[smartVault];
        // uint256[] memory allocations = ...

        // TODO:
        // - fetch smart vault strats and allocations
        // - loop strats and calculate deposit amounts per token and strategy
        // - fetch last index for strat
        // - update _strategyDeposits accordingly
    }
}
