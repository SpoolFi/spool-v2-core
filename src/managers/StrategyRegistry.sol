// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/utils/math/SafeCast.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyNonAtomic.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/ISwapper.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/CommonErrors.sol";
import "../interfaces/Constants.sol";
import "../access/SpoolAccessControllable.sol";
import "../libraries/ArrayMapping.sol";
import "../libraries/SpoolUtils.sol";
import "../libraries/StrategyRegistryLib.sol";

/**
 * @notice Used when strategy apy is out of bounds.
 */
error BadStrategyApy(int256);

/**
 * @notice Used when doHardWord is run after its expiry time
 */
error DoHardWorkParametersExpired();

/**
 * @dev Requires roles:
 * - ROLE_MASTER_WALLET_MANAGER
 * - ADMIN_ROLE_STRATEGY
 * - ROLE_STRATEGY_REGISTRY
 */
contract StrategyRegistry is IStrategyRegistry, IEmergencyWithdrawal, Initializable, SpoolAccessControllable {
    using ArrayMappingUint256 for mapping(uint256 => uint256);
    using uint16a16Lib for uint16a16;

    /* ========== STATE VARIABLES ========== */

    /// @notice Wallet holding funds pending DHW
    IMasterWallet immutable _masterWallet;

    /// @notice Price feed manager
    IUsdPriceFeedManager immutable _priceFeedManager;

    address private immutable _ghostStrategy;

    PlatformFees internal _platformFees;

    /// @notice Address to transfer withdrawn assets to in case of an emergency withdrawal.
    address public override emergencyWithdrawalWallet;

    /// @notice Removed strategies
    mapping(address => bool) private _removedStrategies;

    /**
     * @custom:member sharesMinted Amount of SSTs minted for deposits.
     * @custom:member totalStrategyValue Strategy value at the DHW index.
     * @custom:member totalSSTs Total strategy shares at the DHW index.
     * @custom:member yield Amount of yield generated for a strategy since the previous DHW.
     * @custom:member timestamp Timestamp at which DHW was executed at.
     */
    struct StateAtDhwIndex {
        uint128 sharesMinted;
        uint128 totalStrategyValue;
        uint128 totalSSTs;
        int96 yield;
        uint32 timestamp;
    }

    /**
     * @notice State at DHW for strategies.
     * @dev strategy => DHW index => state at DHW
     */
    mapping(address => mapping(uint256 => StateAtDhwIndex)) internal _stateAtDhw;

    /**
     * @notice Current DHW index for strategies
     */
    mapping(address => uint256) internal _currentIndexes;

    /**
     * @notice Strategy asset ratios at last DHW.
     * @dev strategy => assetIndex => asset ratio weight
     */
    mapping(address => uint256[]) internal _dhwAssetRatios;

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
     * @notice Amount of SSTs redeemed from strategy.
     * @dev strategy => index => SSTs redeemed
     */
    mapping(address => mapping(uint256 => uint256)) internal _sharesRedeemed;

    /**
     * @notice Amount of assets withdrawn from protocol.
     * @dev strategy => index => asset index => amount withdrawn
     */
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _assetsWithdrawn;

    /**
     * @notice Amounts of assets withdrawn from protocol and not claimed yet.
     * @dev strategy => asset index => amount not claimed
     */
    mapping(address => mapping(uint256 => uint256)) internal _assetsNotClaimed;

    /**
     * @notice Running average APY.
     * @dev strategy => apy
     */
    mapping(address => int256) internal _apys;

    /**
     * @notice Atomicity classification for strategies.
     * @dev strategy => classification
     */
    mapping(address => uint256) internal _atomicityClassification;

    /**
     * @notice States of the strategies.
     * @dev strategy => state
     */
    mapping(address => uint256) internal _strategyStates;

    /**
     * @notice User shares withdrawn from the strategy.
     * @dev user => strategy => index => shares withdrawn
     */
    mapping(address => mapping(address => mapping(uint256 => uint256))) internal _userSharesWithdrawn;

    constructor(
        IMasterWallet masterWallet_,
        ISpoolAccessControl accessControl_,
        IUsdPriceFeedManager priceFeedManager_,
        address ghostStrategy_
    ) SpoolAccessControllable(accessControl_) {
        if (address(masterWallet_) == address(0)) revert ConfigurationAddressZero();
        if (address(priceFeedManager_) == address(0)) revert ConfigurationAddressZero();
        if (ghostStrategy_ == address(0)) revert ConfigurationAddressZero();

        _masterWallet = masterWallet_;
        _priceFeedManager = priceFeedManager_;
        _ghostStrategy = ghostStrategy_;
    }

    function initialize(
        uint96 ecosystemFeePct_,
        uint96 treasuryFeePct_,
        address ecosystemFeeReceiver_,
        address treasuryFeeReceiver_,
        address emergencyWithdrawalWallet_
    ) external initializer {
        _setEcosystemFee(ecosystemFeePct_);
        _setTreasuryFee(treasuryFeePct_);
        _setEcosystemFeeReceiver(ecosystemFeeReceiver_);
        _setTreasuryFeeReceiver(treasuryFeeReceiver_);
        _setEmergencyWithdrawalWallet(emergencyWithdrawalWallet_);
    }

    /* ========== VIEW FUNCTIONS ========== */

    function platformFees() external view returns (PlatformFees memory) {
        return _platformFees;
    }

    function depositedAssets(address strategy, uint256 index) external view returns (uint256[] memory) {
        uint256 assetGroupLength = IStrategy(strategy).assets().length;
        return _assetsDeposited[strategy][index].toArray(assetGroupLength);
    }

    function sharesRedeemed(address strategy, uint256 index) external view returns (uint256) {
        return _sharesRedeemed[strategy][index];
    }

    function currentIndex(address[] calldata strategies) external view returns (uint256[] memory) {
        uint256[] memory indexes = new uint256[](strategies.length);
        for (uint256 i; i < strategies.length; ++i) {
            indexes[i] = _currentIndexes[strategies[i]];
        }

        return indexes;
    }

    function strategyAPYs(address[] calldata strategies) external view returns (int256[] memory) {
        int256[] memory apys = new int256[](strategies.length);
        for (uint256 i; i < strategies.length; ++i) {
            apys[i] = _apys[strategies[i]];
        }

        return apys;
    }

    function assetRatioAtLastDhw(address strategy) external view returns (uint256[] memory) {
        return _dhwAssetRatios[strategy];
    }

    function dhwTimestamps(address[] calldata strategies, uint16a16 dhwIndexes)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory result = new uint256[](strategies.length);
        for (uint256 i; i < strategies.length; ++i) {
            result[i] = _stateAtDhw[strategies[i]][dhwIndexes.get(i)].timestamp;
        }

        return result;
    }

    function getDhwYield(address[] calldata strategies, uint16a16 dhwIndexes) external view returns (int256[] memory) {
        int256[] memory yields = new int256[](strategies.length);
        for (uint256 i; i < strategies.length; ++i) {
            yields[i] = _stateAtDhw[strategies[i]][dhwIndexes.get(i)].yield;
        }

        return yields;
    }

    function strategyAtIndexBatch(address[] calldata strategies, uint16a16 dhwIndexes, uint256 assetGroupLength)
        external
        view
        returns (StrategyAtIndex[] memory)
    {
        StrategyAtIndex[] memory result = new StrategyAtIndex[](strategies.length);

        for (uint256 i; i < strategies.length; ++i) {
            StateAtDhwIndex memory state = _stateAtDhw[strategies[i]][dhwIndexes.get(i)];

            result[i] = StrategyAtIndex({
                exchangeRates: _exchangeRates[strategies[i]][dhwIndexes.get(i)].toArray(assetGroupLength),
                assetsDeposited: _assetsDeposited[strategies[i]][dhwIndexes.get(i)].toArray(assetGroupLength),
                sharesMinted: state.sharesMinted,
                totalStrategyValue: state.totalStrategyValue,
                totalSSTs: state.totalSSTs,
                dhwYields: state.yield
            });
        }

        return result;
    }

    function atomicityClassifications(address[] calldata strategies) external view returns (uint256[] memory) {
        uint256[] memory classifications = new uint256[](strategies.length);
        for (uint256 i; i < strategies.length; ++i) {
            classifications[i] = _atomicityClassification[strategies[i]];
        }

        return classifications;
    }

    function strategyStates(address[] calldata strategies) external view returns (uint256[] memory) {
        uint256[] memory states = new uint256[](strategies.length);
        for (uint256 i; i < strategies.length; ++i) {
            states[i] = _strategyStates[strategies[i]];
        }

        return states;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Add strategy to registry
     */
    function registerStrategy(address strategy, int256 apy, uint256 atomicityClassification) external {
        _checkRole(ROLE_SPOOL_ADMIN, msg.sender);

        if (_removedStrategies[strategy]) revert StrategyPreviouslyRemoved(strategy);
        if (_accessControl.hasRole(ROLE_STRATEGY, strategy)) revert StrategyAlreadyRegistered({address_: strategy});

        _accessControl.grantRole(ROLE_STRATEGY, strategy);
        _currentIndexes[strategy] = 1;
        _dhwAssetRatios[strategy] = IStrategy(strategy).assetRatio();
        _stateAtDhw[address(strategy)][0].timestamp = SafeCast.toUint32(block.timestamp);

        emit StrategyRegistered(strategy, atomicityClassification);
        _setStrategyApy(strategy, apy);
        if (atomicityClassification > ATOMIC_STRATEGY) {
            _atomicityClassification[strategy] = atomicityClassification;
        }
    }

    /**
     * @notice Remove strategy from registry
     */
    function removeStrategy(address strategy) external onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender) {
        StrategyRegistryLib.removeStrategy(
            strategy,
            _accessControl,
            _masterWallet,
            emergencyWithdrawalWallet,
            _currentIndexes,
            _assetsDeposited,
            _removedStrategies,
            _assetsNotClaimed
        );
    }

    function doHardWork(DoHardWorkParameterBag calldata dhwParams) external whenNotPaused nonReentrant {
        unchecked {
            // Check if is run after the expiry time.
            if (dhwParams.validUntil < block.timestamp) revert DoHardWorkParametersExpired();

            // Can only be run by do-hard-worker.
            if (!_isViewExecution()) {
                _checkRole(ROLE_DO_HARD_WORKER, msg.sender);
            }

            if (
                dhwParams.tokens.length != dhwParams.exchangeRateSlippages.length
                    || dhwParams.strategies.length != dhwParams.swapInfo.length
                    || dhwParams.strategies.length != dhwParams.compoundSwapInfo.length
                    || dhwParams.strategies.length != dhwParams.strategySlippages.length
                    || dhwParams.strategies.length != dhwParams.baseYields.length
            ) {
                revert InvalidArrayLength();
            }

            // Get exchange rates for tokens and validate them against slippages.
            uint256[] memory exchangeRates = SpoolUtils.getExchangeRates(dhwParams.tokens, _priceFeedManager);
            for (uint256 i; i < dhwParams.tokens.length; ++i) {
                if (
                    exchangeRates[i] < dhwParams.exchangeRateSlippages[i][0]
                        || exchangeRates[i] > dhwParams.exchangeRateSlippages[i][1]
                ) {
                    revert ExchangeRateOutOfSlippages();
                }
            }

            PlatformFees memory platformFeesMemory = _platformFees;

            // Process each group of strategies in turn.
            for (uint256 i; i < dhwParams.strategies.length; ++i) {
                if (
                    dhwParams.strategies[i].length != dhwParams.swapInfo[i].length
                        || dhwParams.strategies[i].length != dhwParams.compoundSwapInfo[i].length
                        || dhwParams.strategies[i].length != dhwParams.strategySlippages[i].length
                        || dhwParams.strategies[i].length != dhwParams.baseYields[i].length
                ) {
                    revert InvalidArrayLength();
                }

                // Get exchange rates for this group of strategies.
                uint256 assetGroupId = IStrategy(dhwParams.strategies[i][0]).assetGroupId();
                address[] memory assetGroup = IStrategy(dhwParams.strategies[i][0]).assets();
                uint256[] memory assetGroupExchangeRates = new uint256[](assetGroup.length);

                for (uint256 j; j < assetGroup.length; ++j) {
                    bool found = false;

                    for (uint256 k; k < dhwParams.tokens.length; ++k) {
                        if (assetGroup[j] == dhwParams.tokens[k]) {
                            assetGroupExchangeRates[j] = exchangeRates[k];

                            found = true;
                            break;
                        }
                    }

                    if (!found) {
                        revert InvalidTokenList();
                    }
                }

                // Process each strategy in this group.
                uint256 numStrategies = dhwParams.strategies[i].length;
                for (uint256 j; j < numStrategies; ++j) {
                    address strategy = dhwParams.strategies[i][j];

                    if (strategy == _ghostStrategy) {
                        revert GhostStrategyUsed();
                    }

                    _checkRole(ROLE_STRATEGY, strategy);

                    if (IStrategy(strategy).assetGroupId() != assetGroupId) {
                        revert NotSameAssetGroup();
                    }

                    if (_strategyStates[strategy] == DHW_IN_PROGRESS) {
                        revert StrategyDhwInProgress(strategy);
                    }

                    uint256 dhwIndex = _currentIndexes[strategy];

                    // Transfer deposited assets to the strategy.
                    for (uint256 k; k < assetGroup.length; ++k) {
                        uint256 assetsDepositedK = _assetsDeposited[strategy][dhwIndex][k];
                        if (assetsDepositedK > 0) {
                            _masterWallet.transfer(IERC20(assetGroup[k]), strategy, assetsDepositedK);
                        }
                    }

                    // Do the hard work on the strategy.
                    DhwInfo memory dhwInfo = IStrategy(strategy).doHardWork(
                        StrategyDhwParameterBag({
                            swapInfo: dhwParams.swapInfo[i][j],
                            compoundSwapInfo: dhwParams.compoundSwapInfo[i][j],
                            slippages: dhwParams.strategySlippages[i][j],
                            assetGroup: assetGroup,
                            exchangeRates: assetGroupExchangeRates,
                            withdrawnShares: _sharesRedeemed[strategy][dhwIndex],
                            masterWallet: address(_masterWallet),
                            priceFeedManager: _priceFeedManager,
                            baseYield: dhwParams.baseYields[i][j],
                            platformFees: platformFeesMemory
                        })
                    );

                    // Bookkeeping.
                    _dhwAssetRatios[strategy] = IStrategy(strategy).assetRatio();
                    for (uint256 k; k < assetGroup.length; ++k) {
                        _assetsWithdrawn[strategy][dhwIndex][k] = dhwInfo.assetsWithdrawn[k];
                        _assetsNotClaimed[strategy][k] += dhwInfo.assetsWithdrawn[k];
                    }

                    // update index even if DHW needs continuation, so that flushes can be done
                    ++_currentIndexes[strategy];

                    if (dhwInfo.continuationNeeded) {
                        _strategyStates[strategy] = DHW_IN_PROGRESS;
                    } else {
                        int256 yield = int256(_stateAtDhw[strategy][dhwIndex - 1].yield);
                        yield += dhwInfo.yieldPercentage + yield * dhwInfo.yieldPercentage / YIELD_FULL_PERCENT_INT;

                        _stateAtDhw[strategy][dhwIndex] = StateAtDhwIndex({
                            sharesMinted: SafeCast.toUint128(dhwInfo.sharesMinted), // shares should not exceed uint128
                            totalStrategyValue: SafeCast.toUint128(dhwInfo.valueAtDhw), // measured in USD
                            totalSSTs: SafeCast.toUint128(dhwInfo.totalSstsAtDhw), // shares should not exceed uint128
                            yield: SafeCast.toInt96(yield), // accumulate the yield from before
                            timestamp: SafeCast.toUint32(block.timestamp)
                        });

                        _exchangeRates[strategy][dhwIndex].setValues(assetGroupExchangeRates);

                        _updateApy(strategy, dhwIndex, dhwInfo.yieldPercentage);

                        emit StrategyDhw(strategy, dhwIndex, dhwInfo);
                    }
                }
            }
        }
    }

    function doHardWorkContinue(DoHardWorkContinuationParameterBag calldata dhwContParams)
        external
        whenNotPaused
        nonReentrant
    {
        unchecked {
            // Check if is run after the expiry time.
            if (dhwContParams.validUntil < block.timestamp) revert DoHardWorkParametersExpired();

            // Can only be run by do-hard-worker.
            if (!_isViewExecution()) {
                _checkRole(ROLE_DO_HARD_WORKER, msg.sender);
            }

            if (
                dhwContParams.tokens.length != dhwContParams.exchangeRateSlippages.length
                    || dhwContParams.strategies.length != dhwContParams.baseYields.length
                    || dhwContParams.strategies.length != dhwContParams.continuationData.length
            ) {
                revert InvalidArrayLength();
            }

            // Get exchange rates for tokens and validate them against slippages.
            uint256[] memory exchangeRates = SpoolUtils.getExchangeRates(dhwContParams.tokens, _priceFeedManager);
            for (uint256 i; i < dhwContParams.tokens.length; ++i) {
                if (
                    exchangeRates[i] < dhwContParams.exchangeRateSlippages[i][0]
                        || exchangeRates[i] > dhwContParams.exchangeRateSlippages[i][1]
                ) {
                    revert ExchangeRateOutOfSlippages();
                }
            }

            PlatformFees memory platformFeesMemory = _platformFees;

            // Process each group of strategies in turn.
            for (uint256 i; i < dhwContParams.strategies.length; ++i) {
                if (
                    dhwContParams.strategies[i].length != dhwContParams.baseYields[i].length
                        || dhwContParams.strategies[i].length != dhwContParams.continuationData[i].length
                ) {
                    revert InvalidArrayLength();
                }

                // Get exchange rates for this group of strategies.
                uint256 assetGroupId = IStrategy(dhwContParams.strategies[i][0]).assetGroupId();
                address[] memory assetGroup = IStrategy(dhwContParams.strategies[i][0]).assets();
                uint256[] memory assetGroupExchangeRates = new uint256[](assetGroup.length);

                for (uint256 j; j < assetGroup.length; ++j) {
                    bool found = false;

                    for (uint256 k; k < dhwContParams.tokens.length; ++k) {
                        if (assetGroup[j] == dhwContParams.tokens[k]) {
                            assetGroupExchangeRates[j] = exchangeRates[k];

                            found = true;
                            break;
                        }
                    }

                    if (!found) {
                        revert InvalidTokenList();
                    }
                }

                // Process each strategy in this group.
                uint256 numStrategies = dhwContParams.strategies[i].length;
                for (uint256 j; j < numStrategies; ++j) {
                    address strategy = dhwContParams.strategies[i][j];

                    if (strategy == _ghostStrategy) {
                        revert GhostStrategyUsed();
                    }

                    _checkRole(ROLE_STRATEGY, strategy);

                    if (IStrategy(strategy).assetGroupId() != assetGroupId) {
                        revert NotSameAssetGroup();
                    }

                    if (_strategyStates[strategy] != DHW_IN_PROGRESS) {
                        revert StrategyDhwFinished(strategy);
                    }

                    // DHW index is incremented on DHW even if continuation is needed.
                    uint256 dhwIndex = _currentIndexes[strategy] - 1;

                    // Continue the hard work on the strategy.
                    DhwInfo memory dhwContInfo = IStrategyNonAtomic(strategy).doHardWorkContinue(
                        StrategyDhwContinuationParameterBag({
                            assetGroup: assetGroup,
                            exchangeRates: assetGroupExchangeRates,
                            masterWallet: address(_masterWallet),
                            priceFeedManager: _priceFeedManager,
                            baseYield: dhwContParams.baseYields[i][j],
                            platformFees: platformFeesMemory,
                            continuationData: dhwContParams.continuationData[i][j]
                        })
                    );

                    // Bookkeeping.
                    _dhwAssetRatios[strategy] = IStrategy(strategy).assetRatio();
                    for (uint256 k; k < assetGroup.length; ++k) {
                        _assetsWithdrawn[strategy][dhwIndex][k] += dhwContInfo.assetsWithdrawn[k];
                        _assetsNotClaimed[strategy][k] += dhwContInfo.assetsWithdrawn[k];
                    }

                    if (!dhwContInfo.continuationNeeded) {
                        _strategyStates[strategy] = STRATEGY_IDLE;

                        int256 yield = int256(_stateAtDhw[strategy][dhwIndex - 1].yield);
                        yield +=
                            dhwContInfo.yieldPercentage + yield * dhwContInfo.yieldPercentage / YIELD_FULL_PERCENT_INT;

                        _stateAtDhw[strategy][dhwIndex] = StateAtDhwIndex({
                            sharesMinted: SafeCast.toUint128(dhwContInfo.sharesMinted), // shares should not exceed uint128
                            totalStrategyValue: SafeCast.toUint128(dhwContInfo.valueAtDhw), // measured in USD
                            totalSSTs: SafeCast.toUint128(dhwContInfo.totalSstsAtDhw), // shares should not exceed uint128
                            yield: SafeCast.toInt96(yield), // accumulate the yield from before
                            timestamp: SafeCast.toUint32(block.timestamp)
                        });

                        _exchangeRates[strategy][dhwIndex].setValues(assetGroupExchangeRates);

                        _updateApy(strategy, dhwIndex, dhwContInfo.yieldPercentage);

                        emit StrategyDhw(strategy, dhwIndex, dhwContInfo);
                    }
                }
            }
        }
    }

    function addDeposits(address[] calldata strategies_, uint256[][] calldata amounts)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint16a16)
    {
        uint16a16 indexes;
        for (uint256 i; i < strategies_.length; ++i) {
            address strategy = strategies_[i];

            uint256 latestIndex = _currentIndexes[strategy];
            indexes = indexes.set(i, latestIndex);

            for (uint256 j = 0; j < amounts[i].length; ++j) {
                _assetsDeposited[strategy][latestIndex][j] += amounts[i][j];
            }
        }

        return indexes;
    }

    function addWithdrawals(address[] calldata strategies_, uint256[] calldata strategyShares)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint16a16)
    {
        uint16a16 indexes;

        for (uint256 i; i < strategies_.length; ++i) {
            address strategy = strategies_[i];
            uint256 latestIndex = _currentIndexes[strategy];

            indexes = indexes.set(i, latestIndex);
            _sharesRedeemed[strategy][latestIndex] += strategyShares[i];
        }

        return indexes;
    }

    function redeemFast(RedeemFastParameterBag calldata redeemFastParams)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint256[] memory)
    {
        return StrategyRegistryLib.redeemFast(redeemFastParams, _ghostStrategy, _masterWallet, _strategyStates);
    }

    function claimWithdrawals(address[] calldata strategies_, uint16a16 dhwIndexes, uint256[] calldata strategyShares)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint256[] memory)
    {
        address[] memory assetGroup;
        uint256[] memory totalWithdrawnAssets;

        for (uint256 i; i < strategies_.length; ++i) {
            address strategy = strategies_[i];

            if (strategies_[i] == _ghostStrategy) {
                continue;
            }

            if (assetGroup.length == 0) {
                assetGroup = IStrategy(strategy).assets();
                totalWithdrawnAssets = new uint256[](assetGroup.length);
            }

            if (strategyShares[i] == 0) {
                continue;
            }

            uint256 dhwIndex = dhwIndexes.get(i);

            if (dhwIndex == _currentIndexes[strategy]) {
                revert DhwNotRunYetForIndex(strategy, dhwIndex);
            }

            for (uint256 j = 0; j < totalWithdrawnAssets.length; ++j) {
                uint256 withdrawnAssets =
                    _assetsWithdrawn[strategy][dhwIndex][j] * strategyShares[i] / _sharesRedeemed[strategy][dhwIndex];
                totalWithdrawnAssets[j] += withdrawnAssets;
                _assetsNotClaimed[strategy][j] -= withdrawnAssets;
                // there will be dust left after all vaults sync
            }
        }

        return totalWithdrawnAssets;
    }

    function emergencyWithdraw(
        address[] calldata strategies,
        uint256[][] calldata withdrawalSlippages,
        bool removeStrategies
    ) external {
        StrategyRegistryLib.emergencyWithdraw(
            strategies,
            withdrawalSlippages,
            EmergencyWithdrawParams({
                removeStrategies: removeStrategies,
                accessControl: _accessControl,
                ghostStrategy: _ghostStrategy,
                emergencyWithdrawalWallet: emergencyWithdrawalWallet,
                masterWallet: _masterWallet
            }),
            _currentIndexes,
            _assetsDeposited,
            _removedStrategies,
            _assetsNotClaimed
        );
    }

    function redeemStrategyShares(
        address[] calldata strategies,
        uint256[] calldata shares,
        uint256[][] calldata withdrawalSlippages
    ) external checkNonReentrant {
        StrategyRegistryLib.redeemStrategyShares(
            strategies, shares, withdrawalSlippages, msg.sender, _accessControl, _ghostStrategy, _strategyStates
        );
    }

    function redeemStrategySharesView(
        address[] calldata strategies,
        uint256[] calldata shares,
        uint256[][] calldata withdrawalSlippages,
        address redeemer
    ) external {
        if (!_isViewExecution()) {
            revert OnlyViewExecution(tx.origin);
        }
        StrategyRegistryLib.redeemStrategyShares(
            strategies, shares, withdrawalSlippages, redeemer, _accessControl, _ghostStrategy, _strategyStates
        );
    }

    function redeemStrategySharesAsync(address[] calldata strategies, uint256[] calldata shares)
        external
        checkNonReentrant
    {
        StrategyRegistryLib.redeemStrategySharesAsync(
            strategies, shares, _ghostStrategy, _accessControl, _currentIndexes, _sharesRedeemed, _userSharesWithdrawn
        );
    }

    function claimStrategyShareWithdrawals(
        address[] calldata strategies,
        uint256[] calldata strategyIndexes,
        address recipient
    ) external checkNonReentrant {
        StrategyRegistryLib.claimStrategyShareWithdrawals(
            strategies,
            strategyIndexes,
            ClaimStrategyShareWithdrawalsParams({
                recipient: recipient,
                accessControl: _accessControl,
                ghostStrategy: _ghostStrategy,
                masterWallet: _masterWallet
            }),
            _userSharesWithdrawn,
            _assetsWithdrawn,
            _sharesRedeemed,
            _assetsNotClaimed
        );
    }

    function setStrategyApy(address strategy, int256 apy) external onlyRole(ROLE_STRATEGY_APY_SETTER, msg.sender) {
        _checkRole(ROLE_STRATEGY, strategy);
        _setStrategyApy(strategy, apy);
    }

    function setEcosystemFee(uint96 ecosystemFeePct_) external onlyRole(ROLE_SPOOL_ADMIN, msg.sender) {
        _setEcosystemFee(ecosystemFeePct_);
    }

    function setEcosystemFeeReceiver(address ecosystemFeePct_) external onlyRole(ROLE_SPOOL_ADMIN, msg.sender) {
        _setEcosystemFeeReceiver(ecosystemFeePct_);
    }

    function setTreasuryFee(uint96 treasuryFeePct_) external onlyRole(ROLE_SPOOL_ADMIN, msg.sender) {
        _setTreasuryFee(treasuryFeePct_);
    }

    function setTreasuryFeeReceiver(address treasuryFeeReceiver_) external onlyRole(ROLE_SPOOL_ADMIN, msg.sender) {
        _setTreasuryFeeReceiver(treasuryFeeReceiver_);
    }

    function setEmergencyWithdrawalWallet(address emergencyWithdrawalWallet_)
        external
        onlyRole(ROLE_SPOOL_ADMIN, msg.sender)
    {
        _setEmergencyWithdrawalWallet(emergencyWithdrawalWallet_);
    }

    function _setStrategyApy(address strategy, int256 apy) private {
        if (apy < -YIELD_FULL_PERCENT_INT) revert BadStrategyApy(apy);

        _apys[strategy] = apy;
        emit StrategyApyUpdated(strategy, apy);
    }

    function _setEcosystemFee(uint96 ecosystemFeePct_) private {
        if (ecosystemFeePct_ > ECOSYSTEM_FEE_MAX) {
            revert EcosystemFeeTooLarge(ecosystemFeePct_);
        }

        _platformFees.ecosystemFeePct = ecosystemFeePct_;
        emit EcosystemFeeSet(ecosystemFeePct_);
    }

    function _setEcosystemFeeReceiver(address ecosystemFeeReceiver_) private {
        if (ecosystemFeeReceiver_ == address(0)) {
            revert ConfigurationAddressZero();
        }

        _platformFees.ecosystemFeeReceiver = ecosystemFeeReceiver_;
        emit EcosystemFeeReceiverSet(ecosystemFeeReceiver_);
    }

    function _setTreasuryFee(uint96 treasuryFeePct_) private {
        if (treasuryFeePct_ > TREASURY_FEE_MAX) {
            revert TreasuryFeeTooLarge(treasuryFeePct_);
        }

        _platformFees.treasuryFeePct = treasuryFeePct_;
        emit TreasuryFeeSet(treasuryFeePct_);
    }

    function _setTreasuryFeeReceiver(address treasuryFeeReceiver_) private {
        if (treasuryFeeReceiver_ == address(0)) {
            revert ConfigurationAddressZero();
        }

        _platformFees.treasuryFeeReceiver = treasuryFeeReceiver_;
        emit TreasuryFeeReceiverSet(treasuryFeeReceiver_);
    }

    function _setEmergencyWithdrawalWallet(address emergencyWithdrawalWallet_) private {
        if (emergencyWithdrawalWallet_ == address(0)) {
            revert ConfigurationAddressZero();
        }

        emergencyWithdrawalWallet = emergencyWithdrawalWallet_;
        emit EmergencyWithdrawalWalletSet(emergencyWithdrawalWallet_);
    }

    function _updateApy(address strategy, uint256 dhwIndex, int256 yieldPercentage) internal {
        if (dhwIndex > 1) {
            unchecked {
                int256 timeDelta =
                    SafeCast.toInt256(block.timestamp - _stateAtDhw[address(strategy)][dhwIndex - 1].timestamp);

                if (timeDelta > 0) {
                    int256 normalizedApy = yieldPercentage * SECONDS_IN_YEAR_INT / timeDelta;
                    int256 weight = _getRunningAverageApyWeight(timeDelta);
                    int256 apy =
                        (_apys[strategy] * (FULL_PERCENT_INT - weight) + normalizedApy * weight) / FULL_PERCENT_INT;

                    _setStrategyApy(strategy, apy);
                }
            }
        }
    }

    function _getRunningAverageApyWeight(int256 timeDelta) internal pure returns (int256) {
        if (timeDelta < 1 days) {
            if (timeDelta < 4 hours) {
                return 4_15;
            } else if (timeDelta < 12 hours) {
                return 12_44;
            } else {
                return 24_49;
            }
        } else {
            if (timeDelta < 1.5 days) {
                return 35_84;
            } else if (timeDelta < 2 days) {
                return 46_21;
            } else if (timeDelta < 3 days) {
                return 63_51;
            } else if (timeDelta < 4 days) {
                return 76_16;
            } else if (timeDelta < 5 days) {
                return 84_83;
            } else if (timeDelta < 6 days) {
                return 90_51;
            } else if (timeDelta < 1 weeks) {
                return 94_14;
            } else {
                return FULL_PERCENT_INT;
            }
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _isViewExecution() private view returns (bool) {
        return tx.origin == address(0);
    }
}
