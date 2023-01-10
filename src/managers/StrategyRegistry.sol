// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/CommonErrors.sol";
import "../interfaces/ISmartVaultManager.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/ISwapper.sol";
import "../libraries/ArrayMapping.sol";
import "../libraries/SpoolUtils.sol";
import "../access/SpoolAccessControl.sol";

/**
 * @dev Requires roles:
 * - ROLE_MASTER_WALLET_MANAGER
 */
contract StrategyRegistry is IStrategyRegistry, SpoolAccessControllable {
    using ArrayMapping for mapping(uint256 => uint256);

    /* ========== STATE VARIABLES ========== */

    /// @notice Wallet holding funds pending DHW
    IMasterWallet immutable _masterWallet;

    /// @notice Price feed manager
    IUsdPriceFeedManager immutable _priceFeedManager;

    /// @notice Strategy registry
    mapping(address => bool) internal _strategies;

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
     * @notice Amount of SSTs redeemed from strategy.
     * @dev strategy => index => SSTs redeemed
     */
    mapping(address => mapping(uint256 => uint256)) internal _sharesRedeemed;

    /**
     * @notice Amount of assets withdrawn from protocol.
     * @dev strategy => index => asset index => amount withdrawn
     */
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _assetsWithdrawn;

    constructor(IMasterWallet masterWallet_, ISpoolAccessControl accessControl_, IUsdPriceFeedManager priceFeedManager_)
        SpoolAccessControllable(accessControl_)
    {
        _masterWallet = masterWallet_;
        _priceFeedManager = priceFeedManager_;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Checks if given address is registered as a strategy
     */
    function isStrategy(address strategy) external view returns (bool) {
        return _strategies[strategy];
    }

    /**
     * @notice Deposits for given strategy and DHW index
     */
    function depositedAssets(address strategy, uint256 index) external view returns (uint256[] memory) {
        uint256 assetGroupLength = IStrategy(strategy).assets().length;
        return _assetsDeposited[strategy][index].toArray(assetGroupLength);
    }

    /**
     * @notice Deposits for given strategy and DHW index
     */
    function currentIndex(address strategy) external view returns (uint256) {
        return _currentIndexes[strategy];
    }

    function assetRatioAtLastDhw(address strategy) external view returns (uint256[] memory) {
        return _dhwAssetRatios[strategy].toArray(IStrategy(strategy).assets().length);
    }

    /**
     * @notice Get state of a strategy for a given DHW index
     */
    function strategyAtIndex(address strategy, uint256 dhwIndex) external view returns (StrategyAtIndex memory) {
        uint256 assetGroupLength = IStrategy(strategy).assets().length;

        return StrategyAtIndex({
            exchangeRates: _exchangeRates[strategy][dhwIndex].toArray(assetGroupLength),
            assetsDeposited: _assetsDeposited[strategy][dhwIndex].toArray(assetGroupLength),
            sharesMinted: _sharesMinted[strategy][dhwIndex]
        });
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Add strategy to registry
     */
    function registerStrategy(address strategy) external {
        if (_strategies[strategy]) revert StrategyAlreadyRegistered({address_: strategy});

        _strategies[strategy] = true;
        _currentIndexes[strategy] = 1;
        _dhwAssetRatios[strategy].setValues(IStrategy(strategy).assetRatio());
    }

    /**
     * @notice Remove strategy from registry
     */
    function removeStrategy(address strategy) external {
        if (!_strategies[strategy]) revert InvalidStrategy({address_: strategy});
        _strategies[strategy] = false;
    }

    /**
     * @notice TODO: just a quick mockup so we can test withdrawals
     */
    function doHardWork(address[] memory strategies_, SwapInfo[][] calldata swapInfo) external {
        address[] memory assetGroup = IStrategy(strategies_[0]).assets();
        uint256[] memory exchangeRates = SpoolUtils.getExchangeRates(assetGroup, _priceFeedManager);

        for (uint256 i = 0; i < strategies_.length; i++) {
            IStrategy strategy = IStrategy(strategies_[i]);
            uint256 dhwIndex = _currentIndexes[address(strategy)];

            // transfer deposited assets to strategy
            for (uint256 j = 0; j < assetGroup.length; j++) {
                _masterWallet.transfer(
                    IERC20(assetGroup[j]), address(strategy), _assetsDeposited[address(strategy)][dhwIndex][j]
                );
            }

            // call strategy to do hard work
            DhwInfo memory dhwInfo = strategy.doHardWork(
                swapInfo[i],
                _sharesRedeemed[address(strategy)][dhwIndex],
                address(_masterWallet),
                exchangeRates,
                _priceFeedManager
            );

            _dhwAssetRatios[address(strategy)].setValues(strategy.assetRatio());
            _currentIndexes[address(strategy)]++;
            _exchangeRates[address(strategy)][dhwIndex].setValues(exchangeRates);
            _sharesMinted[address(strategy)][dhwIndex] = dhwInfo.sharesMinted;
            _assetsWithdrawn[address(strategy)][dhwIndex].setValues(dhwInfo.assetsWithdrawn);
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
                _assetsDeposited[strategy][latestIndex][j] += amounts[i][j];
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
            _sharesRedeemed[strategy][latestIndex] += strategyShares[i];
        }

        return indexes;
    }

    function redeemFast(address[] memory strategies_, uint256[] memory strategyShares, address[] memory assetGroup)
        external
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
                    _assetsWithdrawn[strategy][dhwIndex][j] * strategyShares[i] / _sharesRedeemed[strategy][dhwIndex];
                // there will be dust left after all vaults sync
            }
        }

        return totalWithdrawnAssets;
    }
}
