// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../access/Roles.sol";
import "../interfaces/CommonErrors.sol";
import "../interfaces/Constants.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/ISpoolAccessControl.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";

struct EmergencyWithdrawParams {
    bool removeStrategies;
    ISpoolAccessControl accessControl;
    address ghostStrategy;
    address emergencyWithdrawalWallet;
    IMasterWallet masterWallet;
}

struct ClaimStrategyShareWithdrawalsParams {
    address recipient;
    address ghostStrategy;
    ISpoolAccessControl accessControl;
    IMasterWallet masterWallet;
}

library StrategyRegistryLib {
    /**
     * @notice Emitted when a strategy is emergency withdrawn from.
     * @param strategy Strategy that was emergency withdrawn from.
     */
    event StrategyEmergencyWithdrawn(address indexed strategy);

    /**
     * @notice Strategy was removed
     * @param strategy Strategy address
     */
    event StrategyRemoved(address indexed strategy);

    /**
     * @notice Strategy shares have been redeemed
     * @param strategy Strategy address
     * @param owner Address that owns the shares
     * @param recipient Address that received the withdrawn funds
     * @param shares Amount of shares that were redeemed
     * @param assetsWithdrawn Amounts of withdrawn assets
     */
    event StrategySharesRedeemed(
        address indexed strategy,
        address indexed owner,
        address indexed recipient,
        uint256 shares,
        uint256[] assetsWithdrawn
    );

    /**
     * @notice Strategy shares redeem has been initiated
     * @param strategy Strategy address
     * @param owner Address that owns the shares
     * @param shares Amount of shares that were redeemed
     * @param strategyIndex DHW index of the strategy
     */
    event StrategySharesRedeemInitiated(
        address indexed strategy, address indexed owner, uint256 shares, uint256 strategyIndex
    );

    /**
     * @notice Strategy shares redeem has been claimed
     * @param strategy Strategy address
     * @param owner Address that redeemed the shares
     * @param recipient Address that received the withdrawn funds
     * @param shares Amount of shares that were redeemed
     * @param assetsWithdrawn Amounts of withdrawn assets
     */
    event StrategySharesRedeemClaimed(
        address indexed strategy,
        address indexed owner,
        address indexed recipient,
        uint256 shares,
        uint256[] assetsWithdrawn
    );

    /**
     * @notice Strategy shares were fast redeemed
     * @param strategy Strategy address
     * @param shares Amount of shares redeemed
     * @param assetsWithdrawn Amounts of withdrawn assets
     */
    event StrategySharesFastRedeemed(address indexed strategy, uint256 shares, uint256[] assetsWithdrawn);

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
                revert StrategyNotReady();
            }

            address[] memory assetGroup = IStrategy(strategies[i]).assets();

            uint256[] memory withdrawnAssets =
                IStrategy(strategies[i]).redeemShares(shares[i], redeemer, assetGroup, withdrawalSlippages[i]);

            emit StrategySharesRedeemed(strategies[i], redeemer, redeemer, shares[i], withdrawnAssets);
        }
    }

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
                revert StrategyNotReady();
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
