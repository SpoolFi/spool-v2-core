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
import "../libraries/SmartVaultDeposits.sol";
import "../access/SpoolAccessControl.sol";
import "../interfaces/ISmartVaultManager.sol";

contract SmartVaultManager is ISmartVaultManager, SpoolAccessControllable {
    using SafeERC20 for IERC20;
    using ArrayMapping for mapping(uint256 => uint256);

    /* ========== CONSTANTS ========== */

    uint256 internal constant INITIAL_SHARE_MULTIPLIER = 1000000000000000000000000000000; // 10 ** 30

    // @notice Guard manager
    IGuardManager internal immutable _guardManager;

    // @notice Action manager
    IActionManager internal immutable _actionManager;

    /// @notice Strategy registry
    IStrategyRegistry private immutable _strategyRegistry;

    /// @notice Price Feed Manager
    IUsdPriceFeedManager private immutable _priceFeedManager;

    /// @notice Asset Group registry
    IAssetGroupRegistry private immutable _assetGroupRegistry;

    /// @notice Master wallet
    IMasterWallet private immutable _masterWallet;

    /// @notice Risk manager.
    IRiskManager private immutable _riskManager;

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
     * @notice Vault deposits at given flush index
     * @dev smart vault => flush index => assets deposited
     */
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _vaultDeposits;

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
     * @notice Withdrawn vault shares at given flush index
     * @dev smart vault => flush index => vault shares withdrawn
     */
    mapping(address => mapping(uint256 => uint256)) internal _withdrawnVaultShares;

    /**
     * @notice Withdrawn strategy shares for vault, at given flush index
     * @dev smart vault => flush index => strategy shares withdrawn
     */
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _withdrawnStrategyShares;

    /**
     * @notice Withdrawn assets for vault, at given flush index
     * @dev smart vault => flush index => assets withdrawn
     */
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _withdrawnAssets;

    /**
     * @notice Exchange rates for vault, at given flush index
     * @dev smart vault => flush index => exchange rates
     */
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _flushExchangeRates;

    constructor(
        ISpoolAccessControl accessControl_,
        IStrategyRegistry strategyRegistry_,
        IUsdPriceFeedManager priceFeedManager_,
        IAssetGroupRegistry assetGroupRegistry_,
        IMasterWallet masterWallet_,
        IActionManager actionManager_,
        IGuardManager guardManager_,
        IRiskManager riskManager_
    ) SpoolAccessControllable(accessControl_) {
        _strategyRegistry = strategyRegistry_;
        _priceFeedManager = priceFeedManager_;
        _assetGroupRegistry = assetGroupRegistry_;
        _masterWallet = masterWallet_;
        _actionManager = actionManager_;
        _guardManager = guardManager_;
        _riskManager = riskManager_;
    }

    /* ========== VIEW FUNCTIONS ========== */
    /**
     * @notice Retrieves a Smart Vault Token Balance for user. Including the predicted balance from all current D-NFTs
     * currently in holding.
     */
    function getUserSVTBalance(address smartVaultAddress, address userAddress) external view returns (uint256) {
        ISmartVault smartVault = ISmartVault(smartVaultAddress);
        uint256 currentBalance = smartVault.balanceOf(userAddress);
        uint256[] memory nftIDs = smartVault.activeUserNFTIds(userAddress);
        bytes[] memory metadata = smartVault.getMetadata(nftIDs);

        uint256[] memory balances = smartVault.balanceOfBatch(userAddress, nftIDs);

        for (uint256 i; i < nftIDs.length; i++) {
            if (nftIDs[i] > MAXIMAL_DEPOSIT_ID) {
                continue;
            }

            DepositMetadata memory depositMetadata = abi.decode(metadata[i], (DepositMetadata));
            uint256 balance = _getClaimedVaultTokensPreview(smartVaultAddress, depositMetadata, balances[i]);
            currentBalance += balance;
        }

        return currentBalance;
    }

    function _getClaimedVaultTokensPreview(address smartVaultAddress, DepositMetadata memory data, uint256 nftShares)
        private
        view
        returns (uint256)
    {
        if (data.flushIndex >= _flushIndexesToSync[smartVaultAddress]) {
            revert DepositNotSyncedYet();
        }

        uint256 depositedUsd;
        uint256 totalDepositedUsd;
        {
            address[] memory assets = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVaultAddress]);
            uint256[] memory totalDepositedAssets =
                _vaultDeposits[smartVaultAddress][data.flushIndex].toArray(data.assets.length);
            uint256[] memory exchangeRates =
                _flushExchangeRates[smartVaultAddress][data.flushIndex].toArray(data.assets.length);

            for (uint256 i = 0; i < data.assets.length; i++) {
                depositedUsd += _priceFeedManager.assetToUsdCustomPrice(assets[i], data.assets[i], exchangeRates[i]);
                totalDepositedUsd +=
                    _priceFeedManager.assetToUsdCustomPrice(assets[i], totalDepositedAssets[i], exchangeRates[i]);
            }
        }
        uint256 claimedVaultTokens =
            Math.mulDiv(_mintedVaultShares[smartVaultAddress][data.flushIndex], depositedUsd, totalDepositedUsd);

        // TODO: dust
        return Math.mulDiv(claimedVaultTokens, nftShares, NFT_MINTED_SHARES);
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
        return _vaultDeposits[smartVault][flushIdx].toArray(assetGroupLength);
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

    function redeem(address smartVault, uint256 shares, address receiver, address owner)
        external
        onlyRegisteredSmartVault(smartVault)
        returns (uint256)
    {
        return _redeemShares(smartVault, shares, receiver, owner);
    }

    function redeemFast(address smartVault, uint256 shares)
        external
        onlyRegisteredSmartVault(smartVault)
        returns (uint256[] memory)
    {
        if (ISmartVault(smartVault).balanceOf(msg.sender) < shares) {
            revert InsufficientBalance(ISmartVault(smartVault).balanceOf(msg.sender), shares);
        }

        {
            // run guards
            uint256[] memory assets = new uint256[](1);
            assets[0] = shares;
            address[] memory tokens = new address[](1);
            tokens[0] = smartVault;
            _runGuards(smartVault, msg.sender, msg.sender, msg.sender, assets, tokens, RequestType.Withdrawal);
        }

        // figure out how much to redeem from each strategy
        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        uint256[] memory strategySharesToRedeem = new uint256[](strategies_.length);
        {
            uint256 totalVaultShares = ISmartVault(smartVault).totalSupply();
            for (uint256 i = 0; i < strategies_.length; i++) {
                uint256 strategyShares = IStrategy(strategies_[i]).balanceOf(smartVault);

                strategySharesToRedeem[i] = strategyShares * shares / totalVaultShares;
            }
        }

        // redeem from strategies and burn
        ISmartVault(smartVault).burn(msg.sender, shares, strategies_, strategySharesToRedeem);
        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);
        uint256[] memory assetsWithdrawn = _strategyRegistry.redeemFast(strategies_, strategySharesToRedeem, assetGroup);

        // transfer assets to the redeemer
        for (uint256 i = 0; i < assetGroup.length; i++) {
            _masterWallet.transfer(IERC20(assetGroup[i]), msg.sender, assetsWithdrawn[i]);
        }

        return assetsWithdrawn;
    }

    // TODO: unused parameter
    function depositFor(address smartVault, uint256[] calldata assets, address receiver, address depositor, address)
        external
        onlyRegisteredSmartVault(smartVault)
        returns (uint256)
    {
        return _depositAssets(smartVault, depositor, receiver, assets);
    }

    // TODO: unused parameter
    function deposit(address smartVault, uint256[] calldata assets, address receiver, address)
        external
        onlyRegisteredSmartVault(smartVault)
        returns (uint256)
    {
        return _depositAssets(smartVault, msg.sender, receiver, assets);
    }

    /**
     * @notice Burn deposit NFTs to claim SVTs
     * @param smartVault Vault address
     * @param nftIDs NFTs to burn
     * @param nftAmounts NFT amounts to burn
     */
    function claimSmartVaultTokens(address smartVault, uint256[] calldata nftIDs, uint256[] calldata nftAmounts)
        public
        onlyRegisteredSmartVault(smartVault)
        returns (uint256)
    {
        ISmartVault vault = ISmartVault(smartVault);
        bytes[] memory metadata = vault.burnNFTs(msg.sender, nftIDs, nftAmounts);

        uint256 claimedVaultTokens = 0;
        for (uint256 i = 0; i < nftIDs.length; i++) {
            claimedVaultTokens +=
                _getClaimedVaultTokensPreview(smartVault, abi.decode(metadata[i], (DepositMetadata)), nftAmounts[i]);
        }

        // there will be some dust after all users claim SVTs
        vault.claimShares(msg.sender, claimedVaultTokens);

        return claimedVaultTokens;
    }

    /**
     * @notice Burn withdrawal NFTs to claim assets
     * @param smartVault Vault address
     * @param nftIDs NFTs to burn
     * @param nftAmounts NFT amounts to burn
     * @param receiver Address to which to transfer claimed assets
     */
    function claimWithdrawal(
        address smartVault,
        uint256[] calldata nftIDs,
        uint256[] calldata nftAmounts,
        address receiver
    ) public onlyRegisteredSmartVault(smartVault) returns (uint256[] memory, uint256) {
        uint256 assetGroupID = _smartVaultAssetGroups[smartVault];
        bytes[] memory metadata = ISmartVault(smartVault).burnNFTs(msg.sender, nftIDs, nftAmounts);
        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupID);
        uint256[] memory withdrawnAssets = new uint256[](assetGroup.length);

        for (uint256 i = 0; i < nftIDs.length; i++) {
            uint256[] memory withdrawnAssets_ =
                _calculateWithdrawal(smartVault, abi.decode(metadata[i], (WithdrawalMetadata)), assetGroup.length);
            for (uint256 j = 0; j < assetGroup.length; j++) {
                withdrawnAssets[j] += Math.mulDiv(withdrawnAssets_[j], nftAmounts[i], NFT_MINTED_SHARES);
            }
        }

        _runActions(smartVault, msg.sender, receiver, msg.sender, withdrawnAssets, assetGroup, RequestType.Withdrawal);

        for (uint256 i = 0; i < assetGroup.length; i++) {
            // TODO-Q: should this be done by an action, since there might be a swap?
            _masterWallet.transfer(IERC20(assetGroup[i]), receiver, withdrawnAssets[i]);
        }

        return (withdrawnAssets, assetGroupID);
    }

    /* ========== REGISTRY ========== */

    function registerSmartVault(address smartVault, SmartVaultRegistrationForm calldata registrationForm)
        external
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

        _smartVaultStrategies[smartVault] = registrationForm.strategies;

        // set risk provider
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
    }

    /* ========== BOOKKEEPING ========== */

    function flushSmartVault(address smartVault) external onlyRegisteredSmartVault(smartVault) {
        uint256 flushIndex = _flushIndexes[smartVault];
        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        uint256[] memory flushDhwIndexes;

        if (_vaultDeposits[smartVault][flushIndex][0] > 0) {
            // handle deposits
            address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);
            uint256[] memory exchangeRates = SpoolUtils.getExchangeRates(tokens, _priceFeedManager);
            uint256[] memory deposits = _vaultDeposits[smartVault][flushIndex].toArray(tokens.length);
            uint256[] memory allocation = _smartVaultAllocations[smartVault].toArray(strategies_.length);

            _flushExchangeRates[smartVault][flushIndex].setValues(exchangeRates);

            uint256[][] memory distribution = SmartVaultDeposits.distributeDeposit(
                DepositQueryBag1({
                    deposit: deposits,
                    exchangeRates: exchangeRates,
                    allocation: allocation,
                    strategyRatios: SpoolUtils.getStrategyRatiosAtLastDhw(strategies_, _strategyRegistry)
                })
            );
            flushDhwIndexes = _strategyRegistry.addDeposits(strategies_, distribution);

            for (uint256 i = 0; i < strategies_.length; i++) {
                _vaultFlushedDeposits[smartVault][flushIndex][strategies_[i]].setValues(distribution[i]);
            }
        }

        uint256 withdrawals = _withdrawnVaultShares[smartVault][flushIndex];

        if (withdrawals > 0) {
            // handle withdrawals
            uint256[] memory strategyWithdrawals = new uint256[](strategies_.length);

            for (uint256 i = 0; i < strategies_.length; i++) {
                uint256 strategyShares = IStrategy(strategies_[i]).balanceOf(smartVault);
                uint256 totalVaultShares = ISmartVault(smartVault).totalSupply();

                strategyWithdrawals[i] = strategyShares * withdrawals / totalVaultShares;
            }

            ISmartVault(smartVault).burn(smartVault, withdrawals, strategies_, strategyWithdrawals);
            flushDhwIndexes = _strategyRegistry.addWithdrawals(strategies_, strategyWithdrawals);

            _withdrawnStrategyShares[smartVault][flushIndex].setValues(strategyWithdrawals);
        }

        if (flushDhwIndexes.length == 0) revert NothingToFlush();

        _dhwIndexes[smartVault][flushIndex].setValues(flushDhwIndexes);
        _flushIndexes[smartVault] = flushIndex + 1;

        emit SmartVaultFlushed(smartVault, flushIndex);
    }

    function syncSmartVault(address smartVault) external {
        // TODO: sync yields
        // TODO: sync deposits

        address[] memory strategies_ = _smartVaultStrategies[smartVault];

        uint256 flushIndex = _flushIndexesToSync[smartVault];
        while (flushIndex < _flushIndexes[smartVault]) {
            // TODO: Check if all DHW indexes were processed for given flushIndex (here, not down the stack)

            uint256[] memory indexes = _dhwIndexes[smartVault][flushIndex].toArray(strategies_.length);

            for (uint256 i = 0; i < strategies_.length; i++) {
                uint256 dhwIndex = indexes[i];

                if (dhwIndex == _strategyRegistry.currentIndex(strategies_[i])) {
                    revert DhwNotRunYetForIndex(strategies_[i], dhwIndex);
                }
            }

            _syncWithdrawals(smartVault, flushIndex, strategies_, indexes);
            _syncDeposits(smartVault, flushIndex, strategies_, indexes);

            flushIndex++;
            _flushIndexesToSync[smartVault] = flushIndex;
        }
    }

    /**
     * @notice TODO
     */
    function reallocate() external {}

    /* ========== PRIVATE/INTERNAL FUNCTIONS ========== */

    /**
     * @notice Gets total value (in USD) of assets managed by the vault.
     */
    function _getVaultTotalUsdValue(address smartVault) internal view returns (uint256) {
        return SpoolUtils.getVaultTotalUsdValue(smartVault, _smartVaultStrategies[smartVault]);
    }

    function _depositAssets(address smartVault, address owner, address receiver, uint256[] memory assets)
        internal
        returns (uint256)
    {
        // check assets length
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);
        if (tokens.length != assets.length) {
            revert InvalidAssetLengths();
        }

        // run guards and actions
        _runGuards(smartVault, msg.sender, receiver, owner, assets, tokens, RequestType.Deposit);
        _runActions(smartVault, msg.sender, receiver, owner, assets, tokens, RequestType.Deposit);

        // check if assets are in correct ratio
        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        SmartVaultDeposits.checkDepositRatio(
            assets,
            SpoolUtils.getExchangeRates(tokens, _priceFeedManager),
            _smartVaultAllocations[smartVault].toArray(strategies_.length),
            SpoolUtils.getStrategyRatiosAtLastDhw(strategies_, _strategyRegistry)
        );

        // transfer tokens from user to master wallet
        uint256 flushIndex = _flushIndexes[smartVault];
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransferFrom(owner, address(_masterWallet), assets[i]);
            _vaultDeposits[smartVault][flushIndex][i] = assets[i];
        }

        // mint deposit NFT
        DepositMetadata memory metadata = DepositMetadata(assets, block.timestamp, flushIndex);
        return ISmartVault(smartVault).mintDepositNFT(receiver, metadata);
    }

    function _redeemShares(address smartVaultAddress, uint256 vaultShares, address receiver, address owner)
        internal
        returns (uint256)
    {
        ISmartVault smartVault = ISmartVault(smartVaultAddress);
        if (smartVault.balanceOf(owner) < vaultShares) {
            revert InsufficientBalance(smartVault.balanceOf(msg.sender), vaultShares);
        }

        // run guards
        uint256[] memory assets = new uint256[](1);
        assets[0] = vaultShares;
        address[] memory tokens = new address[](1);
        tokens[0] = smartVaultAddress;
        _runGuards(smartVaultAddress, msg.sender, receiver, owner, assets, tokens, RequestType.Withdrawal);

        // add withdrawal to be flushed
        uint256 flushIndex = _flushIndexes[smartVaultAddress];
        _withdrawnVaultShares[smartVaultAddress][flushIndex] += vaultShares;

        // transfer vault shares back to smart vault
        smartVault.transferFrom(owner, smartVaultAddress, vaultShares);
        return smartVault.mintWithdrawalNFT(receiver, WithdrawalMetadata(vaultShares, flushIndex));
    }

    function _calculateWithdrawal(address smartVault, WithdrawalMetadata memory data, uint256 assetGroupLength)
        internal
        view
        returns (uint256[] memory)
    {
        uint256[] memory withdrawnAssets = new uint256[](assetGroupLength);

        // loop over all assets
        for (uint256 i = 0; i < withdrawnAssets.length; i++) {
            withdrawnAssets[i] = Math.mulDiv(
                _withdrawnAssets[smartVault][data.flushIndex][i],
                data.vaultShares,
                _withdrawnVaultShares[smartVault][data.flushIndex]
            );
        }

        return withdrawnAssets;
    }

    function _syncWithdrawals(
        address smartVault,
        uint256 flushIndex,
        address[] memory strategies_,
        uint256[] memory dhwIndexes_
    ) private {
        if (_withdrawnVaultShares[smartVault][flushIndex] == 0) {
            return;
        }

        uint256[] memory withdrawnAssets_ = _strategyRegistry.claimWithdrawals(
            strategies_, dhwIndexes_, _withdrawnStrategyShares[smartVault][flushIndex].toArray(strategies_.length)
        );

        _withdrawnAssets[smartVault][flushIndex].setValues(withdrawnAssets_);
    }

    function _syncDeposits(
        address smartVault,
        uint256 flushIndex,
        address[] memory strategies_,
        uint256[] memory dhwIndexes_
    ) private {
        // skip if there were no deposits made
        if (_vaultDeposits[smartVault][flushIndex][0] == 0) {
            return;
        }

        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);

        // get vault's USD value before claiming SSTs
        uint256 totalVaultValueBefore = _getVaultTotalUsdValue(smartVault);

        // claim SSTs from each strategy
        for (uint256 i = 0; i < strategies_.length; i++) {
            StrategyAtIndex memory atDhw = _strategyRegistry.strategyAtIndex(strategies_[i], dhwIndexes_[i]);

            uint256[] memory vaultDepositedAssets =
                _vaultFlushedDeposits[smartVault][flushIndex][strategies_[i]].toArray(assetGroup.length);
            uint256 vaultDepositedUsd =
                _priceFeedManager.assetToUsdCustomPriceBulk(assetGroup, vaultDepositedAssets, atDhw.exchangeRates);
            uint256 strategyDepositedUsd =
                _priceFeedManager.assetToUsdCustomPriceBulk(assetGroup, atDhw.assetsDeposited, atDhw.exchangeRates);

            uint256 vaultSstShare = Math.mulDiv(atDhw.sharesMinted, vaultDepositedUsd, strategyDepositedUsd);

            IStrategy(strategies_[i]).claimShares(smartVault, vaultSstShare);
            // TODO: there might be dust left after all vaults are synced
        }

        // mint SVTs based on USD value of claimed SSTs
        uint256 totalDepositedUsd = _getVaultTotalUsdValue(smartVault) - totalVaultValueBefore;
        uint256 svtsToMint;
        if (totalVaultValueBefore == 0) {
            svtsToMint = totalDepositedUsd * INITIAL_SHARE_MULTIPLIER;
        } else {
            svtsToMint = Math.mulDiv(totalDepositedUsd, ISmartVault(smartVault).totalSupply(), totalVaultValueBefore);
        }
        ISmartVault(smartVault).mint(smartVault, svtsToMint);
        _mintedVaultShares[smartVault][flushIndex] = svtsToMint;
    }

    function _runGuards(
        address smartVault,
        address executor,
        address receiver,
        address owner,
        uint256[] memory assets,
        address[] memory assetGroup,
        RequestType requestType
    ) internal view {
        RequestContext memory context = RequestContext(receiver, executor, owner, requestType, assets, assetGroup);
        _guardManager.runGuards(smartVault, context);
    }

    function _runActions(
        address smartVault,
        address executor,
        address recipient,
        address owner,
        uint256[] memory assets,
        address[] memory assetGroup,
        RequestType requestType
    ) internal {
        ActionContext memory context = ActionContext(recipient, executor, owner, requestType, assetGroup, assets);
        _actionManager.runActions(smartVault, context);
    }

    function _onlyUnregisteredSmartVault(address smartVault) internal view {
        _checkRole(ROLE_SMART_VAULT, smartVault);
        if (_smartVaultRegistry[smartVault]) {
            revert SmartVaultAlreadyRegistered();
        }
    }

    function _onlyRegisteredSmartVault(address smartVault) internal view {
        _checkRole(ROLE_SMART_VAULT, smartVault);
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
