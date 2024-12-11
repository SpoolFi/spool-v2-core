// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/utils/math/Math.sol";
import "@openzeppelin/utils/math/SafeCast.sol";
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "../interfaces/Constants.sol";
import "../interfaces/IAssetGroupRegistry.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyNonAtomic.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/CommonErrors.sol";
import "../interfaces/Constants.sol";
import "../access/SpoolAccessControllable.sol";

/**
 * @notice Used when initial locked strategy shares are already minted and strategy usd value is zero.
 */
error StrategyWorthIsZero();

error InvalidDepositContinuation();

error InvalidDeposit();

struct DhwExecutionInfo {
    uint256[] assetsFromDeposit;
    uint256[] assetsFromCompound;
    uint256 depositWorth;
    uint256 compoundWorth;
    uint256 withdrawalWorth;
    uint256 depositedWorth;
    uint256 compoundedWorth;
    bool finished;
    uint256 withdrawalFeeWorth;
    uint256 legacyFeeWorth;
    uint256 usdWorth;
    uint256 totalSupply;
    uint256 undeductedWithdrawalWorth;
}

struct DhwContinuationExecutionInfo {
    bool finished;
    uint256 usdWorth;
    uint256 totalSupply;
    uint256 depositedWorth;
    uint256 otherWorth;
    uint256 feeWorth;
    uint256 feeShares;
}

uint256 constant DEPOSIT_CONTINUATION = 1;
uint256 constant WITHDRAWAL_CONTINUATION = 2;

// Base contract for non-atomic strategies
//                                                                             |
// Works for various strategies that have non-atomic operations with the
// underlying protocol. The strategy supports atomic and non-atomic deposits
// and withdrawals in all combinations. But there are some limitations:
//
// - the interaction must be fully atomic or fully non-atomic. This means that
//   it does not support the case where, e.g., part of withdrawal is executed
//   atomically, and the other part is executed non-atomically.
// - the interaction must be fully completed either in the `doHardWork` or in a
//   single `doHardWorkContinue` call. This means that it does not support the
//   case where, e.g., `doHardWorkContinue` should be called multiple times to
//   complete the interaction.
//
// The flow is as following:
//
// - `doHardWork` is called
//   - base yield is calculated
//   - withdrawal is calculated as if there is no compound yield
//     - withdrawals do not get compound yield since last DHW
//   - compound is prepared
//   - withdrawals are matched with deposits and compound yield
//     - first match whole compound yield, then deposits
//   - protocol interaction is initiated (either deposit or withdrawal)
//   - if interaction is atomic
//     - DHW finishes
//   - else
//     - preparations are made for continuation
// - `doHardWorkContinue` is called
//   - base yield since `doHardWork` is calculated
//   - protocol interaction is finalized
//   - fees are calculated
//     - fees for withdrawal are calculated based on `doHardWork` base yield
//     - fees for matched deposits are calculated based on `doHardWorkContinue` base yield
//     - fees for legacy deposits are calculated based on full yield
//   - DHW finishes

