// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/CommonErrors.sol";
import "../interfaces/ISmartVaultManager.sol";
import "../interfaces/IMasterWallet.sol";
import "../libraries/ArrayMapping.sol";
import "../libraries/SpoolUtils.sol";
import "../access/SpoolAccessControl.sol";

contract StrategyRegistry is IStrategyRegistry, SpoolAccessControllable {
    using ArrayMapping for mapping(uint256 => uint256);

    /* ========== STATE VARIABLES ========== */

    IMasterWallet immutable _masterWallet;

    IUsdPriceFeedManager immutable _priceFeedManager;

    /// @notice TODO
    mapping(address => bool) private _strategies;

    /// @notice TODO
    mapping(address => uint256) private _currentIndexes;

    /// @notice TODO strategy => index => depositAmounts
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) private _depositedAssets;

    /// @notice TODO strategy => index => depositSlippages
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) private _depositSlippages;

    /// @notice TODO strategy => index => depositExchangeRates
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) private _dhwExchangeRates;

    /// @notice TODO strategy => index => sstAmount
    mapping(address => mapping(uint256 => uint256)) private _withdrawnShares;

    /// @notice TODO strategy => index => tokenAmounts
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) private _withdrawnAssets;

    /// @notice TODO strategy => index => SSTs minted
    mapping(address => mapping(uint256 => uint256)) private _sharesMinted;

    constructor(IMasterWallet masterWallet_, ISpoolAccessControl accessControl_, IUsdPriceFeedManager priceFeedManager_)
        SpoolAccessControllable(accessControl_)
    {
        _masterWallet = masterWallet_;
        _priceFeedManager = priceFeedManager_;
    }

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
    function depositedAssets(address strategy, uint256 index) external view returns (uint256[] memory) {
        uint256 assetGroupLength = IStrategy(strategy).assets().length;
        return _depositedAssets[strategy][index].toArray(assetGroupLength);
    }

    /**
     * @notice Deposits for given strategy and DHW index
     */
    function currentIndex(address strategy) external view returns (uint256) {
        return _currentIndexes[strategy];
    }

    /**
     * @notice Get state of a strategy for a given DHW index
     */
    function strategyAtIndex(address strategy, uint256 dhwIndex) external view returns (StrategyAtIndex memory) {
        uint256 assetGroupLength = IStrategy(strategy).assets().length;
        return StrategyAtIndex(
            _sharesMinted[strategy][dhwIndex],
            _depositedAssets[strategy][dhwIndex].toArray(assetGroupLength),
            _depositSlippages[strategy][dhwIndex].toArray(assetGroupLength),
            _dhwExchangeRates[strategy][dhwIndex].toArray(assetGroupLength)
        );
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

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
    function doHardWork(address[] memory strategies_) external {
        address[] memory assetGroup = IStrategy(strategies_[0]).assets();
        uint256[] memory exchangeRates = SpoolUtils.getExchangeRates(assetGroup, _priceFeedManager);

        for (uint256 i = 0; i < strategies_.length; i++) {
            IStrategy strategy = IStrategy(strategies_[i]);
            address strategyAddr = address(strategy);

            uint256 dhwIndex = _currentIndexes[strategyAddr];
            _dhwExchangeRates[strategyAddr][dhwIndex].setValues(exchangeRates);

            uint256[] memory withdrawnAssets_ = strategy.redeem(
                _withdrawnShares[strategyAddr][dhwIndex], address(_masterWallet), address(_masterWallet)
            );

            _withdrawnAssets[strategyAddr][dhwIndex].setValues(withdrawnAssets_);
            uint256 depositUSD = _priceFeedManager.assetToUsdCustomPriceBulk(
                assetGroup, _depositedAssets[strategyAddr][dhwIndex].toArray(assetGroup.length), exchangeRates
            );

            _sharesMinted[strategyAddr][dhwIndex] = depositUSD;

            // TODO: transfer assets to smart vault manager
            _currentIndexes[strategyAddr]++;
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

            for (uint256 j = 0; j < amounts[i].length; j++) {
                _depositedAssets[strategy][latestIndex][j] += amounts[i][j];
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
    ) external view onlyRole(ROLE_STRATEGY_CLAIMER, msg.sender) returns (uint256[] memory) {
        address[] memory tokens = IStrategy(strategies_[0]).assets();
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
}
