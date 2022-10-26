// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {console} from "forge-std/console.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/ISmartVaultManager.sol";
import "../interfaces/IRiskManager.sol";
import "../interfaces/ISmartVault.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";
import "../interfaces/ISmartVaultManager.sol";

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

contract SmartVaultDeposits is ISmartVaultDeposits {
    /// @notice Deposit ratio precision
    uint256 constant RATIO_PRECISION = 10 ** 22;

    uint256 constant ALLOC_PRECISION = 1000;

    /// @notice Difference between desired and actual amounts in WEI after swapping
    uint256 constant SWAP_TOLERANCE = 500;

    /// @notice Price Feed Manager
    IUsdPriceFeedManager private immutable _priceFeedManager;

    /// @notice Strategy registry
    IStrategyRegistry private immutable _strategyRegistry;

    constructor(IUsdPriceFeedManager priceFeedManager_, IStrategyRegistry strategyRegistry_) {
        _priceFeedManager = priceFeedManager_;
        _strategyRegistry = strategyRegistry_;
    }

    /**
     * @notice Calculate current Smart Vault asset deposit ratio
     * @dev As described in /notes/multi-asset-vault-deposit-ratios.md
     */
    function getDepositRatio(DepositRatioQueryBag memory bag) external view returns (uint256[] memory) {
        uint256[] memory outRatios = new uint256[](bag.tokens.length);

        if (bag.tokens.length == 1) {
            outRatios[0] = 1;
            return outRatios;
        }

        uint256[] memory exchangeRates = _getExchangeRates(bag.tokens);
        uint256[][] memory ratios =
            _getDepositRatios(bag.smartVault, bag.strategies, bag.tokens, exchangeRates, bag.allocations);
        for (uint256 i = 0; i < bag.strategies.length; i++) {
            for (uint256 j = 0; j < bag.tokens.length; j++) {
                outRatios[j] += ratios[i][j];
            }
        }

        for (uint256 j = bag.tokens.length; j > 0; j--) {
            outRatios[j - 1] = outRatios[j - 1] * RATIO_PRECISION / outRatios[0];
        }

        return outRatios;
    }

    /**
     * @notice Calculate Smart Vault deposit distributions for underlying strategies based on their
     * internal ratio.
     * @param bag Deposit specific parameters
     * @param swapInfo Information needed to perform asset swaps
     * @return Token deposit amounts per strategy
     */
    function distributeVaultDeposits(DepositDistributorBag memory bag, SwapInfo[] calldata swapInfo)
        external
        returns (uint256[][] memory)
    {
        if (bag.tokens.length != bag.depositsIn.length) revert InvalidAssetLengths();

        uint256[] memory exchangeRates = _getExchangeRates(bag.tokens);
        uint256[] memory decimals = new uint256[](bag.tokens.length);
        uint256[][] memory depositRatios;
        uint256 depositUSD = 0;

        depositRatios = _getDepositRatios(bag.smartVault, bag.strategies, bag.tokens, exchangeRates, bag.allocations);

        for (uint256 j = 0; j < bag.tokens.length; j++) {
            decimals[j] = ERC20(bag.tokens[j]).decimals();
            depositUSD += exchangeRates[j] * bag.depositsIn[j] / 10 ** decimals[j];
        }

        DepositBag memory depositBag = DepositBag(
            bag.tokens,
            bag.strategies,
            bag.depositsIn,
            decimals,
            exchangeRates,
            depositRatios,
            depositUSD,
            _priceFeedManager.usdDecimals()
        );

        depositBag.depositsIn = _swapToRatio(depositBag, swapInfo);
        return _distributeAcrossStrategies(depositBag);
    }

    function _swapToRatio(DepositBag memory bag, SwapInfo[] memory swapInfo) internal returns (uint256[] memory) {
        uint256[] memory oldBalances = _getBalances(bag.tokens);
        for (uint256 i; i < swapInfo.length; i++) {
            _swap(swapInfo[i]);
        }
        uint256[] memory newBalances = _getBalances(bag.tokens);
        uint256[] memory depositsOut = new uint256[](bag.tokens.length);

        for (uint256 i = 0; i < bag.tokens.length; i++) {
            uint256 ratio = 0;

            for (uint256 j = 0; j < bag.depositRatios.length; j++) {
                ratio += bag.depositRatios[j][i];
            }

            // Add/Subtract swapped amounts
            if (newBalances[i] >= oldBalances[i]) {
                depositsOut[i] = bag.depositsIn[i] + (newBalances[i] - oldBalances[i]);
            } else {
                depositsOut[i] = bag.depositsIn[i] - (oldBalances[i] - newBalances[i]);
            }

            // Desired token deposit amount
            uint256 desired = ratio * bag.depositUSD * 10 ** bag.decimals[i] / 10 ** bag.usdDecimals / RATIO_PRECISION;

            // Check discrepancies
            bool isOk = desired == depositsOut[i]
                || desired > depositsOut[i] && (desired - depositsOut[i]) < SWAP_TOLERANCE
                || desired < depositsOut[i] && (depositsOut[i] - desired) < SWAP_TOLERANCE;

            if (!isOk) {
                revert SwapTolerance();
            }
        }

        return depositsOut;
    }

    function _distributeAcrossStrategies(DepositBag memory bag) internal returns (uint256[][] memory) {
        uint256[] memory depositAccum = new uint256[](bag.tokens.length);
        uint256[][] memory strategyDeposits = new uint256[][](bag.strategies.length);
        uint256 usdPrecision = 10 ** bag.usdDecimals;

        for (uint256 i = 0; i < bag.strategies.length; i++) {
            strategyDeposits[i] = new uint256[](bag.tokens.length);

            for (uint256 j = 0; j < bag.tokens.length; j++) {
                uint256 tokenPrecision = 10 ** bag.decimals[j];
                strategyDeposits[i][j] =
                    bag.depositUSD * bag.depositRatios[i][j] * tokenPrecision / RATIO_PRECISION / usdPrecision;
                depositAccum[j] += strategyDeposits[i][j];

                // Dust
                if (i == bag.strategies.length - 1) {
                    strategyDeposits[i][j] += bag.depositsIn[j] - depositAccum[j];
                }
            }
        }

        return strategyDeposits;
    }

    function _getDepositRatios(
        address smartVault,
        address[] memory strategies_,
        address[] memory tokens,
        uint256[] memory exchangeRates,
        uint256[] memory allocations_
    ) internal view returns (uint256[][] memory) {
        uint256[][] memory outRatios = new uint256[][](strategies_.length);
        if (strategies_.length != allocations_.length) revert InvalidArrayLength();

        uint256[][] memory strategyRatios = _getStrategyRatios(strategies_);
        uint256 usdPrecision = 10 ** _priceFeedManager.usdDecimals();

        for (uint256 i = 0; i < strategies_.length; i++) {
            outRatios[i] = new uint256[](tokens.length);
            uint256 ratioNorm = 0;

            for (uint256 j = 0; j < tokens.length; j++) {
                ratioNorm += exchangeRates[j] * strategyRatios[i][j];
            }

            for (uint256 j = 0; j < tokens.length; j++) {
                outRatios[i][j] += allocations_[i] * strategyRatios[i][j] * usdPrecision * RATIO_PRECISION / ratioNorm
                    / ALLOC_PRECISION;
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

    function _getBalances(address[] memory tokens) private returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = ERC20(tokens[i]).balanceOf(address(this));
        }

        return balances;
    }

    function _swap(SwapInfo memory _swapInfo) private {
        (bool success, bytes memory data) = _swapInfo.swapTarget.call(_swapInfo.swapCallData);
        if (!success) revert(_getRevertMsg(data));
    }

    /**
     * @dev Gets revert message when a low-level call reverts, so that it can
     * be bubbled-up to caller.
     * @param _returnData Data returned from reverted low-level call.
     * @return Revert message.
     */
    function _getRevertMsg(bytes memory _returnData) private pure returns (string memory) {
        // if the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) {
            return "CompositeOrder::getRevertMsg: Transaction reverted silently.";
        }

        assembly {
            // slice the sig hash
            _returnData := add(_returnData, 0x04)
        }

        return abi.decode(_returnData, (string)); // all that remains is the revert string
    }
}