abstract contract StrategyNonAtomic is ERC20Upgradeable, SpoolAccessControllable, IStrategy, IStrategyNonAtomic {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IAssetGroupRegistry internal immutable _assetGroupRegistry;

    /// @notice Name of the strategy
    string private _strategyName;

    /// @dev ID of the asset group used by the strategy.
    uint256 private immutable _assetGroupId;
    /// @dev ID of the asset group used by the strategy.
    uint256 private _assetGroupIdStorage;
    // Only one of the above can be set. Use the `assetGroupId` function to read
    // the correct one.

    uint256 internal _continuationType;
    uint256 internal _depositShare;
    uint256 internal _compoundShare;
    int256 internal _yieldPercentage;
    uint256 internal _withdrawalFeeShares;
    uint256 internal _legacyFeeShares;
    uint256 internal _depositShares;
    uint256 internal _undeductedWithdrawalShares;

    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, uint256 assetGroupId_)
        SpoolAccessControllable(accessControl_)
    {
        if (address(assetGroupRegistry_) == address(0)) {
            revert ConfigurationAddressZero();
        }

        _assetGroupRegistry = assetGroupRegistry_;
        _assetGroupId = assetGroupId_;
    }

    function __Strategy_init(string memory strategyName_, uint256 assetGroupId_) internal onlyInitializing {
        if (bytes(strategyName_).length == 0) revert InvalidConfiguration();

        // asset group ID needs to be set exactly once,
        // either in constructor or initializer
        if (_assetGroupId == NULL_ASSET_GROUP_ID) {
            if (assetGroupId_ == NULL_ASSET_GROUP_ID) {
                revert InvalidAssetGroupIdInitialization();
            }
            _assetGroupIdStorage = assetGroupId_;
        } else {
            if (assetGroupId_ != NULL_ASSET_GROUP_ID) {
                revert InvalidAssetGroupIdInitialization();
            }
        }
        _assetGroupRegistry.validateAssetGroup(assetGroupId());

        _strategyName = strategyName_;

        __ERC20_init("Strategy Share Token", "SST");
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function assetGroupId() public view returns (uint256) {
        return _assetGroupId > 0 ? _assetGroupId : _assetGroupIdStorage;
    }

    function assets() public view returns (address[] memory) {
        return _assetGroupRegistry.listAssetGroup(assetGroupId());
    }

    function assetRatio() external view virtual returns (uint256[] memory);

    function strategyName() external view returns (string memory) {
        return _strategyName;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public virtual;

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public virtual;

    function doHardWork(StrategyDhwParameterBag calldata dhwParams) external returns (DhwInfo memory dhwInfo) {
        _checkRole(ROLE_STRATEGY_REGISTRY, msg.sender);

        DhwExecutionInfo memory executionInfo;

        // check initial state
        {
            dhwInfo.valueAtDhw = _getUsdWorth(dhwParams.exchangeRates, dhwParams.priceFeedManager);
            executionInfo.usdWorth = dhwInfo.valueAtDhw;
            executionInfo.totalSupply = totalSupply();
        }

        // check deposit
        executionInfo.assetsFromDeposit = new uint256[](dhwParams.assetGroup.length);
        {
            unchecked {
                for (uint256 i; i < dhwParams.assetGroup.length; ++i) {
                    executionInfo.assetsFromDeposit[i] = IERC20(dhwParams.assetGroup[i]).balanceOf(address(this));
                    // temporarily use deposit worth as a flag if deposit is needed
                    executionInfo.depositWorth += executionInfo.assetsFromDeposit[i];
                }
            }

            if (executionInfo.depositWorth > 0) {
                // assign true deposit worth
                executionInfo.depositWorth = dhwParams.priceFeedManager.assetToUsdCustomPriceBulk(
                    dhwParams.assetGroup, executionInfo.assetsFromDeposit, dhwParams.exchangeRates
                );
            }
        }

        // execute before checks
        beforeDepositCheck(executionInfo.assetsFromDeposit, dhwParams.slippages);
        beforeRedeemalCheck(dhwParams.withdrawnShares, dhwParams.slippages);

        // check yield
        {
            // base yield
            dhwInfo.yieldPercentage = _getYieldPercentage(dhwParams.baseYield);

            // compound yield
            bool compoundNeeded;
            (compoundNeeded, executionInfo.assetsFromCompound) =
                _prepareCompoundImpl(dhwParams.assetGroup, dhwParams.compoundSwapInfo);

            if (compoundNeeded) {
                executionInfo.compoundWorth = dhwParams.priceFeedManager.assetToUsdCustomPriceBulk(
                    dhwParams.assetGroup, executionInfo.assetsFromCompound, dhwParams.exchangeRates
                );
            }
        }

        // check withdrawal
        if (dhwParams.withdrawnShares > 0) {
            executionInfo.withdrawalWorth =
                executionInfo.usdWorth * dhwParams.withdrawnShares / executionInfo.totalSupply;
            executionInfo.usdWorth -= executionInfo.withdrawalWorth;
            executionInfo.totalSupply -= dhwParams.withdrawnShares;

            executionInfo.withdrawalFeeWorth = _calculatePlatformFeeWorth(
                dhwInfo.yieldPercentage, dhwParams.platformFees, executionInfo.withdrawalWorth
            );
            executionInfo.withdrawalWorth -= executionInfo.withdrawalFeeWorth;
        }

        dhwInfo.assetsWithdrawn = new uint256[](dhwParams.assetGroup.length);

        // initiate deposit or withdrawal
        if (executionInfo.depositWorth + executionInfo.compoundWorth > executionInfo.withdrawalWorth) {
            // deposit to protocol is needed

            // reserve assets for withdrawal
            uint256[] memory assetsForDeposit = new uint256[](dhwParams.assetGroup.length);
            for (uint256 i; i < dhwParams.assetGroup.length; ++i) {
                assetsForDeposit[i] = executionInfo.assetsFromDeposit[i] + executionInfo.assetsFromCompound[i];
                dhwInfo.assetsWithdrawn[i] = assetsForDeposit[i] * executionInfo.withdrawalWorth
                    / (executionInfo.depositWorth + executionInfo.compoundWorth);
                assetsForDeposit[i] -= dhwInfo.assetsWithdrawn[i];
            }

            // swap assets into correct ratio
            uint256[] memory assetsToDeposit;
            if (dhwParams.swapInfo.length > 0) {
                _swapAssets(dhwParams.assetGroup, assetsForDeposit, dhwParams.swapInfo);

                assetsToDeposit = new uint256[](dhwParams.assetGroup.length);
                for (uint256 i; i < dhwParams.assetGroup.length; ++i) {
                    assetsToDeposit[i] = IERC20(dhwParams.assetGroup[i]).balanceOf(address(this));
                }
            } else {
                assetsToDeposit = assetsForDeposit;
            }

            // match deposits
            if (executionInfo.withdrawalWorth > 0) {
                executionInfo.compoundedWorth = executionInfo.withdrawalWorth > executionInfo.compoundWorth
                    ? executionInfo.compoundWorth
                    : executionInfo.withdrawalWorth;
                executionInfo.depositedWorth = executionInfo.withdrawalWorth - executionInfo.compoundedWorth;
            }

            // deposit assets to protocol
            {
                executionInfo.finished =
                    _initializeDepositToProtocol(dhwParams.assetGroup, assetsToDeposit, dhwParams.slippages);

                emit DepositInitiated(assetsForDeposit, assetsToDeposit);

                uint256 depositShare = executionInfo.depositWorth - executionInfo.depositedWorth;
                uint256 compoundShare = executionInfo.compoundWorth - executionInfo.compoundedWorth;

                if (executionInfo.finished) {
                    // previous strategy worth
                    uint256 temp = dhwInfo.valueAtDhw;

                    dhwInfo.valueAtDhw = _getUsdWorth(dhwParams.exchangeRates, dhwParams.priceFeedManager);
                    if (dhwInfo.valueAtDhw < temp) {
                        revert InvalidDeposit();
                    }

                    // the actual worth of the deposit (after slippages, fees, ...)
                    uint256 depositedWorth = dhwInfo.valueAtDhw - temp;
                    // share of the deposit that came from compound yield
                    temp = depositedWorth * compoundShare / (compoundShare + depositShare);
                    executionInfo.compoundedWorth += temp;
                    executionInfo.depositedWorth += depositedWorth - temp;
                } else {
                    _continuationType = DEPOSIT_CONTINUATION;
                    _depositShare = depositShare;
                    _compoundShare = compoundShare;
                }
            }
        } else {
            // withdrawal from protocol is needed

            // reserve assets for withdrawal
            for (uint256 i; i < dhwParams.assetGroup.length; ++i) {
                dhwInfo.assetsWithdrawn[i] = executionInfo.assetsFromDeposit[i] + executionInfo.assetsFromCompound[i];
            }

            // withdraw assets from protocol
            {
                uint256 unmatchedWithdrawalWorth =
                    executionInfo.withdrawalWorth - executionInfo.depositWorth - executionInfo.compoundWorth;
                uint256 sharesToWithdraw = executionInfo.totalSupply * unmatchedWithdrawalWorth / executionInfo.usdWorth;

                if (sharesToWithdraw > 0) {
                    bool sharesDeducted;
                    (executionInfo.finished, sharesDeducted) =
                        _initializeWithdrawalFromProtocol(dhwParams.assetGroup, sharesToWithdraw, dhwParams.slippages);

                    if (!sharesDeducted) {
                        executionInfo.undeductedWithdrawalWorth = unmatchedWithdrawalWorth;
                    }

                    emit WithdrawalInitiated(sharesToWithdraw);
                } else {
                    executionInfo.finished = true;
                }
            }

            executionInfo.compoundedWorth = executionInfo.compoundWorth;
            executionInfo.depositedWorth = executionInfo.depositWorth;

            if (executionInfo.finished) {
                dhwInfo.valueAtDhw = _getUsdWorth(dhwParams.exchangeRates, dhwParams.priceFeedManager);

                for (uint256 i; i < dhwParams.assetGroup.length; ++i) {
                    dhwInfo.assetsWithdrawn[i] = IERC20(dhwParams.assetGroup[i]).balanceOf(address(this));
                }
            } else {
                _continuationType = WITHDRAWAL_CONTINUATION;
            }
        }

        // process compound yield
        if (executionInfo.compoundedWorth > 0) {
            int256 compoundYieldPct = _calculateYieldPercentage(
                executionInfo.usdWorth, executionInfo.usdWorth + executionInfo.compoundedWorth
            );
            dhwInfo.yieldPercentage +=
                compoundYieldPct + dhwInfo.yieldPercentage * compoundYieldPct / YIELD_FULL_PERCENT_INT;
            executionInfo.usdWorth += executionInfo.compoundedWorth;
        }

        if (executionInfo.totalSupply < INITIAL_LOCKED_SHARES) {
            // withdrawals were not possible yet
            // attribute all yield to deposits, if any
            // do not take any fees

            // this should only happen for the initial deposit in practice

            // process deposits
            if (executionInfo.depositedWorth > 0) {
                uint256 initialShares;
                (dhwInfo.sharesMinted, initialShares) = _calculateInitialDepositShares(
                    executionInfo.usdWorth + executionInfo.depositedWorth, executionInfo.totalSupply
                );

                executionInfo.totalSupply += initialShares;
                _mint(INITIAL_LOCKED_SHARES_ADDRESS, initialShares);
            }
        } else {
            // process fees
            // - get fees
            if (dhwInfo.yieldPercentage > 0) {
                executionInfo.legacyFeeWorth =
                    _calculatePlatformFeeWorth(dhwInfo.yieldPercentage, dhwParams.platformFees, executionInfo.usdWorth);
            }
            // - take fees
            if (executionInfo.legacyFeeWorth + executionInfo.withdrawalFeeWorth > 0) {
                executionInfo.usdWorth += executionInfo.withdrawalFeeWorth;

                uint256 feeShares = _calculateShareDilution(
                    executionInfo.totalSupply,
                    executionInfo.usdWorth,
                    executionInfo.legacyFeeWorth + executionInfo.withdrawalFeeWorth
                );
                executionInfo.totalSupply += feeShares;

                if (executionInfo.finished) {
                    _mintProtocolFeeShares(feeShares, dhwParams.platformFees);
                } else {
                    _legacyFeeShares = feeShares * executionInfo.legacyFeeWorth
                        / (executionInfo.legacyFeeWorth + executionInfo.withdrawalFeeWorth);
                    _withdrawalFeeShares = feeShares - _legacyFeeShares;
                }
            }
            // - add back shares for undeducted withdrawal
            if (executionInfo.undeductedWithdrawalWorth > 0) {
                executionInfo.usdWorth += executionInfo.undeductedWithdrawalWorth;
                uint256 undeductedWithdrawalShares = _calculateShareDilution(
                    executionInfo.totalSupply, executionInfo.usdWorth, executionInfo.undeductedWithdrawalWorth
                );
                executionInfo.totalSupply += undeductedWithdrawalShares;

                if (!executionInfo.finished) {
                    _undeductedWithdrawalShares = undeductedWithdrawalShares;
                }
            }

            // process deposits
            if (executionInfo.depositedWorth > 0) {
                dhwInfo.sharesMinted = _calculateDepositShares(
                    executionInfo.usdWorth, executionInfo.depositedWorth, executionInfo.totalSupply
                );
            }
        }
        executionInfo.usdWorth += executionInfo.depositedWorth;
        executionInfo.totalSupply += dhwInfo.sharesMinted;

        if (!executionInfo.finished) {
            _depositShares = dhwInfo.sharesMinted;
            _yieldPercentage = dhwInfo.yieldPercentage;
            dhwInfo.continuationNeeded = true;
        }

        // transfer withdrawn assets
        if (executionInfo.withdrawalWorth > 0) {
            unchecked {
                for (uint256 i; i < dhwParams.assetGroup.length; ++i) {
                    if (dhwInfo.assetsWithdrawn[i] > 0) {
                        IERC20(dhwParams.assetGroup[i]).safeTransfer(dhwParams.masterWallet, dhwInfo.assetsWithdrawn[i]);
                    }
                }
            }
        }

        // fix shares
        if (totalSupply() < executionInfo.totalSupply) {
            _mint(address(this), executionInfo.totalSupply - totalSupply());
        } else if (totalSupply() > executionInfo.totalSupply) {
            _burn(address(this), totalSupply() - executionInfo.totalSupply);
        }

        dhwInfo.totalSstsAtDhw = executionInfo.totalSupply;
    }

    function doHardWorkContinue(StrategyDhwContinueParameterBag calldata dhwContParams)
        external
        returns (DhwInfo memory dhwInfo)
    {
        _checkRole(ROLE_STRATEGY_REGISTRY, msg.sender);

        DhwContinuationExecutionInfo memory executionInfo;

        executionInfo.totalSupply = totalSupply();

        int256 baseYieldPct = _getYieldPercentage(dhwContParams.baseYield);
        dhwInfo.yieldPercentage =
            _yieldPercentage + baseYieldPct + _yieldPercentage * baseYieldPct / YIELD_FULL_PERCENT_INT;

        dhwInfo.assetsWithdrawn = new uint256[](dhwContParams.assetGroup.length);

        if (_continuationType == DEPOSIT_CONTINUATION) {
            (bool finished, uint256 valueBefore, uint256 valueAfter) =
                _continueDepositToProtocol(dhwContParams.assetGroup, dhwContParams.continuationData);

            if (!finished) {
                revert ProtocolActionNotFinished();
            }
            if (valueBefore > valueAfter) {
                revert InvalidDepositContinuation();
            }

            dhwInfo.valueAtDhw = _getUsdWorth(dhwContParams.exchangeRates, dhwContParams.priceFeedManager);
            executionInfo.otherWorth = dhwInfo.valueAtDhw * valueBefore / valueAfter;
            executionInfo.depositedWorth = dhwInfo.valueAtDhw - executionInfo.otherWorth;
        } else {
            bool finished = _continueWithdrawalFromProtocol(dhwContParams.assetGroup, dhwContParams.continuationData);
            if (!finished) {
                revert ProtocolActionNotFinished();
            }

            dhwInfo.valueAtDhw = _getUsdWorth(dhwContParams.exchangeRates, dhwContParams.priceFeedManager);
            executionInfo.otherWorth = dhwInfo.valueAtDhw;
            executionInfo.totalSupply -= _undeductedWithdrawalShares;

            // collect withdrawn assets
            for (uint256 i; i < dhwContParams.assetGroup.length; ++i) {
                dhwInfo.assetsWithdrawn[i] = IERC20(dhwContParams.assetGroup[i]).balanceOf(address(this));

                if (dhwInfo.assetsWithdrawn[i] > 0) {
                    IERC20(dhwContParams.assetGroup[i]).safeTransfer(
                        dhwContParams.masterWallet, dhwInfo.assetsWithdrawn[i]
                    );
                }
            }
        }

        if (executionInfo.totalSupply < INITIAL_LOCKED_SHARES) {
            // withdrawals were not possible yet
            // attribute all yield to deposits, if any
            // do not take any fees

            // this should only happen for the initial deposit in practice

            if (executionInfo.otherWorth + executionInfo.depositedWorth > 0) {
                uint256 initialShares;
                (dhwInfo.sharesMinted, initialShares) =
                    _calculateInitialDepositShares(dhwInfo.valueAtDhw, executionInfo.totalSupply);

                _mint(INITIAL_LOCKED_SHARES_ADDRESS, initialShares);
                executionInfo.totalSupply += initialShares + dhwInfo.sharesMinted;
            }
        } else {
            // reconstruct state
            uint256 withdrawalFeeWorth = executionInfo.otherWorth * _withdrawalFeeShares / executionInfo.totalSupply;
            uint256 finishedDepositWorth = executionInfo.otherWorth * _depositShares / executionInfo.totalSupply;
            uint256 legacyWorth = executionInfo.otherWorth - withdrawalFeeWorth - finishedDepositWorth;

            uint256 depositedDepositWorth =
                executionInfo.depositedWorth * _depositShare / (_depositShare + _compoundShare);
            uint256 depositedCompoundWorth = executionInfo.depositedWorth - depositedDepositWorth;

            // calculate deposited compound yield percentage
            if (depositedCompoundWorth > 0) {
                int256 compoundYieldPct = _calculateYieldPercentage(legacyWorth, legacyWorth + depositedCompoundWorth);
                dhwInfo.yieldPercentage +=
                    compoundYieldPct + dhwInfo.yieldPercentage * compoundYieldPct / YIELD_FULL_PERCENT_INT;
            }

            // process fees
            executionInfo.totalSupply -= _depositShares + _withdrawalFeeShares + _legacyFeeShares;
            executionInfo.usdWorth = legacyWorth + depositedCompoundWorth;

            // - for legacy
            if (dhwInfo.yieldPercentage > 0) {
                executionInfo.feeWorth = _calculatePlatformFeeWorth(
                    dhwInfo.yieldPercentage, dhwContParams.platformFees, executionInfo.usdWorth
                );
            }
            // - for withdrawal
            if (withdrawalFeeWorth > 0) {
                executionInfo.feeWorth += withdrawalFeeWorth;
                executionInfo.usdWorth += withdrawalFeeWorth;
            }
            // - for finished deposit
            if (baseYieldPct > 0 && finishedDepositWorth > 0) {
                uint256 finishedDepositFeeWorth =
                    _calculatePlatformFeeWorth(baseYieldPct, dhwContParams.platformFees, finishedDepositWorth);
                executionInfo.feeWorth += finishedDepositFeeWorth;
                executionInfo.usdWorth += finishedDepositFeeWorth;
                finishedDepositWorth -= finishedDepositFeeWorth;
            }
            // - mint fee shares
            executionInfo.feeShares =
                _calculateShareDilution(executionInfo.totalSupply, executionInfo.usdWorth, executionInfo.feeWorth);
            executionInfo.totalSupply += executionInfo.feeShares;
            if (executionInfo.feeShares > 0) {
                _mintProtocolFeeShares(executionInfo.feeShares, dhwContParams.platformFees);
            }

            // process deposits
            if (depositedDepositWorth + finishedDepositWorth > 0) {
                dhwInfo.sharesMinted = _calculateDepositShares(
                    executionInfo.usdWorth, depositedDepositWorth + finishedDepositWorth, executionInfo.totalSupply
                );
                executionInfo.totalSupply += dhwInfo.sharesMinted;
                executionInfo.usdWorth += depositedDepositWorth + finishedDepositWorth;
            }
        }

        // fix shares
        if (totalSupply() < executionInfo.totalSupply) {
            _mint(address(this), executionInfo.totalSupply - totalSupply());
        } else if (totalSupply() > executionInfo.totalSupply) {
            _burn(address(this), totalSupply() - executionInfo.totalSupply);
        }

        dhwInfo.totalSstsAtDhw = executionInfo.totalSupply;
    }

    function claimShares(address smartVault, uint256 amount) external onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender) {
        _transfer(address(this), smartVault, amount);
    }

    function releaseShares(address releasee, uint256 amount) external {
        if (
            !_accessControl.hasRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
                && !_accessControl.hasRole(ROLE_STRATEGY_REGISTRY, msg.sender)
        ) {
            revert NotShareReleasor(msg.sender);
        }

        _transfer(releasee, address(this), amount);
    }

    /**
     * @dev Will try to redeem. If not atomic it will revert.
     */
    function redeemFast(
        uint256 shares,
        address masterWallet,
        address[] calldata assetGroup,
        uint256[] calldata slippages
    ) external returns (uint256[] memory) {
        // try to redeem, revert if not atomic
        if (
            !_accessControl.hasRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
                && !_accessControl.hasRole(ROLE_STRATEGY_REGISTRY, msg.sender)
        ) {
            revert NotFastRedeemer(msg.sender);
        }

        return _redeemShares(shares, address(this), masterWallet, assetGroup, slippages);
    }

    /**
     * @dev Will try to redeem. If not atomic it will revert.
     */
    function redeemShares(uint256 shares, address redeemer, address[] calldata assetGroup, uint256[] calldata slippages)
        external
        returns (uint256[] memory)
    {
        _checkRole(ROLE_STRATEGY_REGISTRY, msg.sender);

        return _redeemShares(shares, redeemer, redeemer, assetGroup, slippages);
    }

    /**
     * @dev Is only called when reallocating.
     * @dev Will try to deposit. If not atomic it will revert.
     */
    function depositFast(
        address[] calldata assetGroup,
        uint256[] calldata exchangeRates,
        IUsdPriceFeedManager priceFeedManager,
        uint256[] calldata slippages,
        SwapInfo[] calldata swapInfo
    ) external returns (uint256 sstsToMint) {
        _checkRole(ROLE_SMART_VAULT_MANAGER, msg.sender);

        // get amount of assets available to deposit
        uint256[] memory assetsToDeposit = new uint256[](assetGroup.length);
        for (uint256 i; i < assetGroup.length; ++i) {
            assetsToDeposit[i] = IERC20(assetGroup[i]).balanceOf(address(this));
        }

        // swap assets
        _swapAssets(assetGroup, assetsToDeposit, swapInfo);
        uint256[] memory assetsDeposited = new uint256[](assetGroup.length);
        for (uint256 i; i < assetGroup.length; ++i) {
            assetsDeposited[i] = IERC20(assetGroup[i]).balanceOf(address(this));
        }

        // deposit assets
        uint256[2] memory usdWorth;
        // usdWorth[0] -> worth before deposit
        // usdWorth[1] -> worth after deposit
        usdWorth[0] = _getUsdWorth(exchangeRates, priceFeedManager);
        {
            bool finished = _initializeDepositToProtocol(assetGroup, assetsDeposited, slippages);
            if (!finished) {
                revert ProtocolActionNotFinished();
            }
        }
        usdWorth[1] = _getUsdWorth(exchangeRates, priceFeedManager);

        // mint SSTs
        {
            uint256 totalSupply_ = totalSupply();
            if (totalSupply_ > INITIAL_LOCKED_SHARES) {
                sstsToMint = _calculateDepositShares(usdWorth[0], usdWorth[1] - usdWorth[0], totalSupply());
            } else {
                uint256 initialShares;
                (sstsToMint, initialShares) = _calculateInitialDepositShares(usdWorth[1], totalSupply_);
                _mint(INITIAL_LOCKED_SHARES_ADDRESS, initialShares);
            }

            _mint(address(this), sstsToMint);
        }

        emit Deposited(sstsToMint, usdWorth[1] - usdWorth[0], assetsToDeposit, assetsDeposited);

        return sstsToMint;
    }

    /**
     * @dev Will try to withdraw. If not atomic it will probably revert.
     * @dev Implementation specific.
     * @dev In case emergency withdrawal is needed, strategy would probably need to be upgraded.
     */
    function emergencyWithdraw(uint256[] calldata slippages, address recipient)
        external
        onlyRole(ROLE_STRATEGY_REGISTRY, msg.sender)
    {
        _emergencyWithdrawImpl(slippages, recipient);
    }

    function getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint256)
    {
        return _getUsdWorth(exchangeRates, priceFeedManager);
    }

    function getProtocolRewards() external onlyViewExecution returns (address[] memory, uint256[] memory) {
        return _getProtocolRewardsInternal();
    }

    /* ========== PRIVATE/INTERNAL FUNCTIONS ========== */

    function _resetAllowance(IERC20 token, address spender) internal {
        if (token.allowance(address(this), spender) > 0) {
            token.safeApprove(spender, 0);
        }
    }

    function _resetAndApprove(IERC20 token, address spender, uint256 amount) internal {
        _resetAllowance(token, spender);
        token.safeApprove(spender, amount);
    }

    function _calculateDepositShares(uint256 valueBefore, uint256 valueAfter, uint256 totalSupply_)
        internal
        pure
        returns (uint256 depositShares)
    {
        if (valueBefore == 0) {
            revert StrategyWorthIsZero();
        }

        depositShares = totalSupply_ * valueAfter / valueBefore;
    }

    function _calculateInitialDepositShares(uint256 usdWorthAfter, uint256 totalSupply_)
        internal
        pure
        returns (uint256 depositShares, uint256 initialShares)
    {
        // in practice, this should be called only once, for the initial deposit

        uint256 afterDepositShares = usdWorthAfter * INITIAL_SHARE_MULTIPLIER;

        initialShares = INITIAL_LOCKED_SHARES - totalSupply_;

        if (afterDepositShares > totalSupply_) {
            unchecked {
                depositShares = afterDepositShares - totalSupply_;

                if (depositShares < initialShares) {
                    initialShares = depositShares;
                }

                depositShares -= initialShares;
            }
        }
        // otherwise no shares should be awarded for the deposit
        // - should not happen in practice
    }

    function _calculatePlatformFeeWorth(int256 yieldPct, PlatformFees calldata platformFees, uint256 totalWorth)
        internal
        pure
        returns (uint256 platformFeeWorth)
    {
        if (yieldPct > 0) {
            uint256 uYieldPct = uint256(yieldPct);

            platformFeeWorth = totalWorth * uYieldPct * (platformFees.ecosystemFeePct + platformFees.treasuryFeePct)
                / (YIELD_FULL_PERCENT + uYieldPct) / FULL_PERCENT;
        }
    }

    function _calculateShareDilution(uint256 totalSupply_, uint256 usdWorth, uint256 dilutionWorth)
        internal
        pure
        returns (uint256)
    {
        return totalSupply_ * dilutionWorth / (usdWorth - dilutionWorth);
    }

    function _mintProtocolFeeShares(uint256 protocolFeeShares, PlatformFees calldata platformFees) internal {
        if (protocolFeeShares > 0) {
            // ecosystem fees
            uint256 feeShares = protocolFeeShares * platformFees.ecosystemFeePct
                / (platformFees.ecosystemFeePct + platformFees.treasuryFeePct);
            _mint(platformFees.ecosystemFeeReceiver, feeShares);

            // treasury fees
            unchecked {
                feeShares = protocolFeeShares - feeShares;
            }
            _mint(platformFees.treasuryFeeReceiver, feeShares);

            emit PlatformFeesCollected(address(this), protocolFeeShares);
        }
    }

    function _calculateYieldPercentage(uint256 previousValue, uint256 currentValue)
        internal
        pure
        returns (int256 yieldPercentage)
    {
        if (currentValue > previousValue) {
            yieldPercentage = int256((currentValue - previousValue) * YIELD_FULL_PERCENT / previousValue);
        } else if (previousValue > currentValue) {
            yieldPercentage = -int256((previousValue - currentValue) * YIELD_FULL_PERCENT / previousValue);
        }
    }

    function _redeemShares(
        uint256 shares,
        address shareOwner,
        address recipient,
        address[] calldata assetGroup,
        uint256[] calldata slippages
    ) internal returns (uint256[] memory) {
        // try to redeem shares from protocol
        uint256[] memory assetsWithdrawn = _tryRedeemFromProtocol(assetGroup, shares, slippages);
        _burn(shareOwner, shares);

        // transfer assets to recipient (master wallet in case of redeemFast)
        unchecked {
            for (uint256 i; i < assetGroup.length; ++i) {
                IERC20(assetGroup[i]).safeTransfer(recipient, assetsWithdrawn[i]);
            }
        }

        return assetsWithdrawn;
    }

    /**
     * @dev Will try to withdraw. If not atomic it will revert.
     */
    function _tryRedeemFromProtocol(address[] calldata tokens, uint256 shares, uint256[] calldata slippages)
        internal
        returns (uint256[] memory withdrawnAssets)
    {
        withdrawnAssets = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            withdrawnAssets[i] = IERC20(tokens[i]).balanceOf(address(this));
        }

        (bool finished,) = _initializeWithdrawalFromProtocol(tokens, shares, slippages);
        if (!finished) {
            revert ProtocolActionNotFinished();
        }

        for (uint256 i; i < tokens.length; ++i) {
            withdrawnAssets[i] = IERC20(tokens[i]).balanceOf(address(this)) - withdrawnAssets[i];
        }
    }

    function _isViewExecution() internal view returns (bool) {
        return tx.origin == address(0);
    }

    /* ========== ABSTRACT FUNCTIONS ========== */

    /**
     * @dev Gets the USD worth of the strategy.
     * @param exchangeRates Exchange rates between the assets and the USD.
     * @param priceFeedManager Price feed manager contract.
     * @return usdWorth USD worth of the strategy.
     */
    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        virtual
        returns (uint256 usdWorth);

    /**
     * @dev Gets the base yield in percentage.
     * @param manualYield Externally provided yield percentage, if it can't be obtained from on-chain data.
     * @return yieldPercentage Base yield expressed according to the YIELD_FULL_PERCENT_INT.
     */
    function _getYieldPercentage(int256 manualYield) internal virtual returns (int256 yieldPercentage);

    /**
     * @dev Initializes a deposit to the protocol.
     * @param tokens Addresses of the asset tokens being deposited.
     * @param assets Amounts of the asset tokens to deposit.
     * @param slippages Slippages used to constrain the deposit into the protocol.
     * @return finished True if the deposit is finished, i.e., atomic deposits; false otherwise.
     */
    function _initializeDepositToProtocol(
        address[] calldata tokens,
        uint256[] memory assets,
        uint256[] calldata slippages
    ) internal virtual returns (bool finished);

    /**
     * @dev Initializes a withdrawal from the protocol.
     * @param tokens Addresses of the asset tokens being received upon withdrawal.
     * @param shares Amount of strategy shares to withdraw.
     * @param slippages Slippages used to constrain the withdrawal from the protocol.
     * @return finished True if the deposit is finished, i.e., atomic withdrawal; false otherwise.
     * @return sharesDeducted True if the shares were deducted by the protocol, false otherwise.
     */
    function _initializeWithdrawalFromProtocol(address[] calldata tokens, uint256 shares, uint256[] calldata slippages)
        internal
        virtual
        returns (bool finished, bool sharesDeducted);

    /**
     * @dev Continues the deposit to the protocol.
     * @dev Base strategy should be able to calculate the USD value of the deposit based on the
     * @dev - USD worth after continuation
     * @dev - valueBefore return parameter
     * @dev - valueAfter return parameter
     * @dev in a proportional manner.
     * @param tokens Addresses of the asset tokens being deposited.
     * @param continuationData Data needed to continue the deposit.
     * @return finished True if the deposit is finished; false otherwise.
     * @return valueBefore Some measure of the value of the strategy before the continuation.
     * @return valueAfter Some measure of the value of the strategy after the continuation.
     */
    function _continueDepositToProtocol(address[] calldata tokens, bytes calldata continuationData)
        internal
        virtual
        returns (bool finished, uint256 valueBefore, uint256 valueAfter);

    /**
     * @dev Continues the withdrawal from the protocol.
     * @param tokens Addresses of the asset tokens being received upon withdrawal.
     * @param continuationData Data needed to continue the withdrawal.
     * @return finished True if the withdrawal is finished; false otherwise.
     */
    function _continueWithdrawalFromProtocol(address[] calldata tokens, bytes calldata continuationData)
        internal
        virtual
        returns (bool finished);

    /**
     * @dev Prepares the protocol rewards for compounding, if needed.
     * @dev Typically involves:
     * @dev - claiming the rewards from the protocol
     * @dev - swapping the rewards to the asset tokens
     * @dev Should not attempt to deposit the rewards into the protocol, base strategy will handle that.
     * @param tokens Addresses of the asset tokens to compound.
     * @param compoundSwapInfo Information needed to swap the rewards to the asset tokens.
     * @return compoundNeeded True if the rewards need to be compounded; false otherwise.
     * @return assetsToCompound Amounts of the asset tokens to compound.
     */
    function _prepareCompoundImpl(address[] calldata tokens, SwapInfo[] calldata compoundSwapInfo)
        internal
        virtual
        returns (bool compoundNeeded, uint256[] memory assetsToCompound);

    /**
     * @dev Swaps the assets to the desired ratio, if needed.
     * @param tokens Addresses of the asset tokens being swapped.
     * @param toSwap Amounts of the asset tokens to swap.
     * @param swapInfo Information needed to swap the assets.
     */
    function _swapAssets(address[] memory tokens, uint256[] memory toSwap, SwapInfo[] calldata swapInfo)
        internal
        virtual;

    /**
     * @dev Withdraws all assets from the protocol in case of emergency.
     * @dev Should revert if the withdrawal is not atomic.
     * @param slippages Slippages used to constrain the emergency withdrawal.
     * @param recipient Address to receive the withdrawn assets.
     */
    function _emergencyWithdrawImpl(uint256[] calldata slippages, address recipient) internal virtual;

    /**
     * @dev Gets the protocol rewards for compounding.
     * @return tokens Addresses of the reward tokens.
     * @return amounts Amounts of the reward tokens.
     */
    function _getProtocolRewardsInternal()
        internal
        virtual
        returns (address[] memory tokens, uint256[] memory amounts);

    /* ========== MODIFIERS ========== */

    /**
     * @notice Only allows execution in the view mode.
     * @dev Reverts when the transaction is not a view execution.
     */
    modifier onlyViewExecution() {
        require(_isViewExecution());
        _;
    }
}
