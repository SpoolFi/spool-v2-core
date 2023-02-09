// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "../interfaces/IMasterWallet.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/ISwapper.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/CommonErrors.sol";
import "../access/SpoolAccessControllable.sol";
import "../libraries/ArrayMapping.sol";
import "../libraries/SpoolUtils.sol";

/**
 * @dev Requires roles:
 * - ROLE_MASTER_WALLET_MANAGER
 * - ADMIN_ROLE_STRATEGY
 */
contract StrategyRegistry is IStrategyRegistry, SpoolAccessControllable {
    using ArrayMapping for mapping(uint256 => uint256);
    using uint16a16Lib for uint16a16;

    /* ========== STATE VARIABLES ========== */

    /// @notice Wallet holding funds pending DHW
    IMasterWallet immutable _masterWallet;

    /// @notice Price feed manager
    IUsdPriceFeedManager immutable _priceFeedManager;

    address private immutable _ghostStrategy;

    /// @notice Current DHW index for strategies
    mapping(address => uint256) internal _currentIndexes;

    /**
     * @notice Strategy asset ratios at last DHW.
     * @dev strategy => assetIndex => exchange rate
     */
    mapping(address => mapping(uint256 => uint256)) internal _dhwAssetRatios;

    /**
     * @notice Asset to USD exchange rates.
     * @dev strategy => index => asset index => exchange rate
     */
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _exchangeRates;

    /**
     * @notice Assets deposited into the strategy.
     * @dev strategy => index => asset index => desposited amount
     */
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _assetsDeposited;

    /**
     * @notice Amount of SSTs minted for deposits.
     * @dev strategy => index => SSTs minted
     */
    mapping(address => mapping(uint256 => uint256)) internal _sharesMinted;

    /**
     * @notice Timestamp at which DHW was executed at.
     * @dev strategy => index => DHW timestamp
     */
    mapping(address => mapping(uint256 => uint256)) internal _dhwTimestamp;

    /**
     * @notice Amount of SSTs redeemed from strategy.
     * @dev strategy => index => SSTs redeemed
     */
    mapping(address => mapping(uint256 => uint256)) internal _sharesRedeemed;

    /**
     * @notice Amount of assets withdrawn from protocol.
     * @dev strategy => index => asset index => amount withdrawn
     */
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _assetsWithdrawn;

    constructor(
        IMasterWallet masterWallet_,
        ISpoolAccessControl accessControl_,
        IUsdPriceFeedManager priceFeedManager_,
        address ghostStrategy_
    ) SpoolAccessControllable(accessControl_) {
        _masterWallet = masterWallet_;
        _priceFeedManager = priceFeedManager_;
        _ghostStrategy = ghostStrategy_;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Deposits for given strategy and DHW index
     */
    function depositedAssets(address strategy, uint256 index) external view returns (uint256[] memory) {
        uint256 assetGroupLength = IStrategy(strategy).assets().length;
        return _assetsDeposited[strategy][index].toArray(assetGroupLength);
    }

    /**
     * @notice Current DHW indexes for given strategies
     */
    function currentIndex(address[] calldata strategies) external view returns (uint256[] memory) {
        uint256[] memory indexes = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            indexes[i] = _currentIndexes[strategies[i]];
        }

        return indexes;
    }

    function assetRatioAtLastDhw(address strategy) external view returns (uint256[] memory) {
        return _dhwAssetRatios[strategy].toArray(IStrategy(strategy).assets().length);
    }

    /**
     * @notice Get state of a strategy for a given DHW index
     */
    function strategyAtIndexBatch(address[] calldata strategies, uint16a16 dhwIndexes)
        external
        view
        returns (StrategyAtIndex[] memory)
    {
        StrategyAtIndex[] memory result = new StrategyAtIndex[](strategies.length);

        for (uint256 i = 0; i < strategies.length; i++) {
            result[i] = strategyAtIndex(strategies[i], dhwIndexes.get(i));
        }

        return result;
    }

    /**
     * @notice Get state of a strategy for a given DHW index
     */
    function strategyAtIndex(address strategy, uint256 dhwIndex) public view returns (StrategyAtIndex memory) {
        uint256 assetGroupLength = IStrategy(strategy).assets().length;

        return StrategyAtIndex({
            exchangeRates: _exchangeRates[strategy][dhwIndex].toArray(assetGroupLength),
            assetsDeposited: _assetsDeposited[strategy][dhwIndex].toArray(assetGroupLength),
            sharesMinted: _sharesMinted[strategy][dhwIndex],
            dhwTimestamp: _dhwTimestamp[strategy][dhwIndex]
        });
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Add strategy to registry
     */
    function registerStrategy(address strategy) external {
        if (_accessControl.hasRole(ROLE_STRATEGY, strategy)) revert StrategyAlreadyRegistered({address_: strategy});

        _accessControl.grantRole(ROLE_STRATEGY, strategy);
        _currentIndexes[strategy] = 1;
        _dhwAssetRatios[strategy].setValues(IStrategy(strategy).assetRatio());
    }

    /**
     * @notice Remove strategy from registry
     */
    function removeStrategy(address strategy) external onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender) {
        if (!_accessControl.hasRole(ROLE_STRATEGY, strategy)) revert InvalidStrategy({address_: strategy});
        _accessControl.revokeRole(ROLE_STRATEGY, strategy);
    }

    /**
     * @notice TODO: just a quick mockup so we can test withdrawals
     */
    function doHardWork(address[] memory strategies_, SwapInfo[][] calldata swapInfo) external {
        uint256 assetGroupId;
        address[] memory assetGroup;
        uint256[] memory exchangeRates;

        for (uint256 i = 0; i < strategies_.length; i++) {
            if (strategies_[i] == _ghostStrategy) {
                continue;
            }

            IStrategy strategy = IStrategy(strategies_[i]);

            if (assetGroup.length == 0) {
                // First strategy being processes should set asset group and exchange rates,
                // since they are common for all strategies.
                assetGroupId = strategy.assetGroupId();
                assetGroup = strategy.assets();
                exchangeRates = SpoolUtils.getExchangeRates(assetGroup, _priceFeedManager);
            } else {
                // Check that all strategies use same asset group.
                if (strategy.assetGroupId() != assetGroupId) {
                    revert NotSameAssetGroup();
                }
            }

            uint256 dhwIndex = _currentIndexes[address(strategy)];

            // Transfer deposited assets to the strategy.
            for (uint256 j = 0; j < assetGroup.length; j++) {
                uint256 deposited = _assetsDeposited[address(strategy)][dhwIndex][j];

                if (deposited > 0) {
                    _masterWallet.transfer(
                        IERC20(assetGroup[j]), address(strategy), _assetsDeposited[address(strategy)][dhwIndex][j]
                    );
                }
            }

            // Call strategy to do hard work.
            DhwInfo memory dhwInfo = strategy.doHardWork(
                swapInfo[i],
                _sharesRedeemed[address(strategy)][dhwIndex],
                address(_masterWallet),
                exchangeRates,
                _priceFeedManager
            );

            // Bookkeeping.
            _dhwAssetRatios[address(strategy)].setValues(strategy.assetRatio());
            _currentIndexes[address(strategy)]++;
            _exchangeRates[address(strategy)][dhwIndex].setValues(exchangeRates);
            _sharesMinted[address(strategy)][dhwIndex] = dhwInfo.sharesMinted;
            _assetsWithdrawn[address(strategy)][dhwIndex].setValues(dhwInfo.assetsWithdrawn);
            _dhwTimestamp[address(strategy)][dhwIndex] = block.timestamp;
        }
    }

    function addDeposits(address[] memory strategies_, uint256[][] memory amounts)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint16a16)
    {
        uint16a16 indexes;
        for (uint256 i = 0; i < strategies_.length; i++) {
            address strategy = strategies_[i];

            uint256 latestIndex = _currentIndexes[strategy];
            indexes = indexes.set(i, latestIndex);

            for (uint256 j = 0; j < amounts[i].length; j++) {
                _assetsDeposited[strategy][latestIndex][j] += amounts[i][j];
            }
        }

        return indexes;
    }

    function addWithdrawals(address[] memory strategies_, uint256[] memory strategyShares)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint16a16)
    {
        uint16a16 indexes;

        for (uint256 i = 0; i < strategies_.length; i++) {
            address strategy = strategies_[i];
            uint256 latestIndex = _currentIndexes[strategy];

            indexes = indexes.set(i, latestIndex);
            _sharesRedeemed[strategy][latestIndex] += strategyShares[i];
        }

        return indexes;
    }

    function redeemFast(address[] memory strategies_, uint256[] memory strategyShares, address[] memory assetGroup)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint256[] memory)
    {
        uint256[] memory withdrawnAssets = new uint256[](assetGroup.length);

        for (uint256 i = 0; i < strategies_.length; i++) {
            uint256[] memory strategyWithdrawnAssets = IStrategy(strategies_[i]).redeemFast(
                strategyShares[i],
                address(_masterWallet),
                assetGroup,
                SpoolUtils.getExchangeRates(assetGroup, _priceFeedManager),
                _priceFeedManager
            );

            for (uint256 j = 0; j < strategyWithdrawnAssets.length; j++) {
                withdrawnAssets[j] += strategyWithdrawnAssets[j];
            }
        }

        return withdrawnAssets;
    }

    function claimWithdrawals(address[] memory strategies_, uint16a16 dhwIndexes, uint256[] memory strategyShares)
        external
        view
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint256[] memory)
    {
        address[] memory assetGroup;
        uint256[] memory totalWithdrawnAssets;

        for (uint256 i = 0; i < strategies_.length; i++) {
            address strategy = strategies_[i];

            if (strategies_[i] == _ghostStrategy) {
                continue;
            }

            if (assetGroup.length == 0) {
                assetGroup = IStrategy(strategy).assets();
                totalWithdrawnAssets = new uint256[](assetGroup.length);
            }

            uint256 dhwIndex = dhwIndexes.get(i);

            if (dhwIndex == _currentIndexes[strategy]) {
                revert DhwNotRunYetForIndex(strategy, dhwIndex);
            }

            for (uint256 j = 0; j < totalWithdrawnAssets.length; j++) {
                totalWithdrawnAssets[j] +=
                    _assetsWithdrawn[strategy][dhwIndex][j] * strategyShares[i] / _sharesRedeemed[strategy][dhwIndex];
                // there will be dust left after all vaults sync
            }
        }

        return totalWithdrawnAssets;
    }
}
