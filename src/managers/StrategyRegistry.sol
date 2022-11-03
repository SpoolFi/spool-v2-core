// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/CommonErrors.sol";

contract StrategyRegistry is IStrategyRegistry {
    /* ========== STATE VARIABLES ========== */

    address internal _smartVaultManager;

    /// @notice TODO
    mapping(address => bool) internal _strategies;

    /// @notice TODO
    mapping(address => uint256) _currentIndexes;

    /// @notice TODO strategy => index => tokenAmounts
    mapping(address => mapping(uint256 => uint256[])) _strategyDeposits;

    /// @notice TODO strategy => index => sstAmount
    mapping(address => mapping(uint256 => uint256)) _withdrawnShares;

    /// @notice TODO strategy => index => tokenAmounts
    mapping(address => mapping(uint256 => uint256[])) _withdrawnAssets;

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice TODO
     */
    function isStrategy(address strategy) external view returns (bool) {
        return _strategies[strategy];
    }

    /**
     * @notice Deposits for given strategy and DHW index
     */
    function strategyDeposits(address strategy, uint256 index) external view returns (uint256[] memory) {
        return _strategyDeposits[strategy][index];
    }

    /**
     * @notice Deposits for given strategy and DHW index
     */
    function currentIndex(address strategy) external view returns (uint256) {
        return _currentIndexes[strategy];
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function setSmartVaultManger(address smartVaultManager_) external {
        _smartVaultManager = smartVaultManager_;
    }

    /**
     * @notice TODO
     */
    function registerStrategy(address strategy) external {
        if (_strategies[strategy]) revert StrategyAlreadyRegistered({address_: strategy});
        _strategies[strategy] = true;
    }

    /**
     * @notice TODO
     */
    function removeStrategy(address strategy) external {
        if (!_strategies[strategy]) revert InvalidStrategy({address_: strategy});
        _strategies[strategy] = false;
    }

    /**
     * @notice TODO: just a quick mockup so we can test withdrawals
     */
    function dhw(address[] memory strategies_) external {
        for (uint256 i = 0; i < strategies_.length; i++) {
            uint256[] memory withdrawnAssets_ =
                IStrategy(strategies_[i]).dhw(_withdrawnShares[strategies_[i]][_currentIndexes[strategies_[i]]]);

            _withdrawnAssets[strategies_[i]][_currentIndexes[strategies_[i]]] = withdrawnAssets_;
            // TODO: transfer assets to smart vault manager
            _currentIndexes[strategies_[i]]++;
        }
    }

    function addDeposits(address[] memory strategies_, uint256[][] memory amounts)
        external
        returns (uint256[] memory)
    {
        uint256[] memory indexes = new uint256[](strategies_.length);
        for (uint256 i = 0; i < strategies_.length; i++) {
            address strategy = strategies_[i];
            uint256 latestIndex = _currentIndexes[strategy];
            indexes[i] = latestIndex;
            bool initialized = _strategyDeposits[strategy][latestIndex].length > 0;

            for (uint256 j = 0; j < amounts[i].length; j++) {
                if (initialized) {
                    _strategyDeposits[strategy][latestIndex][j] += amounts[i][j];
                } else {
                    _strategyDeposits[strategy][latestIndex].push(amounts[i][j]);
                }
            }
        }

        return indexes;
    }

    function addWithdrawals(address[] memory strategies_, uint256[] memory strategyShares)
        external
        returns (uint256[] memory)
    {
        uint256[] memory indexes = new uint256[](strategies_.length);

        for (uint256 i = 0; i < strategies_.length; i++) {
            address strategy = strategies_[i];
            uint256 latestIndex = _currentIndexes[strategy];

            indexes[i] = latestIndex;
            _withdrawnShares[strategy][latestIndex] += strategyShares[i];
        }

        return indexes;
    }

    function claimWithdrawals(
        address[] memory strategies_,
        uint256[] memory dhwIndexes,
        uint256[] memory strategyShares
    ) external view onlySmartVaultManager returns (uint256[] memory) {
        address[] memory tokens = IStrategy(strategies_[0]).asset();
        uint256[] memory totalWithdrawnAssets = new uint256[](tokens.length);

        for (uint256 i = 0; i < strategies_.length; i++) {
            address strategy = strategies_[i];
            uint256 dhwIndex = dhwIndexes[i];

            if (dhwIndex == _currentIndexes[strategy]) {
                revert DhwNotRunYetForIndex(strategy, dhwIndex);
            }

            for (uint256 j = 0; j < totalWithdrawnAssets.length; j++) {
                totalWithdrawnAssets[j] +=
                    _withdrawnAssets[strategy][dhwIndex][j] * strategyShares[i] / _withdrawnShares[strategy][dhwIndex];
                // there will be dust left after all vaults sync
            }
        }

        return totalWithdrawnAssets;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _onlySmartVaultManager() internal view {
        if (msg.sender != _smartVaultManager) {
            revert NotSmartVaultManager(msg.sender);
        }
    }

    /* ========== MODIFIERS ========== */

    modifier onlySmartVaultManager() {
        _onlySmartVaultManager();
        _;
    }
}