contract SmartVaultManager is SmartVaultRegistry, ISmartVaultManager {
    /* ========== STATE VARIABLES ========== */

    /// @notice Strategy registry
    IStrategyRegistry private immutable _strategyRegistry;

    /// @notice Risk manager
    IRiskManager private immutable _riskManager;

    /// @notice Vault deposits logic
    ISmartVaultDeposits private immutable _vaultDepositsManager;

    /// @notice Smart Vault strategy registry
    mapping(address => address[]) internal _smartVaultStrategies;

    /// @notice Smart Vault risk provider registry
    mapping(address => address) internal _smartVaultRiskProviders;

    /// @notice Smart Vault strategy allocations
    mapping(address => uint256[]) internal _smartVaultAllocations;

    /// @notice Smart Vault tolerance registry
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
        ISmartVaultDeposits vaultDepositsManager_
    ) {
        _strategyRegistry = strategyRegistry_;
        _riskManager = riskManager_;
        _vaultDepositsManager = vaultDepositsManager_;
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

    /**
     * @notice TODO
     */
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
     * @notice Accumulate and persist Smart Vault deposits before pushing to strategies
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
        DepositRatioQueryBag memory bag = DepositRatioQueryBag(
            smartVault,
            ISmartVault(smartVault).asset(),
            _smartVaultStrategies[smartVault],
            _smartVaultAllocations[smartVault]
        );

        return _vaultDepositsManager.getDepositRatio(bag);
    }

    /**
     * @notice Transfer all pending deposits from the SmartVault to strategies
     * @dev Swap to match ratio and distribute across strategies
     *      as described in /notes/multi-asset-vault-deposit-ratios.md
     * @param smartVault Smart Vault address
     * @param swapInfo Swap info
     */
    function flushSmartVault(address smartVault, SwapInfo[] calldata swapInfo) external validSmartVault(smartVault) {
        uint256 flushIdx = _flushIndexes[smartVault];

        DepositDistributorBag memory bag = DepositDistributorBag(
            smartVault,
            ISmartVault(smartVault).asset(),
            _smartVaultStrategies[smartVault],
            _vaultDeposits[smartVault][flushIdx],
            _smartVaultAllocations[smartVault]
        );

        uint256[][] memory distribution = _vaultDepositsManager.distributeVaultDeposits(bag, swapInfo);
        uint256[] memory dhwIndexes = _strategyRegistry.addDeposits(bag.strategies, distribution, bag.tokens);

        _dhwIndexes[smartVault][flushIdx] = dhwIndexes;
        _flushIndexes[smartVault] = flushIdx + 1;

        emit SmartVaultFlushed(smartVault, flushIdx);
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
