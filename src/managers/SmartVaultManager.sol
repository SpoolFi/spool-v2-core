// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/utils/math/Math.sol";
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
import "../interfaces/IWithdrawalManager.sol";
import "../interfaces/CommonErrors.sol";
import "../interfaces/Constants.sol";
import "../interfaces/RequestType.sol";
import "../access/SpoolAccessControllable.sol";
import "../libraries/ArrayMapping.sol";
import "../libraries/uint16a16Lib.sol";
import "../libraries/ReallocationLib.sol";

struct VaultSyncUserBag {
    address[] tokens;
    address[] strategies;
    bytes[] metadata;
    uint256[] nftBalances;
}

/**
 * @dev Requires roles:
 * - ROLE_MASTER_WALLET_MANAGER
 * - ROLE_SMART_VAULT_MANAGER
 */
contract SmartVaultManager is ISmartVaultManager, SpoolAccessControllable {
    using uint16a16Lib for uint16a16;
    using SafeERC20 for IERC20;
    using ArrayMappingUint256 for mapping(uint256 => uint256);
    using ArrayMappingAddress for mapping(uint256 => address);

    IDepositManager private immutable _depositManager;

    IWithdrawalManager private immutable _withdrawalManager;

    /// @notice Strategy registry
    IStrategyRegistry private immutable _strategyRegistry;

    /// @notice Asset Group registry
    IAssetGroupRegistry private immutable _assetGroupRegistry;

    /// @notice Risk manager.
    IRiskManager private immutable _riskManager;

    /// @notice Master wallet
    IMasterWallet private immutable _masterWallet;

    /// @notice Price feed manager
    IUsdPriceFeedManager private immutable _priceFeedManager;

    address private immutable _ghostStrategy;

    /* ========== STATE VARIABLES ========== */

    /// @notice Smart Vault registry
    mapping(address => bool) internal _smartVaultRegistry;

    /// @notice Smart Vault - asset group ID registry
    mapping(address => uint256) internal _smartVaultAssetGroups;

    /// @notice Smart Vault strategy registry
    mapping(address => address[]) internal _smartVaultStrategies;

    /// @notice Smart vault fees
    mapping(address => SmartVaultFees) internal _smartVaultFees;

    /// @notice Smart Vault strategy allocations
    mapping(address => uint16a16) internal _smartVaultAllocations;

    /// @notice Current flush index and index to sync for given Smart Vault
    mapping(address => FlushIndex) internal _flushIndexes;

    /**
     * @notice DHW indexes for given Smart Vault and flush index
     * @dev smart vault => flush index => DHW indexes
     */
    mapping(address => mapping(uint256 => uint16a16)) internal _dhwIndexes;

    /**
     * @notice Timestamp of the last DHW that was synced
     * @dev smart vault => dhw timestamp
     */
    mapping(address => uint256) _lastDhwTimestampSynced;

    constructor(
        ISpoolAccessControl accessControl_,
        IAssetGroupRegistry assetGroupRegistry_,
        IRiskManager riskManager_,
        IDepositManager depositManager_,
        IWithdrawalManager withdrawalManager_,
        IStrategyRegistry strategyRegistry_,
        IMasterWallet masterWallet_,
        IUsdPriceFeedManager priceFeedManager_,
        address ghostStrategy
    ) SpoolAccessControllable(accessControl_) {
        if (address(assetGroupRegistry_) == address(0)) revert ConfigurationAddressZero();
        if (address(riskManager_) == address(0)) revert ConfigurationAddressZero();
        if (address(depositManager_) == address(0)) revert ConfigurationAddressZero();
        if (address(withdrawalManager_) == address(0)) revert ConfigurationAddressZero();
        if (address(strategyRegistry_) == address(0)) revert ConfigurationAddressZero();
        if (address(masterWallet_) == address(0)) revert ConfigurationAddressZero();
        if (address(priceFeedManager_) == address(0)) revert ConfigurationAddressZero();
        if (ghostStrategy == address(0)) revert ConfigurationAddressZero();

        _assetGroupRegistry = assetGroupRegistry_;
        _riskManager = riskManager_;
        _depositManager = depositManager_;
        _withdrawalManager = withdrawalManager_;
        _strategyRegistry = strategyRegistry_;
        _masterWallet = masterWallet_;
        _priceFeedManager = priceFeedManager_;
        _ghostStrategy = ghostStrategy;
    }

    /* ========== VIEW FUNCTIONS ========== */
    /**
     * @notice Retrieves a Smart Vault Token Balance for user. Including the predicted balance from all current D-NFTs
     * currently in holding.
     */
    function getUserSVTBalance(address smartVaultAddress, address userAddress, uint256[] calldata nftIds)
        external
        view
        returns (uint256)
    {
        uint256 currentBalance = ISmartVault(smartVaultAddress).balanceOf(userAddress);

        if (_accessControl.smartVaultOwner(smartVaultAddress) == userAddress) {
            (,, uint256 fees) = _simulateSync(smartVaultAddress);
            currentBalance += fees;
        }

        if (nftIds.length > 0) {
            currentBalance += _simulateSyncWithBurn(smartVaultAddress, userAddress, nftIds);
        }

        return currentBalance;
    }

    function getSVTTotalSupply(address smartVault) external view returns (uint256) {
        (uint256 currentSupply, uint256 mintedSVTs, uint256 fees) = _simulateSync(smartVault);
        return currentSupply + mintedSVTs + fees;
    }

    /**
     * @notice SmartVault strategies
     */
    function strategies(address smartVault) external view returns (address[] memory) {
        return _smartVaultStrategies[smartVault];
    }

    /**
     * @notice SmartVault strategy allocations
     */
    function allocations(address smartVault) external view returns (uint16a16) {
        return _smartVaultAllocations[smartVault];
    }

    /**
     * @notice SmartVault asset group ID
     */
    function assetGroupId(address smartVault) external view returns (uint256) {
        return _smartVaultAssetGroups[smartVault];
    }

    function depositRatio(address smartVault) external view returns (uint256[] memory) {
        return _depositManager.getDepositRatio(
            _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]),
            _smartVaultAllocations[smartVault],
            _smartVaultStrategies[smartVault]
        );
    }

    /**
     * @notice SmartVault latest flush index
     */
    function getLatestFlushIndex(address smartVault) external view returns (uint256) {
        return _flushIndexes[smartVault].current;
    }

    /**
     * @notice DHW indexes that were active at given flush index
     */
    function dhwIndexes(address smartVault, uint256 flushIndex) external view returns (uint16a16) {
        return _dhwIndexes[smartVault][flushIndex];
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /* ========== DEPOSIT/WITHDRAW ========== */

    function redeem(RedeemBag calldata bag, address receiver, bool doFlush) external whenNotPaused returns (uint256) {
        return _redeem(bag, receiver, msg.sender, msg.sender, doFlush);
    }

    function redeemFor(RedeemBag calldata bag, address owner, bool doFlush) external whenNotPaused returns (uint256) {
        _checkRole(ROLE_SMART_VAULT_ALLOW_REDEEM, bag.smartVault);
        _checkSmartVaultRole(bag.smartVault, ROLE_SMART_VAULT_ADMIN, msg.sender);
        return _redeem(bag, owner, owner, msg.sender, doFlush);
    }

    function redeemFast(
        RedeemBag calldata bag,
        uint256[][] calldata withdrawalSlippages,
        uint256[2][] calldata exchangeRateSlippages
    ) external whenNotPaused returns (uint256[] memory) {
        _onlyRegisteredSmartVault(bag.smartVault);

        address[] memory strategies_ = _smartVaultStrategies[bag.smartVault];
        uint256 assetGroupId_ = _smartVaultAssetGroups[bag.smartVault];
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId_);

        if (
            bag.nftIds.length != bag.nftAmounts.length || strategies_.length != withdrawalSlippages.length
                || tokens.length != exchangeRateSlippages.length
        ) {
            revert InvalidArrayLength();
        }

        _syncSmartVault(bag.smartVault, strategies_, tokens, false);
        uint256 flushIndexToSync = _flushIndexes[bag.smartVault].toSync;
        _depositManager.claimSmartVaultTokens(
            bag.smartVault, bag.nftIds, bag.nftAmounts, tokens, msg.sender, flushIndexToSync
        );
        return _withdrawalManager.redeemFast(
            bag,
            RedeemFastExtras(strategies_, tokens, assetGroupId_, msg.sender, withdrawalSlippages, exchangeRateSlippages)
        );
    }

    function deposit(DepositBag calldata bag) external whenNotPaused returns (uint256) {
        _onlyRegisteredSmartVault(bag.smartVault);
        return _depositAssets(bag);
    }

    function claimSmartVaultTokens(address smartVault, uint256[] calldata nftIds, uint256[] calldata nftAmounts)
        public
        whenNotPaused
        returns (uint256)
    {
        _onlyRegisteredSmartVault(smartVault);
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);
        _syncSmartVault(smartVault, _smartVaultStrategies[smartVault], tokens, false);
        uint256 flushIndexToSync = _flushIndexes[smartVault].toSync;
        return
            _depositManager.claimSmartVaultTokens(smartVault, nftIds, nftAmounts, tokens, msg.sender, flushIndexToSync);
    }

    function claimWithdrawal(
        address smartVault,
        uint256[] calldata nftIds,
        uint256[] calldata nftAmounts,
        address receiver
    ) public whenNotPaused returns (uint256[] memory, uint256) {
        _onlyRegisteredSmartVault(smartVault);
        uint256 assetGroupId_ = _smartVaultAssetGroups[smartVault];
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId_);

        _syncSmartVault(smartVault, _smartVaultStrategies[smartVault], tokens, false);
        return _withdrawalManager.claimWithdrawal(
            WithdrawalClaimBag(
                smartVault,
                nftIds,
                nftAmounts,
                receiver,
                msg.sender,
                assetGroupId_,
                tokens,
                _flushIndexes[smartVault].toSync
            )
        );
    }

    /* ========== REGISTRY ========== */

    function registerSmartVault(address smartVault, SmartVaultRegistrationForm calldata registrationForm)
        external
        whenNotPaused
    {
        _checkRole(ROLE_SMART_VAULT_INTEGRATOR, msg.sender);

        if (_smartVaultRegistry[smartVault]) {
            revert SmartVaultAlreadyRegistered();
        }

        // set asset group
        _smartVaultAssetGroups[smartVault] = registrationForm.assetGroupId;

        // set strategies
        _smartVaultStrategies[smartVault] = registrationForm.strategies;

        // set smart vault fees
        _smartVaultFees[smartVault] = SmartVaultFees(
            registrationForm.managementFeePct, registrationForm.depositFeePct, registrationForm.performanceFeePct
        );

        // set allocation
        _smartVaultAllocations[smartVault] = registrationForm.strategyAllocation;

        // update registry
        _smartVaultRegistry[smartVault] = true;

        emit SmartVaultRegistered(smartVault, registrationForm);
    }

    function removeStrategyFromVaults(address strategy, address[] calldata vaults, bool disableStrategy) external {
        _checkRole(ROLE_SPOOL_ADMIN, msg.sender);

        for (uint256 i; i < vaults.length; ++i) {
            address smartVault = vaults[i];
            address[] memory strategies_ = _smartVaultStrategies[vaults[i]];
            for (uint256 j; j < strategies_.length; ++j) {
                if (strategies_[j] == strategy) {
                    _smartVaultStrategies[smartVault][j] = _ghostStrategy;
                    _smartVaultAllocations[smartVault] = _smartVaultAllocations[smartVault].set(j, 0);

                    break;
                }
            }
        }

        emit StrategyRemovedFromVaults(strategy, vaults);

        if (disableStrategy) {
            _strategyRegistry.removeStrategy(strategy);
        }
    }

    /* ========== BOOKKEEPING ========== */

    function flushSmartVault(address smartVault) public whenNotPaused {
        _onlyRegisteredSmartVault(smartVault);
        _flushSmartVault(
            smartVault,
            _smartVaultAllocations[smartVault],
            _smartVaultStrategies[smartVault],
            _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault])
        );
    }

    function syncSmartVault(address smartVault, bool revertIfError) public whenNotPaused {
        _onlyRegisteredSmartVault(smartVault);
        _syncSmartVault(
            smartVault,
            _smartVaultStrategies[smartVault],
            _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]),
            revertIfError
        );
    }

    function reallocate(ReallocateParamBag calldata reallocateParams) external whenNotPaused {
        // Can only be called by a reallocator.
        if (!_isViewExecution()) {
            _checkRole(ROLE_REALLOCATOR, msg.sender);
        }

        if (reallocateParams.smartVaults.length == 0) {
            // Check if there is anything to reallocate.
            return;
        }

        if (
            reallocateParams.strategies.length != reallocateParams.swapInfo.length
                || reallocateParams.strategies.length != reallocateParams.depositSlippages.length
                || reallocateParams.strategies.length != reallocateParams.withdrawalSlippages.length
        ) {
            revert InvalidArrayLength();
        }

        uint256 assetGroupId_ = _smartVaultAssetGroups[reallocateParams.smartVaults[0]];
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId_);
        for (uint256 i; i < reallocateParams.smartVaults.length; ++i) {
            address smartVault = reallocateParams.smartVaults[i];

            // Check that all smart vaults are registered.
            _onlyRegisteredSmartVault(smartVault);

            // Check that all smart vaults use the same asset group.
            if (_smartVaultAssetGroups[smartVault] != assetGroupId_) {
                revert NotSameAssetGroup();
            }

            // Check that any smart vault does not have statically set allocation.
            if (_riskManager.getRiskProvider(smartVault) == address(0)) {
                revert StaticAllocationSmartVault();
            }

            // Sync smart vault.
            _syncSmartVault(smartVault, _smartVaultStrategies[smartVault], tokens, false);

            // Set new allocation.
            uint16a16 newAllocations = _riskManager.calculateAllocation(smartVault, _smartVaultStrategies[smartVault]);
            _smartVaultAllocations[smartVault] = newAllocations;

            emit SmartVaultReallocated(smartVault, newAllocations);
        }

        ReallocationParameterBag memory reallocationParameterBag = ReallocationParameterBag({
            assetGroupRegistry: _assetGroupRegistry,
            priceFeedManager: _priceFeedManager,
            masterWallet: _masterWallet,
            assetGroupId: assetGroupId_,
            swapInfo: reallocateParams.swapInfo,
            depositSlippages: reallocateParams.depositSlippages,
            withdrawalSlippages: reallocateParams.withdrawalSlippages,
            exchangeRateSlippages: reallocateParams.exchangeRateSlippages
        });

        // Do the reallocation.
        ReallocationLib.reallocate(
            reallocateParams.smartVaults,
            reallocateParams.strategies,
            _ghostStrategy,
            reallocationParameterBag,
            _smartVaultStrategies,
            _smartVaultAllocations
        );
    }

    /* ========== PRIVATE/INTERNAL FUNCTIONS ========== */

    /**
     * @dev Claim strategy shares, account for withdrawn assets and sync SVTs for all new DHW runs
     * Invariants:
     * - There can't be more than once un-synced flush index per vault at any given time.
     * - Flush index can't be synced, if all DHWs haven't been completed yet.
     */
    function _syncSmartVault(
        address smartVault,
        address[] memory strategies_,
        address[] memory tokens,
        bool revertIfError
    ) private {
        FlushIndex memory flushIndex = _flushIndexes[smartVault];

        if (flushIndex.current == flushIndex.toSync) {
            if (revertIfError) {
                revert NothingToSync();
            }

            return;
        }

        // Pack values to avoid stack depth limit
        uint16a16 indexes = _dhwIndexes[smartVault][flushIndex.toSync];
        uint16a16[2] memory packedIndexes = [indexes, _getPreviousDhwIndexes(smartVault, flushIndex.toSync)];
        DepositSyncResult memory syncResult;

        // If DHWs haven't been run yet, we can't sync
        if (!_areAllDhwRunsCompleted(_strategyRegistry.currentIndex(strategies_), indexes, strategies_, revertIfError))
        {
            return;
        }

        SmartVaultFees memory fees = _smartVaultFees[smartVault];
        address vaultOwner = _accessControl.smartVaultOwner(smartVault);
        // Pack values to avoid stack depth limit
        uint256[2] memory packedParams = [flushIndex.toSync, _lastDhwTimestampSynced[smartVault]];

        // SYNC WITHDRAWALS
        _withdrawalManager.syncWithdrawals(smartVault, flushIndex.toSync, strategies_, indexes);

        // SYNC DEPOSITS
        syncResult = _depositManager.syncDeposits(smartVault, packedParams, strategies_, packedIndexes, tokens, fees);

        emit SmartVaultSynced(smartVault, flushIndex.toSync);
        flushIndex.toSync++;
        _flushIndexes[smartVault] = flushIndex;
        _lastDhwTimestampSynced[smartVault] = syncResult.dhwTimestamp;

        if (syncResult.mintedSVTs > 0) {
            ISmartVault(smartVault).mintVaultShares(smartVault, syncResult.mintedSVTs);
        }

        if (syncResult.feeSVTs > 0) {
            ISmartVault(smartVault).mintVaultShares(vaultOwner, syncResult.feeSVTs);
        }
    }

    /**
     * @dev Check whether all DHW runs were completed for given indexes
     */
    function _areAllDhwRunsCompleted(
        uint256[] memory currentStrategyIndexes,
        uint16a16 dhwIndexes_,
        address[] memory strategies_,
        bool revertIfError
    ) private view returns (bool) {
        for (uint256 i; i < strategies_.length; ++i) {
            if (strategies_[i] == _ghostStrategy) {
                continue;
            }

            if (dhwIndexes_.get(i) >= currentStrategyIndexes[i]) {
                if (revertIfError) {
                    revert DhwNotRunYetForIndex(strategies_[i], dhwIndexes_.get(i));
                }

                return false;
            }
        }

        return true;
    }

    /**
     * @dev Calculate number of SVTs that haven't been synced yet after DHW runs
     * DHW has minted strategy shares, but vaults haven't claimed them yet.
     * Includes management fees (percentage of assets under management, distributed throughout a year) and deposit fees .
     * Invariants:
     * - There can't be more than once un-synced flush index per vault at any given time.
     * - Flush index can't be synced, if all DHWs haven't been completed yet.
     */
    function _simulateSync(address smartVault) private view returns (uint256 oldTotalSVTs, uint256, uint256) {
        address[] memory tokens;
        address[] memory strategies_;
        FlushIndex memory flushIndex;
        SmartVaultFees memory fees;
        uint16a16 indexes;

        {
            tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);
            strategies_ = _smartVaultStrategies[smartVault];
            oldTotalSVTs = ISmartVault(smartVault).totalSupply();
            flushIndex = _flushIndexes[smartVault];
            fees = _smartVaultFees[smartVault];
            indexes = _dhwIndexes[smartVault][flushIndex.toSync];
        }

        // If DHWs haven't been run yet, we can't sync
        if (!_areAllDhwRunsCompleted(_strategyRegistry.currentIndex(strategies_), indexes, strategies_, false)) {
            return (oldTotalSVTs, 0, 0);
        }

        uint256[2] memory packedParams;
        uint16a16 previousIndexes;

        {
            previousIndexes = _getPreviousDhwIndexes(smartVault, flushIndex.toSync);
            uint256 lastDhwTimestamp = _lastDhwTimestampSynced[smartVault];
            packedParams = [flushIndex.toSync, lastDhwTimestamp];
        }

        SimulateDepositParams memory params;
        {
            params =
                SimulateDepositParams(smartVault, packedParams, strategies_, tokens, indexes, previousIndexes, fees);
        }

        DepositSyncResult memory syncResult = _depositManager.syncDepositsSimulate(params);

        flushIndex.toSync++;

        return (oldTotalSVTs, syncResult.mintedSVTs, syncResult.feeSVTs);
    }

    /**
     * @dev Calculate how many SVTs a user would receive, if he were to burn his NFTs.
     * For NFTs that are part of a vault flush that haven't been synced yet, simulate vault sync.
     * We have to simulate sync in correct order, to calculate management fees.
     *
     * Invariants:
     * - There can't be more than once un-synced flush index per vault at any given time.
     * - Flush index can't be synced, if all DHWs haven't been completed yet.
     * - W-NFTs and NFTs with fractional balance of 0 will be skipped.
     */
    function _simulateSyncWithBurn(address smartVault, address userAddress, uint256[] memory nftIds)
        private
        view
        returns (uint256 newBalance)
    {
        VaultSyncUserBag memory bag2;
        FlushIndex memory flushIndex;

        {
            bag2.metadata = ISmartVault(smartVault).getMetadata(nftIds);
            bag2.nftBalances = ISmartVault(smartVault).balanceOfFractionalBatch(userAddress, nftIds);
            bag2.tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);
            bag2.strategies = _smartVaultStrategies[smartVault];
            flushIndex = _flushIndexes[smartVault];
        }

        // Burn any NFTs that have already been synced
        newBalance += _simulateNFTBurn(smartVault, nftIds, bag2, 0, flushIndex, false);

        // Check if latest flush index has already been synced.
        if (flushIndex.toSync == flushIndex.current) {
            return newBalance;
        }

        SmartVaultFees memory fees = _smartVaultFees[smartVault];
        uint256[] memory currentStrategyIndexes = _strategyRegistry.currentIndex(bag2.strategies);
        uint16a16 indexes = _dhwIndexes[smartVault][flushIndex.toSync];

        // If DHWs haven't been run yet, we can't sync
        if (!_areAllDhwRunsCompleted(currentStrategyIndexes, indexes, bag2.strategies, false)) {
            return newBalance;
        }

        uint256[2] memory packedParams;
        {
            packedParams = [flushIndex.toSync, _lastDhwTimestampSynced[smartVault]];
        }

        uint16a16 previousIndexes = _getPreviousDhwIndexes(smartVault, flushIndex.toSync);
        SimulateDepositParams memory params = SimulateDepositParams(
            smartVault, packedParams, bag2.strategies, bag2.tokens, indexes, previousIndexes, fees
        );

        // Simulate deposit sync (DHW)
        DepositSyncResult memory syncResult = _depositManager.syncDepositsSimulate(params);

        // Burn any NFTs that would be synced as part of this flush cycle
        newBalance += _simulateNFTBurn(smartVault, nftIds, bag2, syncResult.mintedSVTs, flushIndex, true);

        return newBalance;
    }

    /**
     * @dev Check how many SVTs would be received by burning the given array of NFTs
     * @param smartVault vault address
     * @param nftIds array of D-NFT ids
     * @param bag NFT balances, token addresses and NFT metadata
     * @param mintedSVTs amount of SVTs minted when syncing flush index
     * @param flushIndex global flush index
     * @param onlyCurrentFlushIndex whether to burn NFTs for current synced flush index or previously synced ones
     */
    function _simulateNFTBurn(
        address smartVault,
        uint256[] memory nftIds,
        VaultSyncUserBag memory bag,
        uint256 mintedSVTs,
        FlushIndex memory flushIndex,
        bool onlyCurrentFlushIndex
    ) private view returns (uint256) {
        uint256 SVTs;
        for (uint256 i; i < nftIds.length; ++i) {
            // Skip W-NFTs
            if (nftIds[i] > MAXIMAL_DEPOSIT_ID) continue;

            // Skip D-NFTs with 0 balance
            if (bag.nftBalances[i] == 0) continue;

            DepositMetadata memory data = abi.decode(bag.metadata[i], (DepositMetadata));

            // we're burning NFTs that have already been synced previously
            if (!onlyCurrentFlushIndex && data.flushIndex >= flushIndex.toSync) continue;

            // we're burning NFTs for current synced flushIndex
            if (onlyCurrentFlushIndex && data.flushIndex != flushIndex.toSync) continue;

            SVTs += _depositManager.getClaimedVaultTokensPreview(
                smartVault, data, bag.nftBalances[i], mintedSVTs, bag.tokens
            );
        }

        return SVTs;
    }

    function _redeem(RedeemBag calldata bag, address receiver, address owner, address executor, bool doFlush)
        internal
        returns (uint256)
    {
        _onlyRegisteredSmartVault(bag.smartVault);

        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[bag.smartVault]);
        _syncSmartVault(bag.smartVault, _smartVaultStrategies[bag.smartVault], tokens, false);

        uint256 flushIndexToSync = _flushIndexes[bag.smartVault].toSync;
        _depositManager.claimSmartVaultTokens(
            bag.smartVault, bag.nftIds, bag.nftAmounts, tokens, owner, flushIndexToSync
        );
        uint256 nftId = _withdrawalManager.redeem(
            bag,
            RedeemExtras({
                receiver: receiver,
                owner: owner,
                executor: executor,
                flushIndex: _flushIndexes[bag.smartVault].current
            })
        );

        if (doFlush) {
            flushSmartVault(bag.smartVault);
        }

        return nftId;
    }

    /**
     * @dev Prepare deposits to be processed in the next DHW cycle.
     * - first sync vault
     * - update vault rewards
     * - optionally trigger flush right after
     */
    function _depositAssets(DepositBag calldata bag) internal returns (uint256) {
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[bag.smartVault]);
        address[] memory strategies_ = _smartVaultStrategies[bag.smartVault];
        uint16a16 allocations_ = _smartVaultAllocations[bag.smartVault];

        _syncSmartVault(bag.smartVault, strategies_, tokens, false);

        uint256 depositId = _depositManager.depositAssets(
            bag,
            DepositExtras({
                depositor: msg.sender,
                tokens: tokens,
                allocations: allocations_,
                strategies: strategies_,
                flushIndex: _flushIndexes[bag.smartVault].current
            })
        );

        for (uint256 i; i < bag.assets.length; ++i) {
            IERC20(tokens[i]).safeTransferFrom(msg.sender, address(_masterWallet), bag.assets[i]);
        }

        if (bag.doFlush) {
            _flushSmartVault(bag.smartVault, allocations_, strategies_, tokens);
        }

        return depositId;
    }

    /**
     * @dev Mark accrued deposits and withdrawals ready for the next DHW cycle
     */
    function _flushSmartVault(
        address smartVault,
        uint16a16 allocations_,
        address[] memory strategies_,
        address[] memory tokens
    ) private {
        FlushIndex memory flushIndex = _flushIndexes[smartVault];

        // Flushing without having synced the previous flush is not allowed
        if (flushIndex.toSync != flushIndex.current) revert VaultNotSynced();

        // need to flush withdrawal before flushing deposit
        uint16a16 flushDhwIndexes = _withdrawalManager.flushSmartVault(smartVault, flushIndex.current, strategies_);
        uint16a16 flushDhwIndexes2 =
            _depositManager.flushSmartVault(smartVault, flushIndex.current, strategies_, allocations_, tokens);

        if (uint16a16.unwrap(flushDhwIndexes2) > 0) {
            flushDhwIndexes = flushDhwIndexes2;
        }

        if (uint16a16.unwrap(flushDhwIndexes) == 0) revert NothingToFlush();

        _dhwIndexes[smartVault][flushIndex.current] = flushDhwIndexes;

        emit SmartVaultFlushed(smartVault, flushIndex.current);

        flushIndex.current++;
        _flushIndexes[smartVault] = flushIndex;
    }

    function _getPreviousDhwIndexes(address smartVault, uint256 flushIndex) private view returns (uint16a16) {
        return flushIndex == 0 ? uint16a16.wrap(0) : _dhwIndexes[smartVault][flushIndex - 1];
    }

    function _onlyRegisteredSmartVault(address smartVault) internal view {
        if (!_smartVaultRegistry[smartVault]) {
            revert SmartVaultNotRegisteredYet();
        }
    }

    function _isViewExecution() private view returns (bool) {
        return tx.origin == address(0);
    }
}
