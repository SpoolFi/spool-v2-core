// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/utils/math/Math.sol";
import "@openzeppelin/utils/math/SafeCast.sol";
import "../interfaces/IAction.sol";
import "../interfaces/IAssetGroupRegistry.sol";
import "../interfaces/IDepositManager.sol";
import "../interfaces/IGuardManager.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/IRiskManager.sol";
import "../interfaces/ISmartVault.sol";
import "../interfaces/ISmartVaultManager.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/Constants.sol";
import "../interfaces/RequestType.sol";
import "../access/SpoolAccessControllable.sol";
import "../libraries/ArrayMapping.sol";
import "../libraries/SpoolUtils.sol";
import "../libraries/uint128a2Lib.sol";

/**
 * @notice Used when deposit is not made in correct asset ratio.
 */
error IncorrectDepositRatio();

/**
 * @notice Used when trying to burn deposit NFT that was not synced yet.
 * @param id ID of the NFT.
 */
error DepositNftNotSyncedYet(uint256 id);

/**
 * @notice Contains parameters for distributeDeposit call.
 * @custom:member deposit Amounts deposited.
 * @custom:member exchangeRates Asset -> USD exchange rates.
 * @custom:member allocation Required allocation of value between different strategies.
 * @custom:member strategyRatios Required ratios between assets for each strategy.
 */
struct DepositQueryBag1 {
    uint256[] deposit;
    uint256[] exchangeRates;
    uint16a16 allocation;
    uint256[][] strategyRatios;
}

struct ClaimTokensLocalBag {
    bytes[] metadata;
    uint256 mintedSVTs;
    DepositMetadata data;
}

struct SyncDepositsSimulateLocalBag {
    int256 totalPlatformFees;
    uint256 svtSupply;
}

/**
 * @dev Requires roles:
 * - ROLE_MASTER_WALLET_MANAGER
 */
