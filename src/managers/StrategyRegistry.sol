// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/console.sol";
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
    function strategyAtIndexBatch(address[] calldata strategies, uint256[] calldata dhwIndexes)
        external
        view
        returns (StrategyAtIndex[] memory)
    {
        StrategyAtIndex[] memory result = new StrategyAtIndex[](strategies.length);

        for (uint256 i = 0; i < strategies.length; i++) {
            result[i] = strategyAtIndex(strategies[i], dhwIndexes[i]);
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
            _dhwTimestamp[address(strategy)][dhwIndex] = block.timestamp;
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
    ) external view returns (uint256[] memory) {
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

    function reallocationReallocate(
        address[] calldata strategies,
        uint256[][][] memory reallocationTable,
        address[] calldata assetGroup,
        uint256[] calldata exchangeRates
    ) external returns (uint256[][][] memory) {
        // console.log("vv StrategyRegistry::reallocationReallocate vv");
        uint256[][] memory toDeposit = new uint256[][](strategies.length);
        for (uint256 i = 0; i < strategies.length; ++i) {
            toDeposit[i] = new uint256[](assetGroup.length + 1);
        }

        // distribute matched shares and withdraw unamatched
        // console.log("  loop 1");
        for (uint256 i = 0; i < strategies.length; ++i) {
            // console.log("    i", i);
            // calculate amount of shares to distribute and amount of shares to redeem
            uint256 sharesToRedeem;
            uint256 totalUnmatchedWithdrawals;

            {
                uint256[] memory totals = new uint256[](2);
                // totals[0] -> total withdrawals
                // totals[1] -> total matched withdrawals

                // console.log("    loop 1.1");
                for (uint256 j = 0; j < strategies.length; ++j) {
                    // console.log("      j", j);
                    // console.log("      reallocationTable[i][j][0]", reallocationTable[i][j][0]);
                    totals[0] += reallocationTable[i][j][0];
                    // console.log("      totals[0]", totals[0]);

                    // take smaller for matched withdrawals
                    // console.log("      reallocationTable[i][j][0]", reallocationTable[i][j][0]);
                    // console.log("      reallocationTable[j][i][0]", reallocationTable[j][i][0]);
                    if (reallocationTable[i][j][0] > reallocationTable[j][i][0]) {
                        totals[1] += reallocationTable[j][i][0];
                    } else {
                        totals[1] += reallocationTable[i][j][0];
                    }
                    // console.log("      totals[1]", totals[1]);
                }

                totalUnmatchedWithdrawals = totals[0] - totals[1];

                // console.log("    totals[0]", totals[0]);
                if (totals[0] == 0) {
                    // there is nothing to withdraw from strategy i
                    // console.log("    nothing to withdaw, skipping");
                    continue;
                }

                uint256 sharesToDistribute = IStrategy(strategies[i]).totalSupply() * totals[0] / IStrategy(strategies[i]).totalUsdValue();
                sharesToRedeem = sharesToDistribute * (totals[0] - totals[1]) / totals[0];
                sharesToDistribute -= sharesToRedeem;
                // console.log("    sharesToDistribute", sharesToDistribute);
                // console.log("    sharesToRedeem", sharesToRedeem);

                // distribute matched shares
                if (sharesToDistribute > 0) {
                    // console.log("    distributing matched shares");
                    // console.log("    loop 1.2");
                    for (uint256 j = 0; j < strategies.length; ++j) {
                        // console.log("      j", j);
                        uint256 matched;

                        // take smaller for matched withdrawals
                        if (reallocationTable[i][j][0] > reallocationTable[j][i][0]) {
                            matched = reallocationTable[j][i][0];
                        } else {
                            matched = reallocationTable[i][j][0];
                        }

                        if (matched == 0) {
                            continue;
                        }

                        // give shares to strategy j
                        reallocationTable[j][i][1] = sharesToDistribute * matched / totals[1];
                        // dust-less calculation
                        sharesToDistribute -= reallocationTable[j][i][1];
                        totals[1] -= matched;
                    }
                }
            }

            if (sharesToRedeem == 0) {
                // there is nothing to withdraw
                // console.log("    no shares to redeem, skipping");
                continue;
            }

            // withdraw
            // console.log("    redeeming shares");
            uint256[] memory withdrawnAssets = IStrategy(strategies[i]).redeemFast(
                sharesToRedeem,
                address(_masterWallet), // TODO: maybe have a clean bucket for reallocation
                assetGroup,
                exchangeRates,
                _priceFeedManager
            );

            // distribute withdrawn assets
            // console.log("    distributing shares");
            // console.log("    loop 1.3");
            for (uint256 j = 0; j < strategies.length; ++j) {
                // console.log("      j", j);
                // console.log("      reallocationTable[i][j][0]", reallocationTable[i][j][0]);
                // console.log("      reallocationTable[j][i][0]", reallocationTable[j][i][0]);
                if (reallocationTable[i][j][0] <= reallocationTable[j][i][0]) {
                    // nothing to deposit into strategy j
                    // console.log("      nothing to deposit into strategy j, skipping");
                    continue;
                }

                // console.log("      depositing into strategy j");
                // console.log("      loop 1.3.1");
                for (uint256 k = 0; k < assetGroup.length; ++k) {
                    // console.log("        k", k);
                    // console.log("        withdrawnAssets[k]", withdrawnAssets[k]);
                    // find out how much of asset k should go to strategy j
                    uint256 depositAmount = withdrawnAssets[k] * (reallocationTable[i][j][0] - reallocationTable[j][i][0]) / totalUnmatchedWithdrawals;
                    // console.log("        depositAmount", depositAmount);

                    toDeposit[j][k] += depositAmount;
                    // console.log("        toDeposit[j][k]", toDeposit[j][k]);
                    toDeposit[j][assetGroup.length] += 1;
                    // console.log("        toDeposit[j][assetGroup.length]", toDeposit[j][assetGroup.length]);
                    // console.log("        assetGroup[k]", assetGroup[k]);
                    // console.log("        depositAmount", depositAmount);
                    // console.log("        exchangeRates[k]", exchangeRates[k]);
                    // mark how much was given to strategy j for deposit
                    reallocationTable[i][j][2] += _priceFeedManager.assetToUsdCustomPrice(assetGroup[k], depositAmount, exchangeRates[k]);
                    // console.log("        reallocationTable[i][j][2]", reallocationTable[i][j][2]);
                    // dust-less calculation
                    withdrawnAssets[k] -= depositAmount;
                    // console.log("        withdrawnAssets[k]", withdrawnAssets[k]);
                }
                totalUnmatchedWithdrawals -= (reallocationTable[i][j][0] - reallocationTable[j][i][0]);
            }
        }

        // deposit
        // console.log("  loop 2");
        for (uint256 i = 0; i < strategies.length; ++i) {
            // console.log("    i", i);
            if (toDeposit[i][assetGroup.length] == 0) {
                // there is nothing to deposit for this strategy
                // console.log("      nothing to deposit, skipping");
                continue;
            }

            // console.log("    loop 2.1");
            for (uint256 j = 0; j < assetGroup.length; ++j) {
                // console.log("      j", j);
                // console.log("      toDeposit[i][j]", toDeposit[i][j]);
                _masterWallet.transfer(IERC20(assetGroup[j]), strategies[i], toDeposit[i][j]);
            }

            uint256 mintedSsts = IStrategy(strategies[i]).depositFast(assetGroup, exchangeRates, _priceFeedManager);
            // console.log("    mintedSsts", mintedSsts);

            // distribute minted SSTs
            uint256 totalDepositedValue = _priceFeedManager.assetToUsdCustomPriceBulk(assetGroup, toDeposit[i], exchangeRates);

            for (uint256 j = 0; j < strategies.length; ++j) {
                if (reallocationTable[j][i][2] == 0) {
                    // no shares to give to strategy j
                    continue;
                }

                // calculate amount of shares to give strategy j that deposited into this one
                uint256 shares = mintedSsts * reallocationTable[j][i][2] / totalDepositedValue;
                // dust-less calculation
                mintedSsts -= shares;
                totalDepositedValue -= reallocationTable[j][i][2];
                // give shares
                reallocationTable[j][i][2] = shares;
            }
        }

        // console.log("^^ StrategyRegistry::reallocationReallocate ^^");
        return reallocationTable;
    }
}
