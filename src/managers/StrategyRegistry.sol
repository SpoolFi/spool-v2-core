// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/ISwapper.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/CommonErrors.sol";
import "../access/SpoolAccessControllable.sol";
import "../interfaces/Constants.sol";
import "../libraries/ArrayMapping.sol";
import "../libraries/SpoolUtils.sol";

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

    /**
     * @notice Strategy value at the DHW index.
     * @dev strategy => index => DHW value
     */
    mapping(address => mapping(uint256 => uint256)) internal _dhwValue;

    /**
     * @notice Total strategy shares at the DHW index.
     * @dev strategy => index => total shares
     */
    mapping(address => mapping(uint256 => uint256)) internal _dhwSsts;

    /**
     * @notice Amount of yield generated for a strategy since the previous DHW.
     * @dev strategy => index => yield percentage
     */
    mapping(address => mapping(uint256 => int256)) internal _dhwYields;

    /**
     * @notice Running average APY.
     * @dev strategy => apy
     */
    mapping(address => int256) internal _apys;

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

    function initialize(
        uint96 ecosystemFeePct_,
        uint96 treasuryFeePct_,
        address ecosystemFeeReceiver_,
        address treasuryFeeReceiver_
    ) external initializer {
        _setEcosystemFee(ecosystemFeePct_);
        _setTreasuryFee(treasuryFeePct_);
        _setEcosystemFeeReceiver(ecosystemFeeReceiver_);
        _setTreasuryFeeReceiver(treasuryFeeReceiver_);
    }

    /* ========== VIEW FUNCTIONS ========== */

    function platformFees() external view returns (PlatformFees memory) {
        return _platformFees;
    }

    function depositedAssets(address strategy, uint256 index) external view returns (uint256[] memory) {
        uint256 assetGroupLength = IStrategy(strategy).assets().length;
        return _assetsDeposited[strategy][index].toArray(assetGroupLength);
    }

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

    function dhwTimestamps(address[] calldata strategies, uint16a16 dhwIndexes)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory result = new uint256[](strategies.length);
        for (uint256 i; i < strategies.length; i++) {
            result[i] = _dhwTimestamp[strategies[i]][dhwIndexes.get(i)];
        }

        return result;
    }

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

    function strategyAtIndex(address strategy, uint256 dhwIndex) public view returns (StrategyAtIndex memory) {
        uint256 assetGroupLength = IStrategy(strategy).assets().length;

        return StrategyAtIndex({
            exchangeRates: _exchangeRates[strategy][dhwIndex].toArray(assetGroupLength),
            assetsDeposited: _assetsDeposited[strategy][dhwIndex].toArray(assetGroupLength),
            sharesMinted: _sharesMinted[strategy][dhwIndex],
            totalStrategyValue: _dhwValue[strategy][dhwIndex],
            totalSSTs: _dhwSsts[strategy][dhwIndex],
            dhwYields: _dhwYields[strategy][dhwIndex]
        });
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Add strategy to registry
     */
    function registerStrategy(address strategy) external {
        _checkRole(ROLE_SPOOL_ADMIN, msg.sender);
        if (_accessControl.hasRole(ROLE_STRATEGY, strategy)) revert StrategyAlreadyRegistered({address_: strategy});

        _accessControl.grantRole(ROLE_STRATEGY, strategy);
        _currentIndexes[strategy] = 1;
        _dhwAssetRatios[strategy].setValues(IStrategy(strategy).assetRatio());
        _dhwTimestamp[address(strategy)][0] = block.timestamp;

        // should we manually set APY?
    }

    /**
     * @notice Remove strategy from registry
     */
    function removeStrategy(address strategy) external onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender) {
        _removeStrategy(strategy);
    }

    function doHardWork(DoHardWorkParameterBag calldata dhwParams) external whenNotPaused {
        unchecked {
            // Can only be run by do-hard-worker.
            _checkRole(ROLE_DO_HARD_WORKER, msg.sender);

            if (
                dhwParams.tokens.length != dhwParams.exchangeRateSlippages.length
                    || dhwParams.strategies.length != dhwParams.swapInfo.length
                    || dhwParams.strategies.length != dhwParams.compoundSwapInfo.length
                    || dhwParams.strategies.length != dhwParams.strategySlippages.length
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

            // Process each group of strategies in turn.
            for (uint256 i; i < dhwParams.strategies.length; ++i) {
                if (
                    dhwParams.strategies[i].length != dhwParams.swapInfo[i].length
                        || dhwParams.strategies[i].length != dhwParams.compoundSwapInfo[i].length
                        || dhwParams.strategies[i].length != dhwParams.strategySlippages[i].length
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

                    if (IStrategy(strategy).assetGroupId() != assetGroupId) {
                        revert NotSameAssetGroup();
                    }

                    uint256 dhwIndex = _currentIndexes[strategy];

                    // Transfer deposited assets to the strategy.
                    for (uint256 k; k < assetGroup.length; ++k) {
                        if (_assetsDeposited[strategy][dhwIndex][k] > 0) {
                            _masterWallet.transfer(
                                IERC20(assetGroup[k]), strategy, _assetsDeposited[strategy][dhwIndex][k]
                            );
                        }
                    }

                    // Do the hard work on the strategy.
                    DhwInfo memory dhwInfo = IStrategy(strategy).doHardWork(
                        StrategyDhwParameterBag({
                            swapInfo: dhwParams.swapInfo[i][j],
                            compoundSwapInfo: dhwParams.compoundSwapInfo[i][j],
                            slippages: dhwParams.strategySlippages[i][j],
                            assetGroup: assetGroup,
                            exchangeRates: exchangeRates,
                            withdrawnShares: _sharesRedeemed[strategy][dhwIndex],
                            masterWallet: address(_masterWallet),
                            priceFeedManager: _priceFeedManager
                        })
                    );

                    // Bookkeeping.
                    _dhwAssetRatios[strategy].setValues(IStrategy(strategy).assetRatio());
                    ++_currentIndexes[strategy];
                    _exchangeRates[strategy][dhwIndex].setValues(exchangeRates);
                    _sharesMinted[strategy][dhwIndex] = dhwInfo.sharesMinted;
                    _assetsWithdrawn[strategy][dhwIndex].setValues(dhwInfo.assetsWithdrawn);
                    _dhwTimestamp[strategy][dhwIndex] = block.timestamp;
                    _dhwYields[address(strategy)][dhwIndex] = dhwInfo.yieldPercentage;
                    _dhwValue[address(strategy)][dhwIndex] = dhwInfo.valueAtDhw;
                    _dhwSsts[address(strategy)][dhwIndex] = dhwInfo.totalSstsAtDhw;
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

    function addWithdrawals(address[] calldata strategies_, uint256[] calldata strategyShares)
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

    function redeemFast(RedeemFastParameterBag calldata redeemFastParams)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint256[] memory)
    {
        uint256[] memory withdrawnAssets = new uint256[](redeemFastParams.assetGroup.length);
        uint256[] memory exchangeRates = SpoolUtils.getExchangeRates(redeemFastParams.assetGroup, _priceFeedManager);

        unchecked {
            for (uint256 i; i < exchangeRates.length; ++i) {
                if (
                    exchangeRates[i] < redeemFastParams.exchangeRateSlippages[i][0]
                        || exchangeRates[i] > redeemFastParams.exchangeRateSlippages[i][1]
                ) {
                    revert ExchangeRateOutOfSlippages();
                }
            }
        }

        for (uint256 i = 0; i < redeemFastParams.strategies.length; i++) {
            uint256[] memory strategyWithdrawnAssets = IStrategy(redeemFastParams.strategies[i]).redeemFast(
                redeemFastParams.strategyShares[i],
                address(_masterWallet),
                redeemFastParams.assetGroup,
                exchangeRates,
                _priceFeedManager,
                redeemFastParams.withdrawalSlippages[i]
            );

            for (uint256 j = 0; j < strategyWithdrawnAssets.length; j++) {
                withdrawnAssets[j] += strategyWithdrawnAssets[j];
            }
        }

        return withdrawnAssets;
    }

    function claimWithdrawals(address[] calldata strategies_, uint16a16 dhwIndexes, uint256[] calldata strategyShares)
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

    function setEmergencyWithdrawalWallet(address address_) external onlyRole(ROLE_SPOOL_ADMIN, msg.sender) {
        if (address_ == address(0)) {
            revert ConfigurationAddressZero();
        }

        emergencyWithdrawalWallet = address_;
    }

    function emergencyWithdraw(
        address[] calldata strategies,
        address[] calldata assetGroup,
        uint256[][] calldata withdrawalSlippages,
        bool removeStrategies
    ) external onlyRole(ROLE_EMERGENCY_WITHDRAWAL_EXECUTOR, msg.sender) {
        if (emergencyWithdrawalWallet == address(0)) {
            revert ConfigurationAddressZero();
        }

        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i] == _ghostStrategy) {
                continue;
            }

            IStrategy(strategies[i]).emergencyWithdraw(assetGroup, withdrawalSlippages[i], emergencyWithdrawalWallet);

            emit StrategyEmergencyWithdrawn(strategies[i]);

            if (removeStrategies) {
                _removeStrategy(strategies[i]);
            }
        }
    }

    function _setEcosystemFee(uint96 ecosystemFeePct_) private {
        if (ecosystemFeePct_ > TREASURY_FEE_MAX) {
            revert EcosystemFeeTooLarge(ecosystemFeePct_);
        }

        _platformFees.ecosystemFeePct = ecosystemFeePct_;
    }

    function _setEcosystemFeeReceiver(address ecosystemFeeReceiver_) private {
        if (ecosystemFeeReceiver_ == address(0)) {
            revert ConfigurationAddressZero();
        }

        _platformFees.ecosystemFeeReceiver = ecosystemFeeReceiver_;
    }

    function _setTreasuryFee(uint96 treasuryFeePct_) private {
        if (treasuryFeePct_ > TREASURY_FEE_MAX) {
            revert TreasuryFeeTooLarge(treasuryFeePct_);
        }

        _platformFees.treasuryFeePct = treasuryFeePct_;
    }

    function _setTreasuryFeeReceiver(address treasuryFeeReceiver_) private {
        if (treasuryFeeReceiver_ == address(0)) {
            revert ConfigurationAddressZero();
        }

        _platformFees.treasuryFeeReceiver = treasuryFeeReceiver_;
    }

    function _updateDhwYieldAndApy(address strategy, uint256 dhwIndex, int256 yieldPercentage) internal {
        if (dhwIndex > 1) {
            unchecked {
                int256 timeDelta = int256(block.timestamp - _dhwTimestamp[address(strategy)][dhwIndex - 1]);
                if (timeDelta > 0) {
                    int256 normalizedApy = yieldPercentage * SECONDS_IN_YEAR_INT / timeDelta;
                    int256 weight = _getRunningAverageApyWeight(timeDelta);
                    // TODO: decide on the formula
                    _apys[strategy] =
                        (_apys[strategy] * (FULL_PERCENT_INT - weight) + normalizedApy * weight) / FULL_PERCENT_INT;
                }
            }
        }
    }

    function _getRunningAverageApyWeight(int256 timeDelta) internal pure returns (int256) {
        // NOTE: decide on the function. ?? sigmoid function "y=2*((1/(1+e^-(0.5*x)))-0.5)"

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

    function _removeStrategy(address strategy) private {
        if (!_accessControl.hasRole(ROLE_STRATEGY, strategy)) revert InvalidStrategy({address_: strategy});
        _accessControl.revokeRole(ROLE_STRATEGY, strategy);
    }
}
