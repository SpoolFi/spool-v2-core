// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../access/Roles.sol";
import "../interfaces/CommonErrors.sol";
import "../interfaces/Constants.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/ISpoolAccessControl.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";

/**
 * @notice Parameters for emergencyWithdraw function.
 * @custom:member removeStrategies Whether to remove strategies from the system after withdrawal.
 * @custom:member accessControl Access control contract.
 * @custom:member ghostStrategy Address of ghost strategy.
 * @custom:member emergencyWithdrawalWallet Address of emergency withdrawal wallet.
 * @custom:member masterWallet Master wallet contract.
 */
struct EmergencyWithdrawParams {
    bool removeStrategies;
    ISpoolAccessControl accessControl;
    address ghostStrategy;
    address emergencyWithdrawalWallet;
    IMasterWallet masterWallet;
}

/**
 * @notice Parameters for claimStrategyShareWithdrawals function.
 * @custom:member recipient Address to receive the claimed assets.
 * @custom:member ghostStrategy Address of ghost strategy.
 * @custom:member accessControl Access control contract.
 * @custom:member masterWallet Master wallet contract.
 */
struct ClaimStrategyShareWithdrawalsParams {
    address recipient;
    address ghostStrategy;
    ISpoolAccessControl accessControl;
    IMasterWallet masterWallet;
}
/**
 * @dev This library should only be used by the StrategyRegistry contract.
 */
