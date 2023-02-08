// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

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
import "../interfaces/Constants.sol";
import "../interfaces/RequestType.sol";
import "../access/SpoolAccessControl.sol";
import "../libraries/ArrayMapping.sol";
import "../libraries/uint16a16Lib.sol";
import "../libraries/ReallocationLib.sol";

struct VaultSyncBag {
    address vaultOwner;
    uint256 oldTotalSVTs;
    uint256 feeSVTs;
    uint256 newSVTs;
    uint256 flushIndex;
    uint256 lastDhwSynced;
    uint256[] currentStrategyIndexes;
}

struct VaultSyncUserBag {
    address[] tokens;
    address[] strategies;
    bytes[] metadata;
    uint256[] nftBalances;
}

/**
 * @dev Requires roles:
 * - ROLE_STRATEGY_CLAIMER
 * - ROLE_MASTER_WALLET_MANAGER
 * - ROLE_SMART_VAULT_MANAGER
 */
contract SmartVaultManager is ISmartVaultManager, SpoolAccessControllable {
    /* ========== CONSTANTS ========== */

    using uint16a16Lib for uint16a16;
    using SafeERC20 for IERC20;
    using ArrayMapping for mapping(uint256 => uint256);
    using ArrayMapping for mapping(uint256 => address);

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

    /// @notice Current flush index for given Smart Vault
    mapping(address => uint256) internal _flushIndexes;

    /// @notice First flush index that still needs to be synced for given Smart Vault.
    mapping(address => uint256) internal _flushIndexesToSync;

    /// @notice List of vaults per strategy
    mapping(address => address[]) internal _smartVaultsWithStrategy;

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
    function getUserSVTBalance(address smartVaultAddress, address userAddress) external view returns (uint256) {
        if (_accessControl.smartVaultOwner(smartVaultAddress) == userAddress) {
            (, uint256 ownerSVTs,, uint256 fees) = _simulateSync(smartVaultAddress);
            return ownerSVTs + fees;
        }

        ISmartVault smartVault = ISmartVault(smartVaultAddress);
        uint256 currentBalance = smartVault.balanceOf(userAddress);
        uint256[] memory nftIds = smartVault.activeUserNFTIds(userAddress);

        if (nftIds.length > 0) {
            currentBalance += _simulateNFTBurn(smartVaultAddress, userAddress, nftIds);
        }

        return currentBalance;
    }

    function getSVTTotalSupply(address smartVault) external view returns (uint256) {
        (uint256 currentSupply, uint256 vaultOwnerSVTs, uint256 mintedSVTs, uint256 fees) = _simulateSync(smartVault);
        return currentSupply + vaultOwnerSVTs + mintedSVTs + fees;
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

    /**
     * @notice SmartVault latest flush index
     */
    function getLatestFlushIndex(address smartVault) external view returns (uint256) {
        return _flushIndexes[smartVault];
    }

    /**
     * @notice DHW indexes that were active at given flush index
     */
    function dhwIndexes(address smartVault, uint256 flushIndex) external view returns (uint16a16) {
        return _dhwIndexes[smartVault][flushIndex];
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /* ========== DEPOSIT/WITHDRAW ========== */

    function redeem(RedeemBag calldata bag, address receiver, bool doFlush)
        external
        whenNotPaused
        onlyRegisteredSmartVault(bag.smartVault)
        returns (uint256)
    {
        address[] memory strategies_ = _smartVaultStrategies[bag.smartVault];
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[bag.smartVault]);
        _syncSmartVault(bag.smartVault, strategies_, tokens, false);

        uint256 flushIndex = _flushIndexes[bag.smartVault];

        _depositManager.claimSmartVaultTokens(bag.smartVault, bag.nftIds, bag.nftAmounts, tokens, msg.sender);
        uint256 nftId = _withdrawalManager.redeem(bag, RedeemExtras(receiver, msg.sender, flushIndex));

        if (doFlush) {
            flushSmartVault(bag.smartVault);
        }

        return nftId;
    }

    function redeemFast(RedeemBag calldata bag)
        external
        whenNotPaused
        onlyRegisteredSmartVault(bag.smartVault)
        returns (uint256[] memory)
    {
        address[] memory strategies_ = _smartVaultStrategies[bag.smartVault];
        uint256 assetGroupId_ = _smartVaultAssetGroups[bag.smartVault];
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId_);

        _syncSmartVault(bag.smartVault, strategies_, tokens, false);
        _depositManager.claimSmartVaultTokens(bag.smartVault, bag.nftIds, bag.nftAmounts, tokens, msg.sender);
        return _withdrawalManager.redeemFast(bag, RedeemFastExtras(strategies_, tokens, assetGroupId_, msg.sender));
    }

    function deposit(DepositBag calldata bag)
        external
        whenNotPaused
        onlyRegisteredSmartVault(bag.smartVault)
        returns (uint256)
    {
        return _depositAssets(bag);
    }

    /**
     * @notice Burn deposit NFTs to claim SVTs
     * @param smartVault Vault address
     * @param nftIds NFTs to burn
     * @param nftAmounts NFT amounts to burn
     */
    function claimSmartVaultTokens(address smartVault, uint256[] calldata nftIds, uint256[] calldata nftAmounts)
        public
        whenNotPaused
        onlyRegisteredSmartVault(smartVault)
        returns (uint256)
    {
        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        uint256 assetGroupId_ = _smartVaultAssetGroups[smartVault];
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId_);

        _syncSmartVault(smartVault, strategies_, tokens, false);
        return _depositManager.claimSmartVaultTokens(smartVault, nftIds, nftAmounts, tokens, msg.sender);
    }

    /**
     * @notice Burn withdrawal NFTs to claim assets
     * @param smartVault Vault address
     * @param nftIds NFTs to burn
     * @param nftAmounts NFT amounts to burn
     * @param receiver Address to which to transfer claimed assets
     */
    function claimWithdrawal(
        address smartVault,
        uint256[] calldata nftIds,
        uint256[] calldata nftAmounts,
        address receiver
    ) public whenNotPaused onlyRegisteredSmartVault(smartVault) returns (uint256[] memory, uint256) {
        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        uint256 assetGroupId_ = _smartVaultAssetGroups[smartVault];
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId_);

        _syncSmartVault(smartVault, strategies_, tokens, false);
        return _withdrawalManager.claimWithdrawal(
            WithdrawalClaimBag(smartVault, nftIds, nftAmounts, receiver, msg.sender, assetGroupId_, tokens)
        );
    }

    /* ========== REGISTRY ========== */

    function registerSmartVault(address smartVault, SmartVaultRegistrationForm calldata registrationForm)
        external
        whenNotPaused
        onlyUnregisteredSmartVault(smartVault)
        onlyRole(ROLE_SMART_VAULT_INTEGRATOR, msg.sender)
    {
        // set asset group
        _smartVaultAssetGroups[smartVault] = registrationForm.assetGroupId;

        uint256 strategiesLength = registrationForm.strategies.length;

        // set strategies
        if (strategiesLength == 0) {
            revert SmartVaultRegistrationNoStrategies();
        }

        if (strategiesLength > STRATEGY_COUNT_CAP) {
            revert StrategyCapExceeded();
        }

        // validate strategies
        for (uint256 i = 0; i < strategiesLength; i++) {
            address strategy = registrationForm.strategies[i];

            if (!_accessControl.hasRole(ROLE_STRATEGY, strategy)) {
                revert InvalidStrategy(strategy);
            }

            // check that strategies use same asset group as smart vault
            if (IStrategy(strategy).assetGroupId() != registrationForm.assetGroupId) {
                revert NotSameAssetGroup();
            }

            _smartVaultsWithStrategy[strategy].push(smartVault);
        }

        // check that management fee is not too big
        if (registrationForm.managementFeePct > MANAGEMENT_FEE_MAX) {
            revert ManagementFeeTooLarge(registrationForm.managementFeePct);
        }
        // check that deposit fee is not too big
        if (registrationForm.depositFeePct > DEPOSIT_FEE_MAX) {
            revert DepositFeeTooLarge(registrationForm.depositFeePct);
        }
        // set smart vault fees
        _smartVaultFees[smartVault] = SmartVaultFees(registrationForm.managementFeePct, registrationForm.depositFeePct);

        // set strategies
        _smartVaultStrategies[smartVault] = registrationForm.strategies;

        // set allocation
        if (registrationForm.strategyAllocation.length == registrationForm.strategies.length) {
            _smartVaultAllocations[smartVault] = uint16a16.wrap(0).set(registrationForm.strategyAllocation);
        } else {
            _riskManager.setRiskProvider(smartVault, registrationForm.riskProvider);
            _riskManager.setRiskTolerance(smartVault, registrationForm.riskTolerance);
            _riskManager.setAllocationProvider(smartVault, registrationForm.allocationProvider);

            _smartVaultAllocations[smartVault] =
                _riskManager.calculateAllocation(smartVault, registrationForm.strategies);
        }

        // update registry
        _smartVaultRegistry[smartVault] = true;
    }

    function removeStrategy(address strategy) external onlyRole(ROLE_SPOOL_ADMIN, msg.sender) {
        _checkRole(ROLE_STRATEGY, strategy);

        for (uint256 i = 0; i < _smartVaultsWithStrategy[strategy].length; i++) {
            address smartVault = _smartVaultsWithStrategy[strategy][i];
            address[] memory strategies_ = _smartVaultStrategies[smartVault];
            for (uint256 j = 0; j < strategies_.length; j++) {
                if (strategies_[j] == strategy) {
                    _smartVaultStrategies[smartVault][j] = _ghostStrategy;
                    _smartVaultAllocations[smartVault] = _smartVaultAllocations[smartVault].set(j, 0);
                    break;
                }
            }
        }

        _strategyRegistry.removeStrategy(strategy);
    }

    /* ========== BOOKKEEPING ========== */

    function flushSmartVault(address smartVault) public whenNotPaused onlyRegisteredSmartVault(smartVault) {
        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);

        _flushSmartVault(smartVault, _smartVaultAllocations[smartVault], strategies_, tokens);
    }

    function syncSmartVault(address smartVault, bool revertOnMissingDHW)
        external
        whenNotPaused
        onlyRegisteredSmartVault(smartVault)
    {
        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);
        _syncSmartVault(smartVault, strategies_, tokens, revertOnMissingDHW);
    }

    function reallocate(address[] calldata smartVaults, address[] calldata strategies_) external whenNotPaused {
        // Can only be called by a reallocator.
        _checkRole(ROLE_REALLOCATOR, msg.sender);

        if (smartVaults.length == 0) {
            // Check if there is anything to reallocate.
            return;
        }

        uint256 assetGroupId_ = _smartVaultAssetGroups[smartVaults[0]];
        for (uint256 i = 0; i < smartVaults.length; ++i) {
            // Check that all smart vaults are registered.
            _onlyRegisteredSmartVault(smartVaults[i]);

            // Check that all smart vaults use the same asset group.
            if (_smartVaultAssetGroups[smartVaults[i]] != assetGroupId_) {
                revert NotSameAssetGroup();
            }

            // Check that any smart vault does not have statically set allocation.
            if (_riskManager.getRiskProvider(smartVaults[i]) == address(0)) {
                revert StaticAllocationSmartVault();
            }

            // Set new allocation.
            _smartVaultAllocations[smartVaults[i]] =
                _riskManager.calculateAllocation(smartVaults[i], _smartVaultStrategies[smartVaults[i]]);
        }

        ReallocationBag memory reallocationBag = ReallocationBag({
            assetGroupRegistry: _assetGroupRegistry,
            priceFeedManager: _priceFeedManager,
            masterWallet: _masterWallet,
            assetGroupId: assetGroupId_
        });

        // Do the reallocation.
        ReallocationLib.reallocate(
            smartVaults, strategies_, reallocationBag, _smartVaultStrategies, _smartVaultAllocations
        );
    }

    /* ========== PRIVATE/INTERNAL FUNCTIONS ========== */

    /**
     * @dev Claim strategy shares, account for withdrawn assets and sync SVTs for all new DHW runs
     */
    function _syncSmartVault(
        address smartVault,
        address[] memory strategies_,
        address[] memory tokens,
        bool revertIfError
    ) private {
        // TODO: sync yields
        VaultSyncBag memory bag;
        bag.flushIndex = _flushIndexesToSync[smartVault];

        if (bag.flushIndex == _flushIndexes[smartVault]) {
            if (revertIfError) {
                revert NothingToSync();
            }

            return;
        }

        bag.currentStrategyIndexes = _strategyRegistry.currentIndex(strategies_);
        bag.vaultOwner = _accessControl.smartVaultOwner(smartVault);
        bag.oldTotalSVTs = ISmartVault(smartVault).totalSupply() - ISmartVault(smartVault).balanceOf(bag.vaultOwner);
        bag.lastDhwSynced = _lastDhwTimestampSynced[smartVault];
        SmartVaultFees memory fees = _smartVaultFees[smartVault];

        while (bag.flushIndex < _flushIndexes[smartVault]) {
            uint16a16 indexes = _dhwIndexes[smartVault][bag.flushIndex];
            if (!_areAllDhwRunsCompleted(bag.currentStrategyIndexes, indexes, strategies_, revertIfError)) break;

            _withdrawalManager.syncWithdrawals(smartVault, bag.flushIndex, strategies_, indexes);
            DepositSyncResult memory syncResult = _depositManager.syncDeposits(
                smartVault, bag.flushIndex, bag.lastDhwSynced, bag.oldTotalSVTs, strategies_, indexes, tokens, fees
            );

            bag.newSVTs += syncResult.mintedSVTs;
            bag.feeSVTs += syncResult.feeSVTs;
            bag.oldTotalSVTs += bag.newSVTs;
            bag.lastDhwSynced = syncResult.dhwTimestamp;

            emit SmartVaultSynced(smartVault, bag.flushIndex);
            bag.flushIndex++;
        }

        if (bag.newSVTs > 0) {
            ISmartVault(smartVault).mint(smartVault, bag.newSVTs);
        }

        if (bag.feeSVTs > 0) {
            ISmartVault(smartVault).mint(bag.vaultOwner, bag.feeSVTs);
        }

        _lastDhwTimestampSynced[smartVault] = bag.lastDhwSynced;
        _flushIndexesToSync[smartVault] = bag.flushIndex;
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
        for (uint256 i; i < strategies_.length; i++) {
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
     */
    function _simulateSync(address smartVault)
        private
        view
        returns (uint256 currentSupply, uint256 vaultOwnerSVTs, uint256 mintedSVTs, uint256 feeSVTs)
    {
        VaultSyncBag memory bag;

        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);
        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        bag.currentStrategyIndexes = _strategyRegistry.currentIndex(strategies_);
        bag.lastDhwSynced = _lastDhwTimestampSynced[smartVault];
        bag.flushIndex = _flushIndexesToSync[smartVault];
        bag.vaultOwner = _accessControl.smartVaultOwner(smartVault);
        vaultOwnerSVTs = ISmartVault(smartVault).balanceOf(bag.vaultOwner);
        bag.oldTotalSVTs = ISmartVault(smartVault).totalSupply() - vaultOwnerSVTs;
        SmartVaultFees memory fees = _smartVaultFees[smartVault];

        while (bag.flushIndex < _flushIndexes[smartVault]) {
            uint16a16 indexes = _dhwIndexes[smartVault][bag.flushIndex];

            if (!_areAllDhwRunsCompleted(bag.currentStrategyIndexes, indexes, strategies_, false)) break;

            DepositSyncResult memory syncResult = _depositManager.syncDepositsSimulate(
                smartVault,
                bag.flushIndex,
                bag.lastDhwSynced,
                bag.oldTotalSVTs + bag.newSVTs,
                strategies_,
                tokens,
                indexes,
                fees
            );

            bag.newSVTs += syncResult.mintedSVTs;
            bag.feeSVTs += syncResult.feeSVTs;

            bag.lastDhwSynced = syncResult.dhwTimestamp;
            bag.flushIndex++;
        }

        return (bag.oldTotalSVTs, vaultOwnerSVTs, bag.newSVTs, bag.feeSVTs);
    }

    /**
     * @dev Calculate how many SVTs a user would receive, if he were to burn his NFTs.
     * For NFTs that are part of a vault flush that haven't been synced yet, simulate vault sync.
     * We have to simulate sync in correct order, to calculate management fees.
     */
    function _simulateNFTBurn(address smartVault, address userAddress, uint256[] memory nftIds)
        private
        view
        returns (uint256)
    {
        VaultSyncBag memory bag;
        VaultSyncUserBag memory bag2;
        uint256 newBalance;

        ISmartVault vault = ISmartVault(smartVault);
        bag2.metadata = vault.getMetadata(nftIds);
        bag2.nftBalances = vault.balanceOfFractionalBatch(userAddress, nftIds);
        bag.flushIndex = _flushIndexesToSync[smartVault];
        bag2.tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);

        // check if any have already been synced
        for (uint256 i = 0; i < nftIds.length; i++) {
            DepositMetadata memory data = abi.decode(bag2.metadata[i], (DepositMetadata));
            if (data.flushIndex >= bag.flushIndex) {
                continue;
            }

            newBalance +=
                _depositManager.getClaimedVaultTokensPreview(smartVault, data, bag2.nftBalances[i], 0, bag2.tokens);
        }

        if (bag.flushIndex == _flushIndexes[smartVault]) {
            // Everything has been synced already.
            return newBalance;
        }

        SmartVaultFees memory fees = _smartVaultFees[smartVault];
        bag2.strategies = _smartVaultStrategies[smartVault];
        bag.currentStrategyIndexes = _strategyRegistry.currentIndex(bag2.strategies);
        bag.lastDhwSynced = _lastDhwTimestampSynced[smartVault];
        bag.oldTotalSVTs = ISmartVault(smartVault).totalSupply()
            - ISmartVault(smartVault).balanceOf(_accessControl.smartVaultOwner(smartVault));

        while (bag.flushIndex < _flushIndexes[smartVault]) {
            uint16a16 indexes = _dhwIndexes[smartVault][bag.flushIndex];
            if (!_areAllDhwRunsCompleted(bag.currentStrategyIndexes, indexes, bag2.strategies, false)) break;

            DepositSyncResult memory syncResult = _depositManager.syncDepositsSimulate(
                smartVault,
                bag.flushIndex,
                bag.lastDhwSynced,
                bag.oldTotalSVTs + bag.newSVTs,
                bag2.strategies,
                bag2.tokens,
                indexes,
                fees
            );

            bag.newSVTs += syncResult.mintedSVTs;
            bag.lastDhwSynced = syncResult.dhwTimestamp;

            // if any NFTs are part of this flush cycle, simulate burn
            for (uint256 i = 0; i < nftIds.length; i++) {
                DepositMetadata memory data = abi.decode(bag2.metadata[i], (DepositMetadata));
                if (data.flushIndex != bag.flushIndex) {
                    continue;
                }

                newBalance += _depositManager.getClaimedVaultTokensPreview(
                    smartVault, data, bag2.nftBalances[i], syncResult.mintedSVTs, bag2.tokens
                );
            }

            bag.flushIndex++;
        }

        return newBalance;
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

        (uint256[] memory deposits, uint256 depositId) = _depositManager.depositAssets(
            bag,
            DepositExtras({
                depositor: msg.sender,
                tokens: tokens,
                allocations: allocations_,
                strategies: strategies_,
                flushIndex: _flushIndexes[bag.smartVault]
            })
        );

        for (uint256 i = 0; i < deposits.length; i++) {
            IERC20(tokens[i]).safeTransferFrom(msg.sender, address(_masterWallet), deposits[i]);
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
        uint256 flushIndex = _flushIndexes[smartVault];
        uint16a16 flushDhwIndexes =
            _depositManager.flushSmartVault(smartVault, flushIndex, strategies_, allocations_, tokens);

        uint16a16 flushDhwIndexes2 = _withdrawalManager.flushSmartVault(smartVault, flushIndex, strategies_);

        if (uint16a16.unwrap(flushDhwIndexes2) > 0) {
            flushDhwIndexes = flushDhwIndexes2;
        }

        if (uint16a16.unwrap(flushDhwIndexes) == 0) revert NothingToFlush();

        uint16a16 currentFlushDhwIndexes = _dhwIndexes[smartVault][flushIndex];

        for (uint256 i = 0; i < strategies_.length; i++) {
            if (strategies_[i] == _ghostStrategy) continue;

            for (uint256 j = 0; j < strategies_.length; j++) {
                if (flushDhwIndexes.get(i) == currentFlushDhwIndexes.get(i)) {
                    revert FlushOverlap(strategies_[i]);
                }
            }
        }

        _dhwIndexes[smartVault][flushIndex] = flushDhwIndexes;
        _flushIndexes[smartVault] = flushIndex + 1;

        emit SmartVaultFlushed(smartVault, flushIndex);
    }

    function _onlyUnregisteredSmartVault(address smartVault) internal view {
        if (_smartVaultRegistry[smartVault]) {
            revert SmartVaultAlreadyRegistered();
        }
    }

    function _onlyRegisteredSmartVault(address smartVault) internal view {
        if (!_smartVaultRegistry[smartVault]) {
            revert SmartVaultNotRegisteredYet();
        }
    }

    /* ========== MODIFIERS ========== */

    modifier onlyUnregisteredSmartVault(address smartVault) {
        _onlyUnregisteredSmartVault(smartVault);
        _;
    }

    modifier onlyRegisteredSmartVault(address smartVault) {
        _onlyRegisteredSmartVault(smartVault);
        _;
    }
}