contract DepositManager is SpoolAccessControllable, IDepositManager {
    using SafeERC20 for IERC20;
    using uint16a16Lib for uint16a16;
    using uint128a2Lib for uint128a2;
    using ArrayMappingUint256 for mapping(uint256 => uint256);

    /**
     * @dev Precission multiplier for internal calculations.
     */
    uint256 constant PRECISION_MULTIPLIER = 10 ** 42;

    /**
     * @dev Relative tolerance for deposit ratio compared to ideal ratio.
     * Equals to 0.5%/
     */
    uint256 constant DEPOSIT_TOLERANCE = 50;

    /// @notice Strategy registry
    IStrategyRegistry private immutable _strategyRegistry;

    /// @notice Price feed manager
    IUsdPriceFeedManager private immutable _priceFeedManager;

    /// @notice Guard manager
    IGuardManager internal immutable _guardManager;

    /// @notice Action manager
    IActionManager internal immutable _actionManager;

    /**
     * @notice Exchange rates for vault, at given flush index
     * @dev smart vault => flush index => exchange rates
     */
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _flushExchangeRates;

    /**
     * @notice Flushed deposits for vault, at given flush index
     * @dev smart vault => flush index => strategy => assets deposited
     */
    mapping(address => mapping(uint256 => mapping(address => mapping(uint256 => uint256)))) internal
        _vaultFlushedDeposits;

    /**
     * @dev smart vault => flush index => FlushShares{mintedVaultShares flushSvtSupply}
     */
    mapping(address => mapping(uint256 => FlushShares)) internal _flushShares;

    /**
     * @notice Vault deposits at given flush index
     * @dev smart vault => flush index => assets deposited
     */
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _vaultDeposits;

    constructor(
        IStrategyRegistry strategyRegistry_,
        IUsdPriceFeedManager priceFeedManager_,
        IGuardManager guardManager_,
        IActionManager actionManager_,
        ISpoolAccessControl accessControl_
    ) SpoolAccessControllable(accessControl_) {
        if (address(guardManager_) == address(0)) revert ConfigurationAddressZero();
        if (address(actionManager_) == address(0)) revert ConfigurationAddressZero();
        if (address(strategyRegistry_) == address(0)) revert ConfigurationAddressZero();
        if (address(priceFeedManager_) == address(0)) revert ConfigurationAddressZero();

        _guardManager = guardManager_;
        _actionManager = actionManager_;
        _strategyRegistry = strategyRegistry_;
        _priceFeedManager = priceFeedManager_;
    }

    function smartVaultDeposits(address smartVault, uint256 flushIdx, uint256 assetGroupLength)
        external
        view
        returns (uint256[] memory)
    {
        return _vaultDeposits[smartVault][flushIdx].toArray(assetGroupLength);
    }

    function claimSmartVaultTokens(
        address smartVault,
        uint256[] calldata nftIds,
        uint256[] calldata nftAmounts,
        address[] calldata tokens,
        address executor,
        uint256 flushIndexToSync
    ) external returns (uint256) {
        _checkRole(ROLE_SMART_VAULT_MANAGER, msg.sender);

        if (nftIds.length != nftAmounts.length) {
            revert InvalidNftArrayLength();
        }

        // NOTE:
        // - here we are passing ids into the request context instead of amounts
        // - here we passing empty array as tokens
        _guardManager.runGuards(
            smartVault,
            RequestContext({
                receiver: executor,
                executor: executor,
                owner: executor,
                requestType: RequestType.BurnNFT,
                assets: nftIds,
                tokens: new address[](0)
            })
        );

        ClaimTokensLocalBag memory bag;
        ISmartVault vault = ISmartVault(smartVault);
        bag.metadata = vault.burnNFTs(executor, nftIds, nftAmounts);

        uint256 claimedVaultTokens = 0;
        for (uint256 i; i < nftIds.length; ++i) {
            if (nftIds[i] > MAXIMAL_DEPOSIT_ID) {
                revert InvalidDepositNftId(nftIds[i]);
            }

            // we can pass empty strategy array and empty DHW index array,
            // because vault should already be synced and mintedVaultShares values available
            bag.data = abi.decode(bag.metadata[i], (DepositMetadata));
            if (bag.data.flushIndex >= flushIndexToSync) {
                revert DepositNftNotSyncedYet(nftIds[i]);
            }

            bag.mintedSVTs = _flushShares[smartVault][bag.data.flushIndex].mintedVaultShares;

            claimedVaultTokens +=
                getClaimedVaultTokensPreview(smartVault, bag.data, nftAmounts[i], bag.mintedSVTs, tokens);
        }

        // there will be some dust after all users claim SVTs
        vault.claimShares(executor, claimedVaultTokens);

        emit SmartVaultTokensClaimed(smartVault, executor, claimedVaultTokens, nftIds, nftAmounts);

        return claimedVaultTokens;
    }

    function flushSmartVault(
        address smartVault,
        uint256 flushIndex,
        address[] calldata strategies,
        uint16a16 allocation,
        address[] calldata tokens
    ) external returns (uint16a16) {
        _checkRole(ROLE_SMART_VAULT_MANAGER, msg.sender);

        if (_vaultDeposits[smartVault][flushIndex][0] == 0) {
            return uint16a16.wrap(0);
        }

        // handle deposits
        uint256[] memory exchangeRates = SpoolUtils.getExchangeRates(tokens, _priceFeedManager);
        _flushExchangeRates[smartVault][flushIndex].setValues(exchangeRates);

        uint256[][] memory distribution = distributeDeposit(
            DepositQueryBag1({
                deposit: _vaultDeposits[smartVault][flushIndex].toArray(tokens.length),
                exchangeRates: exchangeRates,
                allocation: allocation,
                strategyRatios: SpoolUtils.getStrategyRatiosAtLastDhw(strategies, _strategyRegistry)
            })
        );

        for (uint256 i; i < strategies.length; ++i) {
            if (distribution[i].length > 0) {
                _vaultFlushedDeposits[smartVault][flushIndex][strategies[i]].setValues(distribution[i]);
            }
        }

        // Strategy shares should not exceed uint128
        _flushShares[smartVault][flushIndex].flushSvtSupply = SafeCast.toUint128(ISmartVault(smartVault).totalSupply());

        return _strategyRegistry.addDeposits(strategies, distribution);
    }

    function syncDeposits(
        address smartVault,
        uint256[2] calldata bag,
        // uint256 flushIndex,
        // uint256 lastDhwSyncedTimestamp
        address[] calldata strategies,
        uint16a16[2] calldata dhwIndexes,
        address[] calldata assetGroup,
        SmartVaultFees calldata fees
    ) external returns (DepositSyncResult memory) {
        _checkRole(ROLE_SMART_VAULT_MANAGER, msg.sender);
        // mint SVTs based on USD value of claimed SSTs
        DepositSyncResult memory syncResult = syncDepositsSimulate(
            SimulateDepositParams(smartVault, bag, strategies, assetGroup, dhwIndexes[0], dhwIndexes[1], fees)
        );

        if (syncResult.mintedSVTs > 0) {
            // Vault shares should not exceed uint128
            _flushShares[smartVault][bag[0]].mintedVaultShares = SafeCast.toUint128(syncResult.mintedSVTs);
            for (uint256 i; i < strategies.length; ++i) {
                if (syncResult.sstShares[i] > 0) {
                    IStrategy(strategies[i]).claimShares(smartVault, syncResult.sstShares[i]);
                }
            }
        }

        return syncResult;
    }

    function syncDepositsSimulate(SimulateDepositParams memory parameters)
        public
        view
        returns (DepositSyncResult memory result)
    {
        uint256 deposits;
        {
            uint256[] memory dhwTimestamps =
                _strategyRegistry.dhwTimestamps(parameters.strategies, parameters.dhwIndexes);

            result.dhwTimestamp = parameters.bag[1];
            result.sstShares = new uint256[](parameters.strategies.length);

            // find last DHW timestamp of this flush index cycle
            for (uint256 i; i < parameters.strategies.length; ++i) {
                if (dhwTimestamps[i] > result.dhwTimestamp) {
                    result.dhwTimestamp = dhwTimestamps[i];
                }
            }

            deposits = _vaultDeposits[parameters.smartVault][parameters.bag[0]][0];
        }

        uint256[2] memory totalUsd;
        // totalUsd[0]: total USD value of deposits
        // totalUsd[1]: total USD value of the smart vault
        int256 totalYieldUsd;

        StrategyAtIndex[] memory strategyDhwStates = _strategyRegistry.strategyAtIndexBatch(
            parameters.strategies, parameters.dhwIndexes, parameters.assetGroup.length
        );

        // get previous yield for each strategy
        int256[] memory previousYields;
        if (parameters.fees.performanceFeePct > 0 && uint16a16.unwrap(parameters.dhwIndexesOld) > 0) {
            previousYields = _strategyRegistry.getDhwYield(parameters.strategies, parameters.dhwIndexesOld);
        }

        SyncDepositsSimulateLocalBag memory localVariables = SyncDepositsSimulateLocalBag({
            totalPlatformFees: _getTotalPlatformFees(),
            svtSupply: ISmartVault(parameters.smartVault).totalSupply()
        });
        // calculate
        // - amount of SSTs to claim from each strategy
        // - USD value of yield belonging to this smart vault
        for (uint256 i; i < parameters.strategies.length; ++i) {
            StrategyAtIndex memory atDhw = strategyDhwStates[i];

            if (deposits > 0 && atDhw.sharesMinted > 0) {
                uint256[2] memory depositedUsd;
                // depositedUsd[0]: (vault) USD value deposited in the strategy by the smart vault
                // depositedUsd[1]: (strategy) USD value deposited in the strategy
                depositedUsd[0] = _getVaultDepositsValue(
                    parameters.smartVault,
                    parameters.bag[0],
                    parameters.strategies[i],
                    atDhw.exchangeRates,
                    parameters.assetGroup
                );
                depositedUsd[1] = _priceFeedManager.assetToUsdCustomPriceBulk(
                    parameters.assetGroup, atDhw.assetsDeposited, atDhw.exchangeRates
                );

                // get value of deposits
                result.sstShares[i] = atDhw.sharesMinted * depositedUsd[0] / depositedUsd[1];
                totalUsd[0] += result.sstShares[i] * atDhw.totalStrategyValue / atDhw.totalSSTs;
            }

            if (atDhw.totalStrategyValue == 0) {
                // this also covers scenario where `atDhw.totalSSTs` is 0
                continue;
            }

            // get value of the smart vault
            uint256 strategyUsd = atDhw.totalStrategyValue
                * IStrategy(parameters.strategies[i]).balanceOf(parameters.smartVault) / atDhw.totalSSTs;
            totalUsd[1] += strategyUsd;

            // get yield
            if (parameters.fees.performanceFeePct > 0 && previousYields.length > 0) {
                // dhwYield = prevYield + trueYield + prevYield * trueYield
                // => interimYield = (dhwYield - prevYield) / (1 + prevYield)
                int256 interimYieldPct = YIELD_FULL_PERCENT_INT * (atDhw.dhwYields - previousYields[i])
                    / (YIELD_FULL_PERCENT_INT + previousYields[i]);
                // strategyUsd = strategyUsdBefore * (1 + yieldPct * (1 - platformFeesPct))
                // totalStrategyYieldUsd = (strategyUsd - strategyUsd / (1 + yieldPct * (1 - platformFeesPct))) / (1 - platformFeesPct)
                //   = strategyUsd * (yieldPct * (1 - platformFeesPct) / 1 + yieldPct * (1 - platformFeesPct)) / (1 - platformFeesPct)
                //   = strategyUsdBefore * (1 + yieldPct * (1 - platformFeesPct)) * yieldPct / (1 + yieldPct * (1 - platformFeesPct))
                //   = strategyUsdBefore * yieldPct
                totalYieldUsd += (
                    int256(strategyUsd)
                        - (
                            int256(strategyUsd) * YIELD_FULL_PERCENT_INT
                                / (
                                    YIELD_FULL_PERCENT_INT
                                        + interimYieldPct * (FULL_PERCENT_INT - localVariables.totalPlatformFees) / FULL_PERCENT_INT
                                )
                        )
                ) * FULL_PERCENT_INT / (FULL_PERCENT_INT - localVariables.totalPlatformFees);
            }
        }

        // calculate amount of SVTs to mint
        if (totalUsd[1] == 0) {
            result.mintedSVTs = totalUsd[0] * INITIAL_SHARE_MULTIPLIER;
        } else {
            uint256 fees;
            // management fees
            if (parameters.fees.managementFeePct > 0) {
                // take percentage of whole vault
                fees = totalUsd[1] * parameters.fees.managementFeePct * (result.dhwTimestamp - parameters.bag[1])
                    / SECONDS_IN_YEAR / FULL_PERCENT;
            }
            // performance fees
            if (parameters.fees.performanceFeePct > 0 && totalYieldUsd > 0) {
                // take percentage of yield
                fees += uint256(totalYieldUsd) * parameters.fees.performanceFeePct / FULL_PERCENT;
            }
            if (fees > 0) {
                // dilute shares to collect fees
                // current amount represents all value minus fees
                //   svtSupply ... totalUsd[1] - fees
                // amount of fee shares represent fees
                //   feeSVTs ... fees
                // => feeSVTs = svtSupply * fees / (totalUsd[1] - fees)
                result.feeSVTs = localVariables.svtSupply * fees / (totalUsd[1] - fees);
            }

            // deposits
            result.mintedSVTs = (localVariables.svtSupply + result.feeSVTs) * totalUsd[0] / totalUsd[1];
        }

        // deposit fees
        if (parameters.fees.depositFeePct > 0 && result.mintedSVTs > 0) {
            // take smart vault shares to collect deposit fees
            uint256 depositFees = result.mintedSVTs * parameters.fees.depositFeePct / FULL_PERCENT;
            unchecked {
                result.feeSVTs += depositFees;
                result.mintedSVTs -= depositFees;
            }
        }
    }

    function _getTotalPlatformFees() private view returns (int256) {
        PlatformFees memory fees = _strategyRegistry.platformFees();

        return int256(uint256(fees.ecosystemFeePct)) + int256(uint256(fees.treasuryFeePct));
    }

    function _getVaultDepositsValue(
        address smartVault,
        uint256 flushIndex,
        address strategy,
        uint256[] memory exchangeRates,
        address[] memory assetGroup
    ) private view returns (uint256) {
        return _priceFeedManager.assetToUsdCustomPriceBulk(
            assetGroup,
            _vaultFlushedDeposits[smartVault][flushIndex][strategy].toArray(assetGroup.length),
            exchangeRates
        );
    }

    function depositAssets(DepositBag calldata bag, DepositExtras calldata bag2)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint256)
    {
        if (bag2.tokens.length != bag.assets.length) {
            revert InvalidAssetLengths();
        }

        // run guards and actions
        _guardManager.runGuards(
            bag.smartVault,
            RequestContext({
                receiver: bag.receiver,
                executor: bag2.depositor,
                owner: bag2.depositor,
                requestType: RequestType.Deposit,
                tokens: bag2.tokens,
                assets: bag.assets
            })
        );

        _actionManager.runActions(
            ActionContext({
                smartVault: bag.smartVault,
                recipient: bag.receiver,
                executor: bag2.depositor,
                owner: bag2.depositor,
                requestType: RequestType.Deposit,
                tokens: bag2.tokens,
                amounts: bag.assets
            })
        );

        // check if assets are in correct ratio
        checkDepositRatio(
            bag.assets,
            SpoolUtils.getExchangeRates(bag2.tokens, _priceFeedManager),
            bag2.allocations,
            SpoolUtils.getStrategyRatiosAtLastDhw(bag2.strategies, _strategyRegistry)
        );

        // transfer tokens from user to master wallet
        for (uint256 i; i < bag2.tokens.length; ++i) {
            _vaultDeposits[bag.smartVault][bag2.flushIndex][i] += bag.assets[i];
        }

        // mint deposit NFT
        DepositMetadata memory metadata = DepositMetadata(bag.assets, block.timestamp, bag2.flushIndex);
        uint256 depositId = ISmartVault(bag.smartVault).mintDepositNFT(bag.receiver, metadata);

        emit DepositInitiated(
            bag.smartVault, bag.receiver, depositId, bag2.flushIndex, bag.assets, bag2.depositor, bag.referral
        );

        return depositId;
    }

    /**
     * @notice Calculates fair distribution of deposit among strategies.
     * @param bag Parameter bag.
     * @return Distribution of deposits, with first index running over strategies and second index running over assets.
     */
    function distributeDeposit(DepositQueryBag1 memory bag) public pure returns (uint256[][] memory) {
        if (bag.deposit.length == 1) {
            return _distributeDepositSingleAsset(bag);
        } else {
            return _distributeDepositMultipleAssets(bag);
        }
    }

    /**
     * @notice Checks if deposit is made in correct ratio.
     * @dev Reverts with IncorrectDepositRatio if the check fails.
     * @param deposit Amounts deposited.
     * @param exchangeRates Asset -> USD exchange rates.
     * @param allocation Required allocation of value between different strategies.
     * @param strategyRatios Required ratios between assets for each strategy.
     */
    function checkDepositRatio(
        uint256[] memory deposit,
        uint256[] memory exchangeRates,
        uint16a16 allocation,
        uint256[][] memory strategyRatios
    ) public pure {
        if (deposit.length == 1) {
            return;
        }

        uint256[] memory idealDeposit = calculateDepositRatio(exchangeRates, allocation, strategyRatios);

        // loop over assets
        for (uint256 i = 1; i < deposit.length; ++i) {
            uint256 valueA = deposit[i] * idealDeposit[i - 1];
            uint256 valueB = deposit[i - 1] * idealDeposit[i];

            if ( // check if valueA is within DEPOSIT_TOLERANCE of valueB
                valueA < (valueB * (FULL_PERCENT - DEPOSIT_TOLERANCE) / FULL_PERCENT)
                    || valueA > (valueB * (FULL_PERCENT + DEPOSIT_TOLERANCE) / FULL_PERCENT)
            ) {
                revert IncorrectDepositRatio();
            }
        }
    }

    /**
     * @notice Calculates ideal deposit ratio for a smart vault.
     * @param exchangeRates Asset -> USD exchange rates.
     * @param allocation Required allocation of value between different strategies.
     * @param strategyRatios Required ratios between assets for each strategy.
     * @return Ideal deposit ratio.
     */
    function calculateDepositRatio(
        uint256[] memory exchangeRates,
        uint16a16 allocation,
        uint256[][] memory strategyRatios
    ) public pure returns (uint256[] memory) {
        if (exchangeRates.length == 1) {
            uint256[] memory ratio = new uint256[](1);
            ratio[0] = 1;

            return ratio;
        }

        return _calculateDepositRatioFromFlushFactors(calculateFlushFactors(exchangeRates, allocation, strategyRatios));
    }

    /**
     * @dev Calculate flush factors - intermediate result.
     * @param exchangeRates Asset -> USD exchange rates.
     * @param allocation Required allocation of value between different strategies.
     * @param strategyRatios Required ratios between assets for each strategy.
     * @return Flush factors, with first index running over strategies and second index running over assets.
     */
    function calculateFlushFactors(
        uint256[] memory exchangeRates,
        uint16a16 allocation,
        uint256[][] memory strategyRatios
    ) public pure returns (uint256[][] memory) {
        uint256[][] memory flushFactors = new uint256[][](strategyRatios.length);

        // loop over strategies
        for (uint256 i; i < strategyRatios.length; ++i) {
            flushFactors[i] = new uint256[](exchangeRates.length);

            if (allocation.get(i) == 0) {
                // ghost strategy
                // - flush factors should be set to 0, which are already by default
                continue;
            }

            uint256 normalization = 0;
            // loop over assets
            for (uint256 j = 0; j < exchangeRates.length; ++j) {
                normalization += strategyRatios[i][j] * exchangeRates[j];
            }

            // loop over assets
            for (uint256 j = 0; j < exchangeRates.length; ++j) {
                flushFactors[i][j] = allocation.get(i) * strategyRatios[i][j] * PRECISION_MULTIPLIER / normalization;
            }
        }

        return flushFactors;
    }

    /**
     * @notice Calculates the SVT balance that is available to be claimed
     */
    function getClaimedVaultTokensPreview(
        address smartVaultAddress,
        DepositMetadata memory data,
        uint256 nftShares,
        uint256 mintedSVTs,
        address[] calldata tokens
    ) public view returns (uint256) {
        uint256[] memory totalDepositedAssets;
        uint256[] memory exchangeRates;
        uint256 depositedUsd;
        uint256 totalDepositedUsd;
        totalDepositedAssets = _vaultDeposits[smartVaultAddress][data.flushIndex].toArray(data.assets.length);
        exchangeRates = _flushExchangeRates[smartVaultAddress][data.flushIndex].toArray(data.assets.length);

        if (mintedSVTs == 0) {
            mintedSVTs = _flushShares[smartVaultAddress][data.flushIndex].mintedVaultShares;
        }

        for (uint256 i; i < data.assets.length; ++i) {
            depositedUsd += _priceFeedManager.assetToUsdCustomPrice(tokens[i], data.assets[i], exchangeRates[i]);
            totalDepositedUsd +=
                _priceFeedManager.assetToUsdCustomPrice(tokens[i], totalDepositedAssets[i], exchangeRates[i]);
        }
        uint256 claimedVaultTokens = mintedSVTs * depositedUsd / totalDepositedUsd;

        return claimedVaultTokens * nftShares / NFT_MINTED_SHARES;
    }

    /**
     * @dev Calculated deposit ratio from flush factors.
     * @param flushFactors Flush factors.
     * @return Deposit ratio, with first index running over strategies (same length as flush factors) and second index running over assets.
     */
    function _calculateDepositRatioFromFlushFactors(uint256[][] memory flushFactors)
        private
        pure
        returns (uint256[] memory)
    {
        uint256[] memory depositRatio = new uint256[](flushFactors[0].length);

        // loop over strategies
        for (uint256 i; i < flushFactors.length; ++i) {
            // loop over assets
            for (uint256 j = 0; j < flushFactors[i].length; ++j) {
                depositRatio[j] += flushFactors[i][j];
            }
        }

        return depositRatio;
    }

    /**
     * @dev Calculates fair distribution of single asset among strategies.
     * @param bag Parameter bag.
     * @return Distribution of deposits, with first index running over strategies and second index running over assets.
     */
    function _distributeDepositSingleAsset(DepositQueryBag1 memory bag) private pure returns (uint256[][] memory) {
        uint256 distributed;
        uint256[][] memory distribution = new uint256[][](bag.strategyRatios.length);

        uint256 totalAllocation;
        for (uint256 i; i < bag.strategyRatios.length; ++i) {
            totalAllocation += bag.allocation.get(i);
        }

        // loop over strategies
        for (uint256 i; i < bag.strategyRatios.length; ++i) {
            distribution[i] = new uint256[](1);

            distribution[i][0] = bag.deposit[0] * bag.allocation.get(i) / totalAllocation;
            distributed += distribution[i][0];
        }

        // handle dust
        distribution[0][0] += bag.deposit[0] - distributed;

        return distribution;
    }

    /**
     * @dev Calculates fair distribution of multiple assets among strategies.
     * @param bag Parameter bag.
     * @return Distribution of deposits, with first index running over strategies and second index running over assets.
     */
    function _distributeDepositMultipleAssets(DepositQueryBag1 memory bag) private pure returns (uint256[][] memory) {
        uint256[][] memory flushFactors = calculateFlushFactors(bag.exchangeRates, bag.allocation, bag.strategyRatios);
        uint256[] memory idealDepositRatio = _calculateDepositRatioFromFlushFactors(flushFactors);

        uint256[] memory distributed = new uint256[](bag.deposit.length);
        uint256[][] memory distribution = new uint256[][](bag.strategyRatios.length);

        // loop over strategies
        for (uint256 i; i < bag.strategyRatios.length; ++i) {
            distribution[i] = new uint256[](bag.exchangeRates.length);

            // loop over assets
            for (uint256 j = 0; j < bag.exchangeRates.length; j++) {
                distribution[i][j] = bag.deposit[j] * flushFactors[i][j] / idealDepositRatio[j];
                distributed[j] += distribution[i][j];
            }
        }

        // handle dust
        for (uint256 j = 0; j < bag.exchangeRates.length; j++) {
            // We cannot just assign the dust to an arbitrary strategy (like first or last one)
            // in case it is ghost strategy. So we need to find a strategy that was already
            // allocated some assets and assign dust to that one instead.
            for (uint256 i; i < bag.strategyRatios.length; ++i) {
                if (distribution[i][j] > 0) {
                    distribution[i][j] += bag.deposit[j] - distributed[j];
                    break;
                }
            }
        }

        return distribution;
    }
}
