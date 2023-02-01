// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/utils/math/Math.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/ISmartVaultManager.sol";
import "../interfaces/IRiskManager.sol";
import "../interfaces/ISmartVault.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/IGuardManager.sol";
import "../interfaces/IAction.sol";
import "../interfaces/RequestType.sol";
import "../interfaces/IAssetGroupRegistry.sol";
import "../libraries/ArrayMapping.sol";
import "../access/SpoolAccessControl.sol";
import "../interfaces/ISmartVaultManager.sol";
import "../libraries/SpoolUtils.sol";
import "./ActionsAndGuards.sol";
import "../interfaces/IDepositManager.sol";

/**
 * @notice Used when deposit is not made in correct asset ratio.
 */
error IncorrectDepositRatio();

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
    uint256[] allocation;
    uint256[][] strategyRatios;
}

contract DepositManager is ActionsAndGuards, SpoolAccessControllable, IDepositManager {
    using SafeERC20 for IERC20;
    using ArrayMapping for mapping(uint256 => uint256);

    uint256 constant INITIAL_SHARE_MULTIPLIER = 1000;

    /**
     * @dev Precission multiplier for internal calculations.
     */
    uint256 constant PRECISION_MULTIPLIER = 10 ** 42;

    /**
     * @dev Relative tolerance for deposit ratio compared to ideal ratio.
     * Equals to 0.5%/
     */
    uint256 constant DEPOSIT_TOLERANCE = 50;

    /**
     * @dev Represents full percent.
     * - 100_00 -> 100%
     * - 1_00 -> 1%
     * - 1 -> 0.01%
     */
    uint256 constant FULL_PERCENT = 100_00;

    /// @notice Strategy registry
    IStrategyRegistry private immutable _strategyRegistry;

    /// @notice Price feed manager
    IUsdPriceFeedManager private immutable _priceFeedManager;

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
     * @notice Minted vault shares at given flush index
     * @dev smart vault => flush index => vault shares minted
     */
    mapping(address => mapping(uint256 => uint256)) internal _mintedVaultShares;

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
    ) ActionsAndGuards(guardManager_, actionManager_) SpoolAccessControllable(accessControl_) {
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

    /**
     * @notice Calculates the SVT balance that is available to be claimed
     * @dev Simulates vault sync, if it hasn't been invoked yet
     */
    function getClaimedVaultTokensPreview(
        address smartVaultAddress,
        DepositMetadata memory data,
        uint256 nftShares,
        address[] memory tokens,
        address[] memory strategies,
        uint256[] memory dhwIndexes,
        bool allowSyncSimulate
    ) public view returns (uint256) {
        uint256[] memory totalDepositedAssets;
        uint256[] memory exchangeRates;
        uint256 depositedUsd;
        uint256 totalDepositedUsd;
        uint256 mintedSVTs;

        mintedSVTs = _mintedVaultShares[smartVaultAddress][data.flushIndex];
        totalDepositedAssets = _vaultDeposits[smartVaultAddress][data.flushIndex].toArray(data.assets.length);
        exchangeRates = _flushExchangeRates[smartVaultAddress][data.flushIndex].toArray(data.assets.length);

        if (mintedSVTs == 0 && allowSyncSimulate) {
            // simulate vault sync
            StrategyAtIndex[] memory dhwStates = _strategyRegistry.strategyAtIndexBatch(strategies, dhwIndexes);
            DepositSyncResult memory syncResult =
                syncDepositsSimulate(smartVaultAddress, data.flushIndex, strategies, tokens, dhwStates);
            mintedSVTs = syncResult.mintedSVTs;
        }

        for (uint256 i = 0; i < data.assets.length; i++) {
            depositedUsd += _priceFeedManager.assetToUsdCustomPrice(tokens[i], data.assets[i], exchangeRates[i]);
            totalDepositedUsd +=
                _priceFeedManager.assetToUsdCustomPrice(tokens[i], totalDepositedAssets[i], exchangeRates[i]);
        }
        uint256 claimedVaultTokens = mintedSVTs * depositedUsd / totalDepositedUsd;

        // TODO: dust
        return claimedVaultTokens * nftShares / NFT_MINTED_SHARES;
    }

    /**
     * @notice Burn deposit NFTs to claim SVTs
     * @param smartVault Vault address
     * @param nftIds NFTs to burn
     * @param nftAmounts NFT amounts to burn
     */
    function claimSmartVaultTokens(
        address smartVault,
        uint256[] calldata nftIds,
        uint256[] calldata nftAmounts,
        address[] memory tokens,
        address executor
    ) external onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender) returns (uint256) {
        // NOTE:
        // - here we are passing ids into the request context instead of amounts
        // - here we passing empty array as tokens
        _runGuards(smartVault, executor, executor, executor, nftIds, new address[](0), RequestType.BurnNFT);

        ISmartVault vault = ISmartVault(smartVault);
        bytes[] memory metadata = vault.burnNFTs(executor, nftIds, nftAmounts);

        uint256 claimedVaultTokens = 0;
        for (uint256 i = 0; i < nftIds.length; i++) {
            if (nftIds[i] > MAXIMAL_DEPOSIT_ID) {
                revert InvalidDepositNftId(nftIds[i]);
            }

            // we can pass empty strategy array and empty DHW index array,
            // because vault should already be synced and _mintedVaultShares values available
            claimedVaultTokens += getClaimedVaultTokensPreview(
                smartVault,
                abi.decode(metadata[i], (DepositMetadata)),
                nftAmounts[i],
                tokens,
                new address[](0),
                new uint256[](0),
                false
            );
        }

        // there will be some dust after all users claim SVTs
        vault.claimShares(executor, claimedVaultTokens);

        emit SmartVaultTokensClaimed(smartVault, executor, claimedVaultTokens, nftIds, nftAmounts);

        return claimedVaultTokens;
    }

    function flushSmartVault(
        address smartVault,
        uint256 flushIndex,
        address[] memory strategies,
        uint256[] memory allocation,
        address[] memory tokens
    ) external onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender) returns (uint256[] memory) {
        uint256[] memory flushDhwIndexes;

        if (_vaultDeposits[smartVault][flushIndex][0] > 0) {
            // handle deposits
            uint256[] memory exchangeRates = SpoolUtils.getExchangeRates(tokens, _priceFeedManager);
            uint256[] memory deposits = _vaultDeposits[smartVault][flushIndex].toArray(tokens.length);

            _flushExchangeRates[smartVault][flushIndex].setValues(exchangeRates);

            uint256[][] memory distribution = distributeDeposit(
                DepositQueryBag1({
                    deposit: deposits,
                    exchangeRates: exchangeRates,
                    allocation: allocation,
                    strategyRatios: SpoolUtils.getStrategyRatiosAtLastDhw(strategies, _strategyRegistry)
                })
            );

            flushDhwIndexes = _strategyRegistry.addDeposits(strategies, distribution);

            for (uint256 i = 0; i < strategies.length; i++) {
                _vaultFlushedDeposits[smartVault][flushIndex][strategies[i]].setValues(distribution[i]);
            }
        }

        return flushDhwIndexes;
    }

    function syncDeposits(
        address smartVault,
        uint256 flushIndex,
        address[] memory strategies,
        uint256[] memory dhwIndexes,
        address[] memory assetGroup
    ) external onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender) returns (DepositSyncResult memory) {
        StrategyAtIndex[] memory dhwStates = _strategyRegistry.strategyAtIndexBatch(strategies, dhwIndexes);
        // mint SVTs based on USD value of claimed SSTs
        DepositSyncResult memory syncResult =
            syncDepositsSimulate(smartVault, flushIndex, strategies, assetGroup, dhwStates);

        if (syncResult.mintedSVTs > 0) {
            _mintedVaultShares[smartVault][flushIndex] = syncResult.mintedSVTs;
            for (uint256 i = 0; i < strategies.length; i++) {
                IStrategy(strategies[i]).claimShares(smartVault, syncResult.sstShares[i]);
            }

            ISmartVault(smartVault).mint(smartVault, syncResult.mintedSVTs);
        }

        return syncResult;
    }

    function syncDepositsSimulate(
        address smartVault,
        uint256 flushIndex,
        address[] memory strategies,
        address[] memory assetGroup,
        StrategyAtIndex[] memory strategyDhwState
    ) public view returns (DepositSyncResult memory) {
        uint256[] memory sstShares = new uint256[](strategies.length);
        uint256 currentDhwTimestamp = 0;

        for (uint256 i = 0; i < strategies.length; i++) {
            StrategyAtIndex memory atDhw = strategyDhwState[i];

            if (atDhw.dhwTimestamp > currentDhwTimestamp) {
                currentDhwTimestamp = atDhw.dhwTimestamp;
            }
        }

        // skip if there were no deposits made
        if (_vaultDeposits[smartVault][flushIndex][0] == 0) {
            return DepositSyncResult(0, currentDhwTimestamp, sstShares);
        }

        // get vault's USD value before claiming SSTs
        uint256 totalVaultValueBefore = SpoolUtils.getVaultTotalUsdValue(smartVault, strategies);

        // claim SSTs from each strategy
        for (uint256 i = 0; i < strategies.length; i++) {
            StrategyAtIndex memory atDhw = strategyDhwState[i];

            uint256[] memory vaultDepositedAssets =
                _vaultFlushedDeposits[smartVault][flushIndex][strategies[i]].toArray(assetGroup.length);
            uint256 vaultDepositedUsd =
                _priceFeedManager.assetToUsdCustomPriceBulk(assetGroup, vaultDepositedAssets, atDhw.exchangeRates);
            uint256 strategyDepositedUsd =
                _priceFeedManager.assetToUsdCustomPriceBulk(assetGroup, atDhw.assetsDeposited, atDhw.exchangeRates);

            sstShares[i] = atDhw.sharesMinted * vaultDepositedUsd / strategyDepositedUsd;

            // TODO: there might be dust left after all vaults are synced
        }

        // mint SVTs based on USD value of claimed SSTs
        uint256 totalVaultValueAfter = SpoolUtils.getVaultTotalUsdValue(smartVault, strategies, sstShares);
        uint256 totalDepositedUsd = totalVaultValueAfter - totalVaultValueBefore;
        uint256 svtsToMint;
        if (totalVaultValueBefore == 0) {
            svtsToMint = totalDepositedUsd * INITIAL_SHARE_MULTIPLIER;
        } else {
            svtsToMint = totalDepositedUsd * ISmartVault(smartVault).totalSupply() / totalVaultValueBefore;
        }

        return DepositSyncResult({mintedSVTs: svtsToMint, lastDhwTimestamp: currentDhwTimestamp, sstShares: sstShares});
    }

    function depositAssets(DepositBag calldata bag, DepositExtras memory bag2)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint256[] memory, uint256)
    {
        if (bag2.tokens.length != bag.assets.length) {
            revert InvalidAssetLengths();
        }

        // run guards and actions
        _runGuards(
            bag.smartVault, bag2.executor, bag.receiver, bag2.owner, bag.assets, bag2.tokens, RequestType.Deposit
        );
        _runActions(
            bag.smartVault, bag2.executor, bag.receiver, bag2.owner, bag.assets, bag2.tokens, RequestType.Deposit
        );

        // check if assets are in correct ratio
        checkDepositRatio(
            bag.assets,
            SpoolUtils.getExchangeRates(bag2.tokens, _priceFeedManager),
            bag2.allocations,
            SpoolUtils.getStrategyRatiosAtLastDhw(bag2.strategies, _strategyRegistry)
        );

        // transfer tokens from user to master wallet
        for (uint256 i = 0; i < bag2.tokens.length; i++) {
            _vaultDeposits[bag.smartVault][bag2.flushIndex][i] = bag.assets[i];
        }

        // mint deposit NFT
        DepositMetadata memory metadata = DepositMetadata(bag.assets, block.timestamp, bag2.flushIndex);
        uint256 depositId = ISmartVault(bag.smartVault).mintDepositNFT(bag.receiver, metadata);

        emit DepositInitiated(
            bag.smartVault, bag.receiver, depositId, bag2.flushIndex, bag.assets, bag2.executor, bag.referral
            );

        return (_vaultDeposits[bag.smartVault][bag2.flushIndex].toArray(bag2.tokens.length), depositId);
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
        uint256[] memory allocation,
        uint256[][] memory strategyRatios
    ) public pure {
        if (deposit.length == 1) {
            return;
        }

        uint256[] memory idealDeposit = calculateDepositRatio(exchangeRates, allocation, strategyRatios);

        // loop over assets
        for (uint256 i = 1; i < deposit.length; i++) {
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
        uint256[] memory allocation,
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
        uint256[] memory allocation,
        uint256[][] memory strategyRatios
    ) public pure returns (uint256[][] memory) {
        uint256[][] memory flushFactors = new uint256[][](allocation.length);

        // loop over strategies
        for (uint256 i = 0; i < allocation.length; i++) {
            flushFactors[i] = new uint256[](exchangeRates.length);

            uint256 normalization = 0;
            // loop over assets
            for (uint256 j = 0; j < exchangeRates.length; j++) {
                normalization += strategyRatios[i][j] * exchangeRates[j];
            }

            // loop over assets
            for (uint256 j = 0; j < exchangeRates.length; j++) {
                flushFactors[i][j] = allocation[i] * strategyRatios[i][j] * PRECISION_MULTIPLIER / normalization;
            }
        }

        return flushFactors;
    }

    /**
     * @dev Calculated deposit ratio from flush factors.
     * @param flushFactors Flush factors.
     * @return Deposit ratio, with first index running over strategies and second index running over assets.
     */
    function _calculateDepositRatioFromFlushFactors(uint256[][] memory flushFactors)
        private
        pure
        returns (uint256[] memory)
    {
        uint256[] memory depositRatio = new uint256[](flushFactors[0].length);

        // loop over strategies
        for (uint256 i = 0; i < flushFactors.length; i++) {
            // loop over assets
            for (uint256 j = 0; j < flushFactors[i].length; j++) {
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
        uint256[][] memory distribution = new uint256[][](bag.allocation.length);

        uint256 totalAllocation;
        for (uint256 i = 0; i < bag.allocation.length; ++i) {
            totalAllocation += bag.allocation[i];
        }

        // loop over strategies
        for (uint256 i = 0; i < bag.allocation.length; ++i) {
            distribution[i] = new uint256[](1);

            distribution[i][0] = bag.deposit[0] * bag.allocation[i] / totalAllocation;
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
        uint256[][] memory distribution = new uint256[][](bag.allocation.length);

        // loop over strategies
        for (uint256 i = 0; i < bag.allocation.length; i++) {
            distribution[i] = new uint256[](bag.exchangeRates.length);

            // loop over assets
            for (uint256 j = 0; j < bag.exchangeRates.length; j++) {
                distribution[i][j] = bag.deposit[j] * flushFactors[i][j] / idealDepositRatio[j];
                distributed[j] += distribution[i][j];
            }
        }

        // handle dust
        for (uint256 j = 0; j < bag.exchangeRates.length; j++) {
            distribution[0][j] += bag.deposit[j] - distributed[j];
        }

        return distribution;
    }
}
