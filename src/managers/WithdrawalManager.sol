// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/ISmartVault.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/ISmartVaultManager.sol";
import "./ActionsAndGuards.sol";
import "../interfaces/IWithdrawalManager.sol";
import "../libraries/ArrayMapping.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/ISmartVault.sol";
import "../access/SpoolAccessControl.sol";

contract WithdrawalManager is ActionsAndGuards, SpoolAccessControllable, IWithdrawalManager {
    using SafeERC20 for IERC20;
    using ArrayMapping for mapping(uint256 => uint256);

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

    /// @notice Strategy registry
    IStrategyRegistry private immutable _strategyRegistry;

    /// @notice Price feed manager
    IUsdPriceFeedManager private immutable _priceFeedManager;

    /// @notice Master wallet
    IMasterWallet private immutable _masterWallet;

    constructor(
        IStrategyRegistry strategyRegistry_,
        IUsdPriceFeedManager priceFeedManager_,
        IMasterWallet masterWallet_,
        IGuardManager guardManager_,
        IActionManager actionManager_,
        ISpoolAccessControl accessControl_
    ) ActionsAndGuards(guardManager_, actionManager_) SpoolAccessControllable(accessControl_) {
        _strategyRegistry = strategyRegistry_;
        _priceFeedManager = priceFeedManager_;
        _masterWallet = masterWallet_;
    }

    function flushSmartVault(address smartVault, uint256 flushIndex, address[] memory strategies)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint256[] memory)
    {
        uint256[] memory flushDhwIndexes;
        uint256 withdrawals = _withdrawnVaultShares[smartVault][flushIndex];

        if (withdrawals > 0) {
            // handle withdrawals
            uint256[] memory strategyWithdrawals = new uint256[](strategies.length);
            uint256 totalVaultShares = ISmartVault(smartVault).totalSupply();

            for (uint256 i = 0; i < strategies.length; i++) {
                uint256 strategyShares = IStrategy(strategies[i]).balanceOf(smartVault);
                strategyWithdrawals[i] = strategyShares * withdrawals / totalVaultShares;
            }

            ISmartVault(smartVault).burn(smartVault, withdrawals, strategies, strategyWithdrawals);
            flushDhwIndexes = _strategyRegistry.addWithdrawals(strategies, strategyWithdrawals);

            _withdrawnStrategyShares[smartVault][flushIndex].setValues(strategyWithdrawals);
        }

        return flushDhwIndexes;
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

    function claimWithdrawal(WithdrawalClaimBag memory bag)
        public
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint256[] memory, uint256)
    {
        uint256[] memory withdrawnAssets = new uint256[](bag.assetGroup.length);
        bytes[] memory metadata = ISmartVault(bag.smartVault).burnNFTs(bag.executor, bag.nftIds, bag.nftAmounts);

        for (uint256 i = 0; i < bag.nftIds.length; i++) {
            if (bag.nftIds[i] <= MAXIMAL_DEPOSIT_ID) {
                revert InvalidWithdrawalNftId(bag.nftIds[i]);
            }

            uint256[] memory withdrawnAssets_ = _calculateWithdrawal(
                bag.smartVault, abi.decode(metadata[i], (WithdrawalMetadata)), bag.assetGroup.length
            );
            for (uint256 j = 0; j < bag.assetGroup.length; j++) {
                withdrawnAssets[j] += withdrawnAssets_[j] * bag.nftAmounts[i] / NFT_MINTED_SHARES;
            }
        }

        _runActions(
            bag.smartVault,
            bag.executor,
            bag.receiver,
            bag.executor,
            withdrawnAssets,
            bag.assetGroup,
            RequestType.Withdrawal
        );

        for (uint256 i = 0; i < bag.assetGroup.length; i++) {
            // TODO-Q: should this be done by an action, since there might be a swap?
            _masterWallet.transfer(IERC20(bag.assetGroup[i]), bag.receiver, withdrawnAssets[i]);
        }

        emit WithdrawalClaimed(
            bag.smartVault, bag.executor, bag.assetGroupId, bag.nftIds, bag.nftAmounts, withdrawnAssets
            );

        return (withdrawnAssets, bag.assetGroupId);
    }

    function syncWithdrawals(
        address smartVault,
        uint256 flushIndex,
        address[] memory strategies,
        uint256[] memory dhwIndexes_
    ) external onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender) {
        if (_withdrawnVaultShares[smartVault][flushIndex] == 0) {
            return;
        }

        uint256[] memory withdrawnAssets_ = _strategyRegistry.claimWithdrawals(
            strategies, dhwIndexes_, _withdrawnStrategyShares[smartVault][flushIndex].toArray(strategies.length)
        );

        _withdrawnAssets[smartVault][flushIndex].setValues(withdrawnAssets_);
    }

    function redeem(RedeemBag calldata bag, RedeemExtras memory bag2)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint256)
    {
        ISmartVault smartVault = ISmartVault(bag.smartVault);
        _validateRedeem(smartVault, bag2.redeemer, bag2.receiver, bag.nftIds, bag.nftAmounts, bag.shares);

        // add withdrawal to be flushed
        _withdrawnVaultShares[bag.smartVault][bag2.flushIndex] += bag.shares;

        // transfer vault shares back to smart vault
        smartVault.transferFromSpender(bag2.redeemer, bag.smartVault, bag.shares, bag2.redeemer);
        uint256 redeemId = smartVault.mintWithdrawalNFT(bag2.receiver, WithdrawalMetadata(bag.shares, bag2.flushIndex));
        emit RedeemInitiated(bag.smartVault, bag2.redeemer, redeemId, bag2.flushIndex, bag.shares, bag2.receiver);

        return redeemId;
    }

    function redeemFast(RedeemBag calldata bag, RedeemFastExtras memory bag2)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint256[] memory)
    {
        ISmartVault smartVault = ISmartVault(bag.smartVault);
        _validateRedeem(smartVault, bag2.redeemer, bag2.redeemer, bag.nftIds, bag.nftAmounts, bag.shares);

        // figure out how much to redeem from each strategy
        uint256[] memory strategySharesToRedeem = new uint256[](bag2.strategies.length);
        {
            uint256 totalVaultShares = smartVault.totalSupply();
            for (uint256 i = 0; i < bag2.strategies.length; i++) {
                uint256 strategyShares = IStrategy(bag2.strategies[i]).balanceOf(bag.smartVault);

                strategySharesToRedeem[i] = strategyShares * bag.shares / totalVaultShares;
            }

            // redeem from strategies and burn
            smartVault.burn(bag2.redeemer, bag.shares, bag2.strategies, strategySharesToRedeem);
        }

        uint256[] memory assetsWithdrawn =
            _strategyRegistry.redeemFast(bag2.strategies, strategySharesToRedeem, bag2.assetGroup);

        // transfer assets to the redeemer
        for (uint256 i = 0; i < bag2.assetGroup.length; i++) {
            _masterWallet.transfer(IERC20(bag2.assetGroup[i]), bag2.redeemer, assetsWithdrawn[i]);
        }

        emit FastRedeemInitiated(bag.smartVault, bag2.redeemer, bag.shares, bag.nftIds, bag.nftAmounts, assetsWithdrawn);

        return assetsWithdrawn;
    }

    function _validateRedeem(
        ISmartVault smartVault,
        address redeemer,
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

        _runGuards(address(smartVault), redeemer, redeemer, redeemer, nftIds, new address[](0), RequestType.BurnNFT);
        smartVault.burnNFTs(redeemer, nftIds, nftAmounts);

        if (smartVault.balanceOf(redeemer) < shares) {
            revert InsufficientBalance(smartVault.balanceOf(redeemer), shares);
        }

        uint256[] memory assets = new uint256[](1);
        assets[0] = shares;
        address[] memory tokens = new address[](1);
        tokens[0] = address(smartVault);
        _runGuards(address(smartVault), redeemer, receiver, redeemer, assets, tokens, RequestType.Withdrawal);
    }
}
