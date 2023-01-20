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
import "./DepositManager.sol";

/**
 * @dev Requires roles:
 * - ROLE_STRATEGY_CLAIMER
 * - ROLE_MASTER_WALLET_MANAGER
 * - ROLE_SMART_VAULT_MANAGER
 */
contract SmartVaultManager is ISmartVaultManager, ActionsAndGuards, SpoolAccessControllable {
    /* ========== CONSTANTS ========== */

    using SafeERC20 for IERC20;
    using ArrayMapping for mapping(uint256 => uint256);

    IDepositManager private immutable _depositManager;

    /// @notice Strategy registry
    IStrategyRegistry private immutable _strategyRegistry;

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

    constructor(
        ISpoolAccessControl accessControl_,
        IStrategyRegistry strategyRegistry_,
        IAssetGroupRegistry assetGroupRegistry_,
        IMasterWallet masterWallet_,
        IActionManager actionManager_,
        IGuardManager guardManager_,
        IRiskManager riskManager_,
        IDepositManager depositManager_
    ) ActionsAndGuards(guardManager_, actionManager_) SpoolAccessControllable(accessControl_) {
        _strategyRegistry = strategyRegistry_;
        _assetGroupRegistry = assetGroupRegistry_;
        _masterWallet = masterWallet_;
        _riskManager = riskManager_;
        _depositManager = depositManager_;
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
            bytes[] memory metadata = smartVault.getMetadata(nftIds);
            uint256[] memory balances = smartVault.balanceOfFractionalBatch(userAddress, nftIds);
            address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVaultAddress]);

            for (uint256 i; i < nftIds.length; i++) {
                if (nftIds[i] > MAXIMAL_DEPOSIT_ID) {
                    continue;
                }

                DepositMetadata memory depositMetadata = abi.decode(metadata[i], (DepositMetadata));

                if (depositMetadata.flushIndex >= _flushIndexesToSync[smartVaultAddress]) {
                    revert DepositNotSyncedYet();
                }

                uint256 balance = _depositManager.getClaimedVaultTokensPreview(
                    smartVaultAddress, depositMetadata, balances[i], tokens
                );
                currentBalance += balance;
            }
        }

        return currentBalance;
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

    function redeem(
        address smartVault,
        uint256 shares,
        address receiver,
        address owner,
        uint256[] calldata nftIds,
        uint256[] calldata nftAmounts
    ) external onlyRegisteredSmartVault(smartVault) returns (uint256) {
        return _redeemShares(smartVault, shares, receiver, owner, nftIds, nftAmounts);
    }

    function redeemFast(
        address smartVaultAddress,
        uint256 shares,
        uint256[] calldata nftIds,
        uint256[] calldata nftAmounts
    ) external onlyRegisteredSmartVault(smartVaultAddress) returns (uint256[] memory) {
        ISmartVault smartVault = ISmartVault(smartVaultAddress);
        _validateRedeem(smartVault, msg.sender, msg.sender, msg.sender, nftIds, nftAmounts, shares);

        // figure out how much to redeem from each strategy
        address[] memory strategies_ = _smartVaultStrategies[smartVaultAddress];
        uint256[] memory strategySharesToRedeem = new uint256[](strategies_.length);
        {
            uint256 totalVaultShares = smartVault.totalSupply();
            for (uint256 i = 0; i < strategies_.length; i++) {
                uint256 strategyShares = IStrategy(strategies_[i]).balanceOf(smartVaultAddress);

                strategySharesToRedeem[i] = strategyShares * shares / totalVaultShares;
            }

            // redeem from strategies and burn
            smartVault.burn(msg.sender, shares, strategies_, strategySharesToRedeem);
        }

        uint256 assetGroupId_ = _smartVaultAssetGroups[smartVaultAddress];
        uint256[] memory assetsWithdrawn;

        {
            address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupId_);
            assetsWithdrawn = _strategyRegistry.redeemFast(strategies_, strategySharesToRedeem, assetGroup);

            // transfer assets to the redeemer
            for (uint256 i = 0; i < assetGroup.length; i++) {
                _masterWallet.transfer(IERC20(assetGroup[i]), msg.sender, assetsWithdrawn[i]);
            }
        }

        emit FastRedeemInitiated(
            smartVaultAddress, msg.sender, assetGroupId_, shares, nftIds, nftAmounts, assetsWithdrawn
            );

        return assetsWithdrawn;
    }

    function depositFor(
        address smartVault,
        uint256[] calldata assets,
        address receiver,
        address depositor,
        address referral
    ) external onlyRegisteredSmartVault(smartVault) returns (uint256) {
        return _depositAssets(smartVault, depositor, receiver, assets, referral);
    }

    function deposit(address smartVault, uint256[] calldata assets, address receiver, address referral)
        external
        onlyRegisteredSmartVault(smartVault)
        returns (uint256)
    {
        return _depositAssets(smartVault, msg.sender, receiver, assets, referral);
    }

    /**
     * @notice Burn deposit NFTs to claim SVTs
     * @param smartVault Vault address
     * @param nftIds NFTs to burn
     * @param nftAmounts NFT amounts to burn
     */
    function claimSmartVaultTokens(address smartVault, uint256[] calldata nftIds, uint256[] calldata nftAmounts)
        public
        onlyRegisteredSmartVault(smartVault)
        returns (uint256)
    {
        // NOTE:
        // - here we are passing ids into the request context instead of amounts
        // - here we passing empty array as tokens
        _runGuards(smartVault, msg.sender, msg.sender, msg.sender, nftIds, new address[](0), RequestType.BurnNFT);

        ISmartVault vault = ISmartVault(smartVault);
        bytes[] memory metadata = vault.burnNFTs(msg.sender, nftIds, nftAmounts);
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);

        uint256 claimedVaultTokens = 0;
        for (uint256 i = 0; i < nftIds.length; i++) {
            if (nftIds[i] > MAXIMAL_DEPOSIT_ID) {
                revert InvalidDepositNftId(nftIds[i]);
            }

            claimedVaultTokens += _depositManager.getClaimedVaultTokensPreview(
                smartVault, abi.decode(metadata[i], (DepositMetadata)), nftAmounts[i], tokens
            );
        }

        // there will be some dust after all users claim SVTs
        vault.claimShares(msg.sender, claimedVaultTokens);

        emit SmartVaultTokensClaimed(smartVault, msg.sender, claimedVaultTokens, nftIds, nftAmounts);

        return claimedVaultTokens;
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
    ) public onlyRegisteredSmartVault(smartVault) returns (uint256[] memory, uint256) {
        uint256 assetGroupId_ = _smartVaultAssetGroups[smartVault];
        bytes[] memory metadata = ISmartVault(smartVault).burnNFTs(msg.sender, nftIds, nftAmounts);
        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupId_);
        uint256[] memory withdrawnAssets = new uint256[](assetGroup.length);

        for (uint256 i = 0; i < nftIds.length; i++) {
            if (nftIds[i] <= MAXIMAL_DEPOSIT_ID) {
                revert InvalidWithdrawalNftId(nftIds[i]);
            }

            uint256[] memory withdrawnAssets_ =
                _calculateWithdrawal(smartVault, abi.decode(metadata[i], (WithdrawalMetadata)), assetGroup.length);
            for (uint256 j = 0; j < assetGroup.length; j++) {
                withdrawnAssets[j] += withdrawnAssets_[j] * nftAmounts[i] / NFT_MINTED_SHARES;
            }
        }

        _runActions(smartVault, msg.sender, receiver, msg.sender, withdrawnAssets, assetGroup, RequestType.Withdrawal);

        for (uint256 i = 0; i < assetGroup.length; i++) {
            // TODO-Q: should this be done by an action, since there might be a swap?
            _masterWallet.transfer(IERC20(assetGroup[i]), receiver, withdrawnAssets[i]);
        }

        emit WithdrawalClaimed(smartVault, msg.sender, assetGroupId_, nftIds, nftAmounts, withdrawnAssets);

        return (withdrawnAssets, assetGroupId_);
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
        emit RiskProviderSet(smartVault, riskProvider_);
    }

    /* ========== BOOKKEEPING ========== */

    function flushSmartVault(address smartVault) external onlyRegisteredSmartVault(smartVault) {
        uint256 flushIndex = _flushIndexes[smartVault];
        address[] memory strategies_ = _smartVaultStrategies[smartVault];

        // handle deposits
        uint256[] memory allocation = _smartVaultAllocations[smartVault].toArray(strategies_.length);
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);
        uint256[] memory flushDhwIndexes =
            _depositManager.flushSmartVault(smartVault, flushIndex, strategies_, allocation, tokens);

        uint256 withdrawals = _withdrawnVaultShares[smartVault][flushIndex];

        if (withdrawals > 0) {
            // handle withdrawals
            uint256[] memory strategyWithdrawals = new uint256[](strategies_.length);
            uint256 totalVaultShares = ISmartVault(smartVault).totalSupply();

            for (uint256 i = 0; i < strategies_.length; i++) {
                uint256 strategyShares = IStrategy(strategies_[i]).balanceOf(smartVault);
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

        // NOTE: warning "This declaration has the same name as another declaration."
        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);

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
            _depositManager.syncDeposits(smartVault, flushIndex, strategies_, indexes, assetGroup);

            emit SmartVaultSynced(smartVault, flushIndex);

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

    function _depositAssets(
        address smartVault,
        address owner,
        address receiver,
        uint256[] memory assets,
        address referral
    ) internal returns (uint256) {
        // check assets length
        uint256 assetGroupId_ = _smartVaultAssetGroups[smartVault];
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId_);
        if (tokens.length != assets.length) {
            revert InvalidAssetLengths();
        }
        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        uint256[] memory allocations_ = _smartVaultAllocations[smartVault].toArray(strategies_.length);
        uint256 flushIndex = _flushIndexes[smartVault];
        return _depositManager.depositAssets(
            DepositBag(
                smartVault,
                owner,
                receiver,
                msg.sender,
                assets,
                tokens,
                strategies_,
                allocations_,
                flushIndex,
                assetGroupId_,
                referral
            )
        );
    }

    function _redeemShares(
        address smartVaultAddress,
        uint256 vaultShares,
        address receiver,
        address owner,
        uint256[] calldata nftIds,
        uint256[] calldata nftAmounts
    ) internal returns (uint256) {
        ISmartVault smartVault = ISmartVault(smartVaultAddress);
        _validateRedeem(smartVault, owner, msg.sender, receiver, nftIds, nftAmounts, vaultShares);

        // add withdrawal to be flushed
        uint256 flushIndex = _flushIndexes[smartVaultAddress];
        _withdrawnVaultShares[smartVaultAddress][flushIndex] += vaultShares;

        // transfer vault shares back to smart vault
        smartVault.transferFromSpender(owner, smartVaultAddress, vaultShares, msg.sender);
        uint256 redeemId = smartVault.mintWithdrawalNFT(receiver, WithdrawalMetadata(vaultShares, flushIndex));
        emit RedeemInitiated(smartVaultAddress, owner, redeemId, flushIndex, vaultShares, receiver);

        return redeemId;
    }

    function _validateRedeem(
        ISmartVault smartVault,
        address owner,
        address executor,
        address receiver,
        uint256[] memory nftIds,
        uint256[] memory nftAmounts,
        uint256 shares
    ) private {
        for (uint256 i = 0; i < nftIds.length; i++) {
            if (nftIds[i] > MAXIMAL_DEPOSIT_ID) {
                revert InvalidDepositNftId(nftIds[i]);
            }
        }

        _runGuards(address(smartVault), owner, owner, owner, nftIds, new address[](0), RequestType.BurnNFT);
        smartVault.burnNFTs(owner, nftIds, nftAmounts);

        if (smartVault.balanceOf(owner) < shares) {
            revert InsufficientBalance(smartVault.balanceOf(owner), shares);
        }

        uint256[] memory assets = new uint256[](1);
        assets[0] = shares;
        address[] memory tokens = new address[](1);
        tokens[0] = address(smartVault);
        _runGuards(address(smartVault), executor, receiver, owner, assets, tokens, RequestType.Withdrawal);
    }

    function _calculateWithdrawal(address smartVault, WithdrawalMetadata memory data, uint256 assetGroupLength)
        internal
        view
        returns (uint256[] memory)
    {
        uint256[] memory withdrawnAssets = new uint256[](assetGroupLength);

        // loop over all assets
        for (uint256 i = 0; i < withdrawnAssets.length; i++) {
            withdrawnAssets[i] = _withdrawnAssets[smartVault][data.flushIndex][i] * data.vaultShares
                / _withdrawnVaultShares[smartVault][data.flushIndex];
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
