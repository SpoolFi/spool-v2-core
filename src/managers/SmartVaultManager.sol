// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/ISmartVaultManager.sol";
import "../interfaces/IRiskManager.sol";
import "../interfaces/ISmartVault.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

contract SmartVaultRegistry is ISmartVaultRegistry {
    /// @notice TODO
    mapping(address => bool) internal _smartVaults;

    /**
     * @notice TODO
     */
    function isSmartVault(address address_) external view returns (bool) {
        return _smartVaults[address_];
    }

    /**
     * @notice TODO
     */
    function registerSmartVault(address smartVault) external {
        if (_smartVaults[smartVault]) revert SmartVaultAlreadyRegistered({address_: smartVault});
        _smartVaults[smartVault] = true;
    }

    /**
     * @notice TODO
     */
    function removeSmartVault(address smartVault) external validSmartVault(smartVault) {
        _smartVaults[smartVault] = false;
    }

    /* ========== MODIFIERS ========== */

    modifier validSmartVault(address address_) {
        if (!_smartVaults[address_]) revert InvalidSmartVault({address_: address_});
        _;
    }
}

contract SmartVaultManager is SmartVaultRegistry, ISmartVaultManager {
    /* ========== STATE VARIABLES ========== */

    uint256 constant RATIO_PRECISION = 10 ** 22;

    /// @notice TODO
    IStrategyRegistry private immutable _strategyRegistry;

    /// @notice TODO
    IRiskManager private immutable _riskManager;

    /// @notice TODO
    IUsdPriceFeedManager private immutable _priceFeedManager;

    /// @notice TODO
    mapping(address => address[]) internal _smartVaultStrategies;

    /// @notice TODO
    mapping(address => address) internal _smartVaultRiskProviders;

    /// @notice TODO
    mapping(address => uint256[]) internal _smartVaultAllocations;

    /// @notice TODO
    mapping(address => int256) internal _riskTolerances;

    /// @notice Current flush index for given Smart Vault
    mapping(address => uint256) internal _flushIndexes;

    /// @notice DHW indexes for given Smart Vault and flush index
    mapping(address => mapping(uint256 => uint256[])) internal _dhwIndexes;

    /// @notice TODO smartVault => flushIdx => depositAmounts
    mapping(address => mapping(uint256 => uint256[])) _vaultDeposits;

    constructor(
        IStrategyRegistry strategyRegistry_,
        IRiskManager riskManager_,
        IUsdPriceFeedManager priceFeedManager_
    ) {
        _strategyRegistry = strategyRegistry_;
        _riskManager = riskManager_;
        _priceFeedManager = priceFeedManager_;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice TODO
     */
    function strategies(address smartVault) external view returns (address[] memory) {
        return _smartVaultStrategies[smartVault];
    }

    /**
     * @notice TODO
     */
    function allocations(address smartVault) external view returns (uint256[] memory) {
        return _smartVaultAllocations[smartVault];
    }

    /**
     * @notice TODO
     */
    function riskProvider(address smartVault) external view returns (address) {
        return _smartVaultRiskProviders[smartVault];
    }

    /**
     * @notice TODO
     */
    function riskTolerance(address smartVault) external view returns (int256) {
        return _riskTolerances[smartVault];
    }

    function getLatestFlushIndex(address smartVault) external view returns (uint256) {
        return _flushIndexes[smartVault];
    }

    /**
     * @notice Smart vault deposits for given flush index.
     */
    function smartVaultDeposits(address smartVault, uint256 flushIdx) external returns (uint256[] memory) {
        return _vaultDeposits[smartVault][flushIdx];
    }

    /**
     * @notice DHW indexes that were active at given flush index
     */
    function dhwIndexes(address smartVault, uint256 flushIndex) external view returns (uint256[] memory) {
        return _dhwIndexes[smartVault][flushIndex];
    }

    /**
     * @notice Gets total value (in USD) of assets managed by the vault.
     */
    function getVaultTotalUsdValue(address smartVault) external view returns (uint256) {
        address[] memory strategyAddresses = _smartVaultStrategies[smartVault];

        uint256 totalUsdValue = 0;

        for (uint256 i = 0; i < strategyAddresses.length; i++) {
            IStrategy strategy = IStrategy(strategyAddresses[i]);
            totalUsdValue =
                totalUsdValue + strategy.totalUsdValue() * strategy.balanceOf(smartVault) / strategy.totalSupply();
        }

        return totalUsdValue;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice TODO
     */
    function setStrategies(address smartVault, address[] memory strategies_) external validSmartVault(smartVault) {
        if (strategies_.length == 0) revert EmptyStrategyArray();

        for (uint256 i = 0; i < strategies_.length; i++) {
            address strategy = strategies_[i];
            if (!_strategyRegistry.isStrategy(strategy)) revert InvalidStrategy({address_: strategy});
        }

        _smartVaultStrategies[smartVault] = strategies_;
    }

    /**
     * @notice TODO
     */
    function setAllocations(address smartVault, uint256[] memory allocations_) external validSmartVault(smartVault) {
        _smartVaultAllocations[smartVault] = allocations_;
    }

    /**
     * @notice TODO
     */
    function setRiskProvider(address smartVault, address riskProvider_) external validRiskProvider(riskProvider_) {
        _smartVaultRiskProviders[smartVault] = riskProvider_;
    }

    /**
     * @notice TODO
     */
    function syncSmartVault(address smartVault) external {}

    /**
     * @notice Accumulate Smart Vault deposits before pushing to strategies
     * @param smartVault Smart Vault address
     * @param amounts Deposit amounts
     */
    function addDeposits(address smartVault, uint256[] memory amounts)
        external
        validSmartVault(smartVault)
        returns (uint256)
    {
        address[] memory tokens = ISmartVault(smartVault).asset();
        if (tokens.length != amounts.length) revert InvalidAssetLengths();

        uint256 flushIdx = _flushIndexes[smartVault];
        bool initialized = _vaultDeposits[smartVault][flushIdx].length > 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            if (amounts[i] == 0) revert InvalidDepositAmount({smartVault: smartVault});

            if (initialized) {
                _vaultDeposits[smartVault][flushIdx][i] += amounts[i];
            } else {
                _vaultDeposits[smartVault][flushIdx].push(amounts[i]);
            }
        }

        return _flushIndexes[smartVault];
    }

    /**
     * @notice Calculate current Smart Vault asset deposit ratio
     * @dev As described in /notes/multi-asset-vault-deposit-ratios.md
     */
    function getDepositRatio(address smartVault) external view validSmartVault(smartVault) returns (uint256[] memory) {
        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        uint256[] memory allocations_ = _smartVaultAllocations[smartVault];
        address[] memory tokens = ISmartVault(smartVault).asset();

        if (strategies_.length != allocations_.length) revert InvalidArrayLength();

        uint256[] memory outRatios = new uint256[](tokens.length);

        if (tokens.length == 1) {
            outRatios[0] = 1;
            return outRatios;
        }

        uint256[] memory exchangeRates = _getExchangeRates(tokens);
        uint256[][] memory ratios = _getDepositRatios(strategies_, allocations_, tokens, exchangeRates);
        for (uint256 i = 0; i < strategies_.length; i++) {
            for (uint256 j = 0; j < tokens.length; j++) {
                outRatios[j] += ratios[i][j];
            }
        }

        for (uint256 j = tokens.length; j > 0; j--) {
            outRatios[j - 1] = outRatios[j - 1] * RATIO_PRECISION / outRatios[0];
        }

        return outRatios;
    }

    /**
     * @notice Transfer all pending deposits from the SmartVault to strategies
     * @dev Distribute as described in /notes/multi-asset-vault-deposit-ratios.md
     * @param smartVault Smart Vault address
     */
    function flushSmartVault(address smartVault) external validSmartVault(smartVault) {
        uint256 flushIdx = _flushIndexes[smartVault];
        address[] memory tokens = ISmartVault(smartVault).asset();
        uint256[] memory deposits = _vaultDeposits[smartVault][flushIdx];

        if (tokens.length != deposits.length) revert InvalidAssetLengths();

        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        uint256[] memory allocations_ = _smartVaultAllocations[smartVault];

        if (strategies_.length != allocations_.length) revert InvalidArrayLength();

        uint256[] memory exchangeRates = _getExchangeRates(tokens);
        uint256[][] memory depositRatios = _getDepositRatios(strategies_, allocations_, tokens, exchangeRates);
        // TODO: swap to match ratio

        uint256[][] memory strategyDeposits = new uint256[][](strategies_.length);

        {
            uint256 depositNorm = 0;
            uint256 usdPrecision = 10 ** _priceFeedManager.usdDecimals();
            uint256[] memory depositAccum = new uint256[](tokens.length);

            for (uint256 j = 0; j < tokens.length; j++) {
                depositNorm += exchangeRates[j] * deposits[j];
            }

            for (uint256 i = 0; i < strategies_.length; i++) {
                strategyDeposits[i] = new uint256[](tokens.length);

                for (uint256 j = 0; j < tokens.length; j++) {
                    strategyDeposits[i][j] = depositNorm * depositRatios[i][j] / RATIO_PRECISION / usdPrecision;
                    depositAccum[j] += strategyDeposits[i][j];

                    // Dust
                    if (i == strategies_.length - 1) {
                        strategyDeposits[i][j] += deposits[j] - depositAccum[j];
                    }
                }
            }
        }

        uint256[] memory dhwIndexes = _strategyRegistry.addDeposits(strategies_, strategyDeposits, tokens);
        emit SmartVaultFlushed(smartVault, flushIdx);

        _flushIndexes[smartVault] = flushIdx + 1;
    }

    function _getDepositRatios(
        address[] memory strategies_,
        uint256[] memory allocations_,
        address[] memory tokens,
        uint256[] memory exchangeRates
    ) internal view returns (uint256[][] memory) {
        uint256[][] memory outRatios = new uint256[][](strategies_.length);
        uint256[][] memory strategyRatios = _getStrategyRatios(strategies_);

        uint256 usdPrecision = 10 ** _priceFeedManager.usdDecimals();

        for (uint256 i = 0; i < strategies_.length; i++) {
            outRatios[i] = new uint256[](tokens.length);
            uint256 ratioNorm = 0;

            for (uint256 j = 0; j < tokens.length; j++) {
                ratioNorm += exchangeRates[j] * strategyRatios[i][j];
            }

            for (uint256 j = 0; j < tokens.length; j++) {
                outRatios[i][j] +=
                    allocations_[i] * strategyRatios[i][j] * usdPrecision * RATIO_PRECISION / ratioNorm / 100;
            }
        }

        return outRatios;
    }

    function _getExchangeRates(address[] memory tokens) internal view returns (uint256[] memory) {
        uint256[] memory exchangeRates = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            exchangeRates[i] = _priceFeedManager.assetToUsd(tokens[i], 10 ** ERC20(tokens[i]).decimals());
        }

        return exchangeRates;
    }

    function _getStrategyRatios(address[] memory strategies_) internal view returns (uint256[][] memory) {
        uint256[][] memory ratios = new uint256[][](strategies_.length);
        for (uint256 i = 0; i < strategies_.length; i++) {
            ratios[i] = IStrategy(strategies_[i]).assetRatio();
        }

        return ratios;
    }

    /**
     * @notice TODO
     */
    function reallocate() external {}

    /* ========== PRIVATE/INTERNAL FUNCTIONS ========== */

    /* ========== MODIFIERS ========== */

    modifier validRiskProvider(address address_) {
        if (!_riskManager.isRiskProvider(address_)) revert InvalidRiskProvider({address_: address_});
        _;
    }
}
