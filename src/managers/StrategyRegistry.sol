// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/IUsdPriceFeedManager.sol";

contract StrategyRegistry is IStrategyRegistry {
    /* ========== STATE VARIABLES ========== */

    /// @notice TODO
    mapping(address => bool) internal _strategies;

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

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice TODO
     */
    function registerStrategy(address strategy) external {
        require(!_strategies[strategy], "StrategyRegistry::registerStrategy: Strategy already registered.");
        _strategies[strategy] = true;
    }

    /**
     * @notice TODO
     */
    function removeStrategy(address strategy) external {
        require(_strategies[strategy], "StrategyRegistry::registerStrategy: Strategy not registered.");
        _strategies[strategy] = false;
    }
}
