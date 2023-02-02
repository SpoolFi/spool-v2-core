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
import "../libraries/SpoolUtils.sol";
import "../access/SpoolAccessControl.sol";
import "../interfaces/ISmartVaultManager.sol";
import "../interfaces/IDepositManager.sol";
import "../interfaces/IWithdrawalManager.sol";
import "../interfaces/IWithdrawalManager.sol";
import "../interfaces/IRewardManager.sol";
import "../interfaces/Constants.sol";

/**
 * @dev Requires roles:
 * - ROLE_STRATEGY_CLAIMER
 * - ROLE_MASTER_WALLET_MANAGER
 * - ROLE_SMART_VAULT_MANAGER
 */
contract SmartVaultManager is ISmartVaultManager, SpoolAccessControllable {
    /* ========== CONSTANTS ========== */

    using SafeERC20 for IERC20;
    using ArrayMapping for mapping(uint256 => uint256);

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

    /* ========== STATE VARIABLES ========== */

    /// @notice Smart Vault registry
    mapping(address => bool) internal _smartVaultRegistry;

    /// @notice Smart Vault - asset group ID registry
    mapping(address => uint256) internal _smartVaultAssetGroups;

    /// @notice Smart Vault strategy registry
    mapping(address => address[]) internal _smartVaultStrategies;

    /// @notice Smart Vault risk provider registry
    mapping(address => address) internal _smartVaultRiskProviders;

    /**
     * @notice Risk appetite for given Smart Vault.
     * @dev smart vault => risk appetite
     */
    mapping(address => uint256) internal _smartVaultRiskAppetite;

    /// @notice Smart vault management fee percentage
    mapping(address => uint256) internal _smartVaultMgmtFeePct;

    /// @notice Smart Vault strategy allocations
    mapping(address => mapping(uint256 => uint256)) internal _smartVaultAllocations;

    /// @notice Smart Vault tolerance registry
    mapping(address => int256) internal _riskTolerances;

    /// @notice Current flush index for given Smart Vault
    mapping(address => uint256) internal _flushIndexes;

    /// @notice First flush index that still needs to be synced for given Smart Vault.
    mapping(address => uint256) internal _flushIndexesToSync;

    /**
     * @notice DHW indexes for given Smart Vault and flush index
     * @dev smart vault => flush index => DHW indexes
     */
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _dhwIndexes;

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
        IMasterWallet masterWallet_
    ) SpoolAccessControllable(accessControl_) {
        _assetGroupRegistry = assetGroupRegistry_;
        _riskManager = riskManager_;
        _depositManager = depositManager_;
        _withdrawalManager = withdrawalManager_;
        _strategyRegistry = strategyRegistry_;
        _masterWallet = masterWallet_;
    }

    /* ========== VIEW FUNCTIONS ========== */
    /**
     * @notice Retrieves a Smart Vault Token Balance for user. Including the predicted balance from all current D-NFTs
     * currently in holding.
     */
    function getUserSVTBalance(address smartVaultAddress, address userAddress) external view returns (uint256) {
        ISmartVault smartVault = ISmartVault(smartVaultAddress);
        uint256 currentBalance = smartVault.balanceOf(userAddress);
        uint256[] memory nftIds = smartVault.activeUserNFTIds(userAddress);

        if (nftIds.length > 0) {
            currentBalance += _simulateDepositNFTBurn(smartVault, userAddress, nftIds);
        }

        return currentBalance;
    }

    function getSVTTotalSupply(address smartVault) external view returns (uint256) {
        return _totalSVTs(smartVault);
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
    function allocations(address smartVault) external view returns (uint256[] memory) {
        return _smartVaultAllocations[smartVault].toArray(_smartVaultStrategies[smartVault].length);
    }

    /**
     * @notice SmartVault risk provider
     */
    function riskProvider(address smartVault) external view returns (address) {
        return _smartVaultRiskProviders[smartVault];
    }

    /**
     * @notice SmartVault risk tolerance
     */
    function riskTolerance(address smartVault) external view returns (int256) {
        return _riskTolerances[smartVault];
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
     * @notice Smart vault deposits for given flush index.
     */
    function smartVaultDeposits(address smartVault, uint256 flushIdx) external view returns (uint256[] memory) {
        uint256 assetGroupLength = _assetGroupRegistry.assetGroupLength(_smartVaultAssetGroups[smartVault]);
        return _depositManager.smartVaultDeposits(smartVault, flushIdx, assetGroupLength);
    }

    /**
     * @notice DHW indexes that were active at given flush index
     */
    function dhwIndexes(address smartVault, uint256 flushIndex) external view returns (uint256[] memory) {
        uint256 strategyCount = _smartVaultStrategies[smartVault].length;
        return _dhwIndexes[smartVault][flushIndex].toArray(strategyCount);
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
        onlyRole(ROLE_RISK_PROVIDER, registrationForm.riskProvider)
    {
        // TODO: should check if same asset group on strategies and smart vault

        // set asset group
        _smartVaultAssetGroups[smartVault] = registrationForm.assetGroupId;

        // set strategies
        if (registrationForm.strategies.length == 0) {
            revert SmartVaultRegistrationNoStrategies();
        }

        for (uint256 i = 0; i < registrationForm.strategies.length; i++) {
            address strategy = registrationForm.strategies[i];
            if (!_strategyRegistry.isStrategy(strategy)) {
                revert InvalidStrategy(strategy);
            }
        }

        if (registrationForm.managementFeePct > MANAGEMENT_FEE_MAX) {
            revert ManagementFeeTooLarge(registrationForm.managementFeePct);
        }

        _smartVaultMgmtFeePct[smartVault] = registrationForm.managementFeePct;
        _smartVaultStrategies[smartVault] = registrationForm.strategies;
        _smartVaultRiskProviders[smartVault] = registrationForm.riskProvider;

        // set allocation
        _smartVaultAllocations[smartVault].setValues(
            _riskManager.calculateAllocation(
                registrationForm.riskProvider, registrationForm.strategies, registrationForm.riskAppetite
            )
        );

        // update registry
        _smartVaultRegistry[smartVault] = true;
    }

    /**
     * @notice TODO
     */
    function setRiskProvider(address smartVault, address riskProvider_)
        external
        onlyRole(ROLE_RISK_PROVIDER, riskProvider_)
    {
        _smartVaultRiskProviders[smartVault] = riskProvider_;
        emit RiskProviderSet(smartVault, riskProvider_);
    }

    /* ========== BOOKKEEPING ========== */

    function flushSmartVault(address smartVault) public whenNotPaused onlyRegisteredSmartVault(smartVault) {
        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        uint256[] memory allocations_ = _smartVaultAllocations[smartVault].toArray(strategies_.length);
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);

        _flushSmartVault(smartVault, allocations_, strategies_, tokens);
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

    /**
     * @notice TODO
     */
    function reallocate() external {}

    /* ========== PRIVATE/INTERNAL FUNCTIONS ========== */

    /**
     * @dev Claim strategy shares, account for withdrawn assets and sync SVTs for all new DHW runs
     */
    function _syncSmartVault(
        address smartVault,
        address[] memory strategies_,
        address[] memory tokens,
        bool revertOnMissingDHW
    ) private {
        // TODO: sync yields

        // NOTE: warning "This declaration has the same name as another declaration."
        uint256[] memory currentStrategyIndexes = _strategyRegistry.currentIndex(strategies_);
        uint256 flushIndex = _flushIndexesToSync[smartVault];
        uint256 mgmtFeeSVTs;
        DepositSyncResult memory syncResult;
        address vaultOwner = _accessControl.smartVaultOwner(smartVault);
        uint256 totalSVTs = ISmartVault(smartVault).totalSupply() - ISmartVault(smartVault).balanceOf(vaultOwner);
        uint256 mgmtFeePct = _smartVaultMgmtFeePct[smartVault];
        uint256[] memory indexes;

        while (flushIndex < _flushIndexes[smartVault]) {
            indexes = _dhwIndexes[smartVault][flushIndex].toArray(strategies_.length);

            {
                (bool dhwOk, uint256 idx) = _areAllDhwRunsCompleted(currentStrategyIndexes, indexes);
                if (!dhwOk) {
                    if (revertOnMissingDHW) {
                        revert DhwNotRunYetForIndex(strategies_[idx], indexes[idx]);
                    } else {
                        return;
                    }
                }
            }

            _withdrawalManager.syncWithdrawals(smartVault, flushIndex, strategies_, indexes);
            syncResult = _depositManager.syncDeposits(smartVault, flushIndex, strategies_, indexes, tokens);

            uint256 lastSyncedDhw = _lastDhwTimestampSynced[smartVault];

            if (mgmtFeePct > 0) {
                mgmtFeeSVTs +=
                    _calculateManagementFees(lastSyncedDhw, syncResult.lastDhwTimestamp, totalSVTs, mgmtFeePct);
            }

            totalSVTs += syncResult.mintedSVTs;
            _lastDhwTimestampSynced[smartVault] = syncResult.lastDhwTimestamp;

            emit SmartVaultSynced(smartVault, flushIndex);

            flushIndex++;
            _flushIndexesToSync[smartVault] = flushIndex;
        }

        if (mgmtFeeSVTs > 0) {
            ISmartVault(smartVault).mint(vaultOwner, mgmtFeeSVTs);
        }
    }

    /**
     * @dev Calculated as percentage of assets under management, distributed throughout a year.
     * SVT amount being diluted should not include previously distributed management fees.
     * @param timeFrom time from which to collect fees
     * @param timeTo time to which to collect fees
     * @param totalSVTs SVT amount basis on which to apply fees
     * @param mgmtFeePct management fee percentage value
     */
    function _calculateManagementFees(uint256 timeFrom, uint256 timeTo, uint256 totalSVTs, uint256 mgmtFeePct)
        private
        pure
        returns (uint256)
    {
        uint256 timeDelta = timeTo - timeFrom;
        return totalSVTs * mgmtFeePct * timeDelta / SECONDS_IN_YEAR / FULL_PERCENT;
    }

    /**
     * @dev Simulate how many SVTs would a user receive by burning given deposit NFTs
     * - Withdrawal NFTs are skipped
     * - Incomplete DHW runs are skipped
     * - Incomplete vault syncs will be simulated
     */
    function _simulateDepositNFTBurn(ISmartVault smartVault, address userAddress, uint256[] memory nftIds)
        private
        view
        returns (uint256)
    {
        uint256 balance;
        address smartVaultAddress = address(smartVault);
        bytes[] memory metadata = smartVault.getMetadata(nftIds);
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVaultAddress]);
        address[] memory strategies_ = _smartVaultStrategies[smartVaultAddress];
        uint256[] memory nftBalances = smartVault.balanceOfFractionalBatch(userAddress, nftIds);
        uint256[] memory currentStrategyIndexes = _strategyRegistry.currentIndex(strategies_);

        for (uint256 i; i < nftIds.length; i++) {
            if (nftIds[i] > MAXIMAL_DEPOSIT_ID) continue;

            DepositMetadata memory depositMetadata = abi.decode(metadata[i], (DepositMetadata));
            uint256[] memory dhwIndexes_ =
                _dhwIndexes[smartVaultAddress][depositMetadata.flushIndex].toArray(strategies_.length);

            (bool dhwOk,) = _areAllDhwRunsCompleted(currentStrategyIndexes, dhwIndexes_);
            if (!dhwOk) continue;

            balance += _depositManager.getClaimedVaultTokensPreview(
                smartVaultAddress, depositMetadata, nftBalances[i], tokens, strategies_, dhwIndexes_, true
            );
        }
        return balance;
    }

    /**
     * @dev Check whether all DHW runs were completed for given indexes
     */
    function _areAllDhwRunsCompleted(uint256[] memory currentStrategyIndexes, uint256[] memory dhwIndexes_)
        private
        pure
        returns (bool, uint256)
    {
        for (uint256 i; i < dhwIndexes_.length; i++) {
            if (dhwIndexes_[i] >= currentStrategyIndexes[i]) {
                return (false, i);
            }
        }

        return (true, 0);
    }

    /**
     * @dev Calculate number of SVTs that haven't been synced yet after DHW runs
     * DHW has minted strategy shares, but vaults haven't claimed them yet.
     * Includes management fees (percentage of assets under management, distributed throughout a year) .
     */
    function _totalSVTs(address smartVault) private view returns (uint256) {
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);
        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        uint256[] memory currentStrategyIndexes = _strategyRegistry.currentIndex(strategies_);
        uint256 flushIndex = _flushIndexesToSync[smartVault];
        uint256 lastDhwSyncedTimestamp;
        uint256 mgmtFeeSVTs;
        uint256 vaultOwnerSVTs = ISmartVault(smartVault).balanceOf(_accessControl.smartVaultOwner(smartVault));
        uint256 totalSVTs = ISmartVault(smartVault).totalSupply() - vaultOwnerSVTs;
        uint256 mgmtFeePct = _smartVaultMgmtFeePct[smartVault];

        StrategyAtIndex[] memory dhwStates;

        while (flushIndex < _flushIndexes[smartVault]) {
            {
                uint256[] memory indexes = _dhwIndexes[smartVault][flushIndex].toArray(strategies_.length);
                (bool dhwOk,) = _areAllDhwRunsCompleted(currentStrategyIndexes, indexes);
                if (!dhwOk) break;

                dhwStates = _strategyRegistry.strategyAtIndexBatch(strategies_, indexes);
            }

            DepositSyncResult memory syncResult =
                _depositManager.syncDepositsSimulate(smartVault, flushIndex, strategies_, tokens, dhwStates);

            if (mgmtFeePct > 0) {
                mgmtFeeSVTs +=
                    _calculateManagementFees(lastDhwSyncedTimestamp, syncResult.lastDhwTimestamp, totalSVTs, mgmtFeePct);
            }

            totalSVTs += syncResult.mintedSVTs;

            lastDhwSyncedTimestamp = syncResult.lastDhwTimestamp;
            flushIndex++;
        }

        return totalSVTs + mgmtFeeSVTs + vaultOwnerSVTs;
    }

    /**
     * @dev Gets total value (in USD) of assets managed by the vault.
     */
    function _getVaultTotalUsdValue(address smartVault) internal view returns (uint256) {
        return SpoolUtils.getVaultTotalUsdValue(smartVault, _smartVaultStrategies[smartVault]);
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
        uint256[] memory allocations_ = _smartVaultAllocations[bag.smartVault].toArray(strategies_.length);

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
        uint256[] memory allocations_,
        address[] memory strategies_,
        address[] memory tokens
    ) private {
        uint256 flushIndex = _flushIndexes[smartVault];
        uint256[] memory flushDhwIndexes =
            _depositManager.flushSmartVault(smartVault, flushIndex, strategies_, allocations_, tokens);

        uint256[] memory flushDhwIndexes2 = _withdrawalManager.flushSmartVault(smartVault, flushIndex, strategies_);
        if (flushDhwIndexes.length == 0) {
            flushDhwIndexes = flushDhwIndexes2;
        }

        if (flushDhwIndexes.length == 0) {
            revert NothingToFlush();
        }

        _dhwIndexes[smartVault][flushIndex].setValues(flushDhwIndexes);
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