library StrategyRegistryLib {
    /**
     * @notice Emitted when a strategy is emergency withdrawn from.
     * @param strategy Strategy that was emergency withdrawn from.
     */
    event StrategyEmergencyWithdrawn(address indexed strategy);

    /**
     * @notice Strategy was removed.
     * @param strategy Strategy address.
     */
    event StrategyRemoved(address indexed strategy);

    /**
     * @notice Strategy shares have been redeemed.
     * @param strategy Strategy address.
     * @param owner Address that owns the shares.
     * @param recipient Address that received the withdrawn funds.
     * @param shares Amount of shares that were redeemed.
     * @param assetsWithdrawn Amounts of withdrawn assets.
     */
    event StrategySharesRedeemed(
        address indexed strategy,
        address indexed owner,
        address indexed recipient,
        uint256 shares,
        uint256[] assetsWithdrawn
    );

    /**
     * @notice Strategy shares redeem has been initiated.
     * @param strategy Strategy address.
     * @param owner Address that owns the shares.
     * @param shares Amount of shares that were redeemed.
     * @param strategyIndex DHW index of the strategy.
     */
    event StrategySharesRedeemInitiated(
        address indexed strategy, address indexed owner, uint256 shares, uint256 strategyIndex
    );

    /**
     * @notice Strategy shares redeem has been claimed.
     * @param strategy Strategy address.
     * @param owner Address that redeemed the shares.
     * @param recipient Address that received the withdrawn funds.
     * @param shares Amount of shares that were redeemed.
     * @param assetsWithdrawn Amounts of withdrawn assets.
     */
    event StrategySharesRedeemClaimed(
        address indexed strategy,
        address indexed owner,
        address indexed recipient,
        uint256 shares,
        uint256[] assetsWithdrawn
    );

    /**
     * @notice Strategy shares were fast redeemed.
     * @param strategy Strategy address.
     * @param shares Amount of shares redeemed.
     * @param assetsWithdrawn Amounts of withdrawn assets.
     */
    event StrategySharesFastRedeemed(address indexed strategy, uint256 shares, uint256[] assetsWithdrawn);

    /**
     * @notice Executes emergency withdrawal.
     * @param strategies Addresses of strategies to emergency withdraw from.
     * @param withdrawalSlippages Slippages to guard withdrawal.
     * @param params Parameters for emergency withdrawal.
     * @param currentIndexes Current DHW indexes of strategies.
     * @param assetsDeposited Assets deposited into strategies.
     * @param removedStrategies Registry of removed strategies.
     * @param assetsNotClaimed Assets not claimed by strategy users.
     */
    function emergencyWithdraw(
        address[] calldata strategies,
        uint256[][] calldata withdrawalSlippages,
        EmergencyWithdrawParams memory params,
        mapping(address => uint256) storage currentIndexes,
        mapping(address => mapping(uint256 => mapping(uint256 => uint256))) storage assetsDeposited,
        mapping(address => bool) storage removedStrategies,
        mapping(address => mapping(uint256 => uint256)) storage assetsNotClaimed
    ) external {
        if (!_isViewExecution()) {
            _checkRole(ROLE_EMERGENCY_WITHDRAWAL_EXECUTOR, msg.sender, params.accessControl);
        }

        for (uint256 i; i < strategies.length; ++i) {
            if (strategies[i] == params.ghostStrategy) {
                continue;
            }
            _checkRole(ROLE_STRATEGY, strategies[i], params.accessControl);

            IStrategy(strategies[i]).emergencyWithdraw(withdrawalSlippages[i], params.emergencyWithdrawalWallet);

            emit StrategyEmergencyWithdrawn(strategies[i]);

            if (params.removeStrategies) {
                removeStrategy(
                    strategies[i],
                    params.accessControl,
                    params.masterWallet,
                    params.emergencyWithdrawalWallet,
                    currentIndexes,
                    assetsDeposited,
                    removedStrategies,
                    assetsNotClaimed
                );
            }
        }
    }

    /**
     * @notice Removes a strategy from registry.
     * @param strategy Strategy to remove.
     * @param accessControl Access control contract.
     * @param masterWallet Master wallet contract.
     * @param emergencyWithdrawalWallet Address of emergency withdrawal wallet.
     * @param currentIndexes Current DHW indexes of strategies.
     * @param assetsDeposited Assets deposited into strategies.
     * @param removedStrategies Registry of removed strategies.
     * @param assetsNotClaimed Assets not claimed by strategy users.
     */
    function removeStrategy(
        address strategy,
        ISpoolAccessControl accessControl,
        IMasterWallet masterWallet,
        address emergencyWithdrawalWallet,
        mapping(address => uint256) storage currentIndexes,
        mapping(address => mapping(uint256 => mapping(uint256 => uint256))) storage assetsDeposited,
        mapping(address => bool) storage removedStrategies,
        mapping(address => mapping(uint256 => uint256)) storage assetsNotClaimed
    ) public {
        if (!accessControl.hasRole(ROLE_STRATEGY, strategy)) {
            revert InvalidStrategy(strategy);
        }

        // send flushed and non-claimed funds to emergency withdrawal wallet
        uint256 dhwIndex = currentIndexes[strategy];
        address[] memory tokens = IStrategy(strategy).assets();
        for (uint256 i; i < tokens.length; ++i) {
            uint256 amount = assetsDeposited[strategy][dhwIndex][i] + assetsNotClaimed[strategy][i];

            if (amount > 0) {
                masterWallet.transfer(IERC20(tokens[i]), emergencyWithdrawalWallet, amount);
            }
        }

        // remove strategy
        accessControl.revokeRole(ROLE_STRATEGY, strategy);
        removedStrategies[strategy] = true;

        emit StrategyRemoved(strategy);
    }

    /**
     * @notice Redeems strategy shares.
     * @param strategies Strategies from which to redeem.
     * @param shares Amount of shares to redeem.
     * @param withdrawalSlippages Slippages to guard withdrawal.
     * @param redeemer User redeeming the shares.
     * @param accessControl Access control contract.
     * @param ghostStrategy Address of ghost strategy.
     * @param dhwStatus DHW status of strategies.
     */
    function redeemStrategyShares(
        address[] calldata strategies,
        uint256[] calldata shares,
        uint256[][] calldata withdrawalSlippages,
        address redeemer,
        ISpoolAccessControl accessControl,
        address ghostStrategy,
        mapping(address => uint256) storage dhwStatus
    ) external {
        for (uint256 i; i < strategies.length; ++i) {
            if (strategies[i] == ghostStrategy || shares[i] == 0) {
                continue;
            }
            _checkRole(ROLE_STRATEGY, strategies[i], accessControl);

            if (dhwStatus[strategies[i]] > STRATEGY_IDLE) {
                revert StrategyNotReady(strategies[i]);
            }

            address[] memory assetGroup = IStrategy(strategies[i]).assets();

            uint256[] memory withdrawnAssets =
                IStrategy(strategies[i]).redeemShares(shares[i], redeemer, assetGroup, withdrawalSlippages[i]);

            emit StrategySharesRedeemed(strategies[i], redeemer, redeemer, shares[i], withdrawnAssets);
        }
    }

    /**
     * Initiates redemption of strategy shares asynchronously.
     * @param strategies Strategies from which to redeem.
     * @param shares Amount of shares to redeem.
     * @param ghostStrategy Address of ghost strategy.
     * @param accessControl Access control contract.
     * @param currentIndexes Current DHW indexes of strategies.
     * @param sharesRedeemed Amount of SSTs redeemed from strategies.
     * @param userSharesWithdrawn Amount of SSTs withdrawn from strategies by users.
     */
    function redeemStrategySharesAsync(
        address[] calldata strategies,
        uint256[] calldata shares,
        address ghostStrategy,
        ISpoolAccessControl accessControl,
        mapping(address => uint256) storage currentIndexes,
        mapping(address => mapping(uint256 => uint256)) storage sharesRedeemed,
        mapping(address => mapping(address => mapping(uint256 => uint256))) storage userSharesWithdrawn
    ) external {
        if (strategies.length != shares.length) {
            revert InvalidArrayLength();
        }

        for (uint256 i; i < strategies.length; ++i) {
            address strategy = strategies[i];

            if (strategy == ghostStrategy) {
                revert GhostStrategyUsed();
            }
            _checkRole(ROLE_STRATEGY, strategy, accessControl);

            uint256 strategyShares = shares[i];
            uint256 index = currentIndexes[strategy];
            sharesRedeemed[strategy][index] += strategyShares;
            userSharesWithdrawn[msg.sender][strategy][index] += strategyShares;

            IStrategy(strategy).releaseShares(msg.sender, strategyShares);

            emit StrategySharesRedeemInitiated(strategy, msg.sender, strategyShares, index);
        }
    }

    /**
     * @notice Claims strategy share withdrawals from redeemStrategySharesAsync
     * @param strategies Strategies from which to claim withdrawals.
     * @param strategyIndexes DHW indexes of strategies when withdrawals were initiated.
     * @param params Parameters for claiming withdrawals.
     * @param userSharesWithdrawn Amount of SSTs withdrawn from strategies by users.
     * @param assetsWithdrawn Amounts of withdrawn assets
     * @param sharesRedeemed Amount of SSTs redeemed from strategies.
     * @param assetsNotClaimed Amounts of assets not claimed by strategy users.
     */
    function claimStrategyShareWithdrawals(
        address[] calldata strategies,
        uint256[] calldata strategyIndexes,
        ClaimStrategyShareWithdrawalsParams memory params,
        mapping(address => mapping(address => mapping(uint256 => uint256))) storage userSharesWithdrawn,
        mapping(address => mapping(uint256 => mapping(uint256 => uint256))) storage assetsWithdrawn,
        mapping(address => mapping(uint256 => uint256)) storage sharesRedeemed,
        mapping(address => mapping(uint256 => uint256)) storage assetsNotClaimed
    ) external {
        if (strategies.length != strategyIndexes.length) {
            revert InvalidArrayLength();
        }

        uint256 assetGroupId;
        address[] memory assetGroup;
        uint256[] memory totalWithdrawnAssets;

        for (uint256 i; i < strategies.length; ++i) {
            address strategy = strategies[i];

            if (strategy == params.ghostStrategy) {
                continue;
            }
            _checkRole(ROLE_STRATEGY, strategy, params.accessControl);

            uint256 strategyAssetGroupId = IStrategy(strategy).assetGroupId();
            if (assetGroup.length == 0) {
                assetGroupId = strategyAssetGroupId;
                assetGroup = IStrategy(strategy).assets();
                totalWithdrawnAssets = new uint256[](assetGroup.length);
            } else {
                if (assetGroupId != strategyAssetGroupId) {
                    revert NotSameAssetGroup();
                }
            }

            uint256 strategyIndex = strategyIndexes[i];
            uint256 strategyShares = userSharesWithdrawn[msg.sender][strategy][strategyIndex];

            userSharesWithdrawn[msg.sender][strategy][strategyIndex] = 0;

            uint256[] memory withdrawnAssets = new uint256[](assetGroup.length);
            for (uint256 j = 0; j < assetGroup.length; ++j) {
                withdrawnAssets[j] = assetsWithdrawn[strategy][strategyIndex][j] * strategyShares
                    / sharesRedeemed[strategy][strategyIndex];
                totalWithdrawnAssets[j] += withdrawnAssets[j];
                assetsNotClaimed[strategy][j] -= withdrawnAssets[j];
                // there will be dust left after all vaults sync
            }

            emit StrategySharesRedeemClaimed(strategy, msg.sender, params.recipient, strategyShares, withdrawnAssets);
        }

        for (uint256 i; i < totalWithdrawnAssets.length; ++i) {
            if (totalWithdrawnAssets[i] > 0) {
                params.masterWallet.transfer(IERC20(assetGroup[i]), params.recipient, totalWithdrawnAssets[i]);
            }
        }
    }

    /**
     * @notice Instantly redeems strategy shares for assets.
     * @param redeemFastParams Parameters for calling redeem fast.
     * @param ghostStrategy Address of ghost strategy.
     * @param masterWallet Master wallet contract.
     * @param dhwStatus DHW status of strategies.
     * @return Amounts of withdrawn assets.
     */
    function redeemFast(
        RedeemFastParameterBag calldata redeemFastParams,
        address ghostStrategy,
        IMasterWallet masterWallet,
        mapping(address => uint256) storage dhwStatus
    ) external returns (uint256[] memory) {
        uint256[] memory withdrawnAssets = new uint256[](redeemFastParams.assetGroup.length);

        for (uint256 i; i < redeemFastParams.strategies.length; ++i) {
            if (redeemFastParams.strategies[i] == ghostStrategy || redeemFastParams.strategyShares[i] == 0) {
                continue;
            }

            if (dhwStatus[redeemFastParams.strategies[i]] > STRATEGY_IDLE) {
                revert StrategyNotReady(redeemFastParams.strategies[i]);
            }

            uint256[] memory strategyWithdrawnAssets = IStrategy(redeemFastParams.strategies[i]).redeemFast(
                redeemFastParams.strategyShares[i],
                address(masterWallet),
                redeemFastParams.assetGroup,
                redeemFastParams.withdrawalSlippages[i]
            );

            for (uint256 j = 0; j < strategyWithdrawnAssets.length; ++j) {
                withdrawnAssets[j] += strategyWithdrawnAssets[j];
            }

            emit StrategySharesFastRedeemed(
                redeemFastParams.strategies[i], redeemFastParams.strategyShares[i], strategyWithdrawnAssets
            );
        }

        return withdrawnAssets;
    }

    function _checkRole(bytes32 role, address account, ISpoolAccessControl accessControl) private view {
        if (!accessControl.hasRole(role, account)) {
            revert MissingRole(role, account);
        }
    }

    function _isViewExecution() private view returns (bool) {
        return tx.origin == address(0);
    }
}
