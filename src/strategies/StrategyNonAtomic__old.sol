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

error InitialDeposit();

error NotInitialDeposit();

error ProtocolActionNotFinished();

error InvalidDepositContinuation();

struct DhwExecutionInfo {
    uint256[] assetsFromDeposit;
    uint256[] assetsFromCompound;
    uint256 depositWorth;
    uint256 compoundWorth;
    uint256 withdrawalWorth;
    uint256 withdrawalFeeWorth;
    uint256 depositFeeWorth;
    uint256 totalSupply;
    uint256 usdWorth;
    uint256[2] feeShares;
}

struct DhwDepositContinuationExectuionInfo {
    uint256 feeWorth;
    uint256 legacyWorth;
    uint256 matchedDepositWorth;
    uint256 depositedDepositWorth;
    uint256 depositedCompoundWorth;
    uint256[2] feeShares;
    uint256 depositShares;
}

struct DhwWithdrawalContinuationExecutionInfo {
    uint256 feeWorth;
    uint256 legacyWorth;
    uint256 depositWorth;
    uint256[2] feeShares;
}

uint256 constant DEPOSIT_CONTINUATION = 1;
uint256 constant WITHDRAWAL_CONTINUATION = 2;

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
    uint256 internal _depositFeeShares;
    uint256 internal _depositShares;

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
        {
            // withdrawal includes base yield but not compound yield
            if (dhwParams.withdrawnShares > 0) {
                executionInfo.withdrawalWorth =
                    executionInfo.usdWorth * dhwParams.withdrawnShares / executionInfo.totalSupply;
                executionInfo.usdWorth -= executionInfo.withdrawalWorth;
                executionInfo.totalSupply -= dhwParams.withdrawnShares;

                executionInfo.feeShares =
                    _calculatePlatformFees(dhwInfo.yieldPercentage, dhwParams.platformFees, dhwParams.withdrawnShares);
                executionInfo.withdrawalFeeWorth = executionInfo.withdrawalWorth
                    * (executionInfo.feeShares[0] + executionInfo.feeShares[1])
                    / (executionInfo.feeShares[0] + executionInfo.feeShares[1] + dhwParams.withdrawnShares);
                executionInfo.withdrawalWorth -= executionInfo.withdrawalFeeWorth;
            }
        }

        // initiate deposit or withdrawal
        if (executionInfo.withdrawalWorth + executionInfo.depositWorth + executionInfo.compoundWorth == 0) {
            // no action needed - only base yield

            if (executionInfo.totalSupply < INITIAL_LOCKED_SHARES) {
                // should not happen in practice
                // do nothing, do not take fees
            } else {
                executionInfo.feeShares =
                    _calculatePlatformFees(dhwInfo.yieldPercentage, dhwParams.platformFees, executionInfo.totalSupply);

                _mint(dhwParams.platformFees.ecosystemFeeReceiver, executionInfo.feeShares[0]);
                _mint(dhwParams.platformFees.treasuryFeeReceiver, executionInfo.feeShares[1]);

                executionInfo.totalSupply += executionInfo.feeShares[0] + executionInfo.feeShares[1];
                dhwInfo.totalSstsAtDhw = executionInfo.totalSupply;
            }

            dhwInfo.assetsWithdrawn = new uint256[](dhwParams.assetGroup.length);
            dhwInfo.valueAtDhw = executionInfo.usdWorth;
        } else if (executionInfo.withdrawalWorth < executionInfo.depositWorth + executionInfo.compoundWorth) {
            // only deposit is needed

            // reserve assets for withdrawal
            uint256[] memory assetsForDeposit = new uint256[](dhwParams.assetGroup.length);
            dhwInfo.assetsWithdrawn = new uint256[](dhwParams.assetGroup.length);
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

            // deposit assets to protocol
            bool finished = _initializeDepositToProtocol(dhwParams.assetGroup, assetsToDeposit, dhwParams.slippages);

            if (finished) {
                revert("todo: do hard work - deposit finished");
            } else {
                // non-atomic deposit

                dhwInfo.continuationNeeded = true;
                _continuationType = DEPOSIT_CONTINUATION;

                // process withdrawal
                if (executionInfo.withdrawalWorth > 0) {
                    _burn(address(this), dhwParams.withdrawnShares);
                }

                // matching
                uint256 matchedCompoundWorth = executionInfo.withdrawalWorth > executionInfo.compoundWorth
                    ? executionInfo.compoundWorth
                    : executionInfo.withdrawalWorth;
                uint256 matchedDepositWorth = executionInfo.withdrawalWorth - matchedCompoundWorth;

                _depositShare = executionInfo.depositWorth - matchedDepositWorth;
                _compoundShare = executionInfo.compoundWorth - matchedCompoundWorth;

                // process deposit yield
                // - partial compound yield
                if (matchedCompoundWorth > 0) {
                    int256 compoundYieldPct =
                        _calculateYieldPercentage(executionInfo.usdWorth, executionInfo.usdWorth + matchedCompoundWorth);
                    dhwInfo.yieldPercentage +=
                        compoundYieldPct + dhwInfo.yieldPercentage * compoundYieldPct / YIELD_FULL_PERCENT_INT;

                    executionInfo.usdWorth += matchedCompoundWorth;
                }
                // - get fees
                if (dhwInfo.yieldPercentage > 0) {
                    executionInfo.feeShares = _calculatePlatformFees(
                        dhwInfo.yieldPercentage, dhwParams.platformFees, executionInfo.totalSupply
                    );

                    executionInfo.depositFeeWorth = executionInfo.usdWorth
                        * (executionInfo.feeShares[0] + executionInfo.feeShares[1])
                        / (executionInfo.feeShares[0] + executionInfo.feeShares[1] + executionInfo.totalSupply);
                }

                // process fees
                if (executionInfo.depositFeeWorth + executionInfo.withdrawalFeeWorth > 0) {
                    // - merge withdrawal and deposit yield
                    executionInfo.usdWorth += executionInfo.withdrawalFeeWorth;
                    // - calculate total fee shares
                    executionInfo.feeShares = _calculateShareDilution(
                        executionInfo.totalSupply,
                        executionInfo.usdWorth,
                        executionInfo.depositFeeWorth + executionInfo.withdrawalFeeWorth,
                        dhwParams.platformFees
                    );
                    executionInfo.totalSupply += executionInfo.feeShares[0] + executionInfo.feeShares[1];

                    // - distribute fee shares
                    _depositFeeShares = (executionInfo.feeShares[0] + executionInfo.feeShares[1])
                        * executionInfo.depositFeeWorth / (executionInfo.depositFeeWorth + executionInfo.withdrawalFeeWorth);
                    _withdrawalFeeShares = executionInfo.feeShares[0] + executionInfo.feeShares[1] - _depositFeeShares;
                }

                // process matched deposit
                if (matchedDepositWorth > 0) {
                    dhwInfo.sharesMinted =
                        _calculateDepositShares(executionInfo.usdWorth, matchedDepositWorth, executionInfo.totalSupply);

                    _depositShares = dhwInfo.sharesMinted;
                    executionInfo.usdWorth += matchedDepositWorth;
                    executionInfo.totalSupply += dhwInfo.sharesMinted;
                }
            }
        } else {
            // only withdrawal is needed

            executionInfo.totalSupply += dhwParams.withdrawnShares;
            executionInfo.usdWorth += executionInfo.withdrawalWorth + executionInfo.withdrawalFeeWorth;

            // reserve assets for withdrawal
            dhwInfo.assetsWithdrawn = new uint256[](dhwParams.assetGroup.length);
            for (uint256 i; i < dhwParams.assetGroup.length; ++i) {
                dhwInfo.assetsWithdrawn[i] = executionInfo.assetsFromDeposit[i] + executionInfo.assetsFromCompound[i];
            }

            // withdraw assets from protocol
            bool finished;
            {
                uint256 unmatchedWithdrawalWorth =
                    executionInfo.withdrawalWorth - executionInfo.depositWorth - executionInfo.compoundWorth;
                uint256 sharesToWithdraw = executionInfo.totalSupply * unmatchedWithdrawalWorth / executionInfo.usdWorth;
                unmatchedWithdrawalWorth = executionInfo.usdWorth * sharesToWithdraw / executionInfo.totalSupply;

                if (sharesToWithdraw > 0) {
                    finished =
                        _initializeWithdrawalFromProtocol(dhwParams.assetGroup, sharesToWithdraw, dhwParams.slippages);
                } else {
                    finished = true;
                }

                // how to handle shares if protocol doesn't immediately lower the worth of the strategy

                executionInfo.totalSupply -= dhwParams.withdrawnShares;
                executionInfo.usdWorth -= executionInfo.withdrawalWorth + executionInfo.withdrawalFeeWorth;
            }

            if (finished) {
                revert("todo: do hard work - withdrawal finished");
            } else {
                // non-atomic withdrawal

                dhwInfo.continuationNeeded = true;
                _continuationType = WITHDRAWAL_CONTINUATION;

                // process legacy yield
                // - compound yield
                {
                    int256 compoundYieldPct = _calculateYieldPercentage(
                        executionInfo.usdWorth, executionInfo.usdWorth + executionInfo.compoundWorth
                    );
                    dhwInfo.yieldPercentage +=
                        compoundYieldPct + dhwInfo.yieldPercentage * compoundYieldPct / YIELD_FULL_PERCENT_INT;
                    executionInfo.usdWorth += executionInfo.compoundWorth;
                }
                // - get fees
                if (dhwInfo.yieldPercentage > 0) {
                    executionInfo.feeShares = _calculatePlatformFees(
                        dhwInfo.yieldPercentage, dhwParams.platformFees, executionInfo.totalSupply
                    );

                    executionInfo.depositFeeWorth = executionInfo.usdWorth
                        * (executionInfo.feeShares[0] + executionInfo.feeShares[1])
                        / (executionInfo.feeShares[0] + executionInfo.feeShares[1] + executionInfo.totalSupply);
                }

                // process fees
                if (executionInfo.depositFeeWorth + executionInfo.withdrawalFeeWorth > 0) {
                    // - merge withdrawal and deposit yield
                    executionInfo.usdWorth += executionInfo.withdrawalFeeWorth;
                    // - calculate total fee shares
                    executionInfo.feeShares = _calculateShareDilution(
                        executionInfo.totalSupply,
                        executionInfo.usdWorth,
                        executionInfo.depositFeeWorth + executionInfo.withdrawalFeeWorth,
                        dhwParams.platformFees
                    );
                    executionInfo.totalSupply += executionInfo.feeShares[0] + executionInfo.feeShares[1];
                    // - distribute fee shares
                    _depositFeeShares = (executionInfo.feeShares[0] + executionInfo.feeShares[1])
                        * executionInfo.depositFeeWorth / (executionInfo.depositFeeWorth + executionInfo.withdrawalFeeWorth);
                    _withdrawalFeeShares = executionInfo.feeShares[0] + executionInfo.feeShares[1] - _depositFeeShares;
                }

                // process deposit
                if (executionInfo.depositWorth > 0) {
                    dhwInfo.sharesMinted = _calculateDepositShares(
                        executionInfo.usdWorth, executionInfo.depositWorth, executionInfo.totalSupply
                    );

                    _depositShares = dhwInfo.sharesMinted;
                    executionInfo.usdWorth += executionInfo.depositWorth;
                    executionInfo.totalSupply += dhwInfo.sharesMinted;
                }
            }
        }

        // transfer withdrawn assets
        if (executionInfo.withdrawalWorth > 0) {
            unchecked {
                for (uint256 i; i < dhwParams.assetGroup.length; ++i) {
                    IERC20(dhwParams.assetGroup[i]).safeTransfer(dhwParams.masterWallet, dhwInfo.assetsWithdrawn[i]);
                }
            }
        }

        // fix shares
        if (totalSupply() < executionInfo.totalSupply) {
            _mintToAddress(address(this), executionInfo.totalSupply - totalSupply());
        } else if (totalSupply() > executionInfo.totalSupply) {
            _burn(address(this), totalSupply() - executionInfo.totalSupply);
        }

        dhwInfo.totalSstsAtDhw = totalSupply();
        _yieldPercentage = dhwInfo.yieldPercentage;
    }

    function doHardWorkContinue(StrategyDhwContinuationParameterBag calldata dhwContParams)
        external
        returns (DhwInfo memory dhwInfo)
    {
        _checkRole(ROLE_STRATEGY_REGISTRY, msg.sender);

        // base yield from DHW initiation
        int256 baseYieldPct = _getYieldPercentage(dhwContParams.baseYield);

        if (_continuationType == DEPOSIT_CONTINUATION) {
            (bool finished, uint256 valueBefore, uint256 valueAfter) =
                _continueDepositToProtocol(dhwContParams.assetGroup, dhwContParams.continuationData);
            if (!finished) {
                revert ProtocolActionNotFinished();
            }
            if (valueBefore > valueAfter) {
                revert InvalidDepositContinuation();
            }

            uint256 totalSupply_ = totalSupply();
            dhwInfo.valueAtDhw = _getUsdWorth(dhwContParams.exchangeRates, dhwContParams.priceFeedManager);

            if (totalSupply_ < INITIAL_LOCKED_SHARES) {
                // initial deposit

                // in this case just check the USD worth after deposit and mint the shares for the strategy
                // - there couldn't have been any withdrawals yet
                // - ignore fees and fold compound into deposit
                // - in practice, this path is only taken on the first deposit
                dhwInfo.sharesMinted = _calculateInitialDepositShares(dhwInfo.valueAtDhw, totalSupply_);
                if (dhwInfo.sharesMinted > 0) {
                    dhwInfo.sharesMinted = _mintToAddress(address(this), dhwInfo.sharesMinted);
                }
            } else {
                // non-initial deposit

                DhwDepositContinuationExectuionInfo memory executionInfo;

                {
                    // split strategy worth into previous and deposited part
                    // - previousWorth: worth of strategy as before continuation
                    uint256 previousWorth = dhwInfo.valueAtDhw * valueBefore / valueAfter;
                    // - depositedWorth: worth of finalized deposit in continuation
                    uint256 depositedWorth = dhwInfo.valueAtDhw - previousWorth;

                    // split previous worth into legacy part, deposit part and fees for withdrawal
                    // - fees for withdrawal: fees taken on withdrawn amount
                    // - deposit: matched deposit amount
                    // - legacy: what was untouched since last DHW
                    executionInfo.feeWorth = previousWorth * _withdrawalFeeShares / totalSupply_;
                    executionInfo.matchedDepositWorth = previousWorth * _depositShares / totalSupply_;
                    executionInfo.legacyWorth =
                        previousWorth - executionInfo.feeWorth - executionInfo.matchedDepositWorth;

                    // split deposited part into deposit and compound
                    executionInfo.depositedCompoundWorth =
                        depositedWorth * _compoundShare / (_depositShare + _compoundShare);
                    executionInfo.depositedDepositWorth = depositedWorth - executionInfo.depositedCompoundWorth;
                }

                uint256 usdWorth = executionInfo.legacyWorth;
                totalSupply_ -= _withdrawalFeeShares + _depositFeeShares + _depositShares;

                // lets start with legacy part
                {
                    // calculate yield percentage for legacy part
                    dhwInfo.yieldPercentage =
                        _yieldPercentage + baseYieldPct + _yieldPercentage * baseYieldPct / YIELD_FULL_PERCENT_INT;

                    if (executionInfo.depositedCompoundWorth > 0) {
                        int256 compoundYieldPct =
                            _calculateYieldPercentage(usdWorth, usdWorth + executionInfo.depositedCompoundWorth);
                        dhwInfo.yieldPercentage +=
                            compoundYieldPct + dhwInfo.yieldPercentage * compoundYieldPct / YIELD_FULL_PERCENT_INT;

                        usdWorth += executionInfo.depositedCompoundWorth;
                    }

                    executionInfo.feeShares =
                        _calculatePlatformFees(dhwInfo.yieldPercentage, dhwContParams.platformFees, totalSupply_);
                    uint256 feeWorth = usdWorth * (executionInfo.feeShares[0] + executionInfo.feeShares[1])
                        / (executionInfo.feeShares[0] + executionInfo.feeShares[1] + totalSupply_);

                    usdWorth -= feeWorth;
                    executionInfo.feeWorth += feeWorth;
                }

                // now do the deposited part
                {
                    uint256 depositWorth = executionInfo.matchedDepositWorth;

                    if (depositWorth > 0 && baseYieldPct > 0) {
                        uint256 feeWorth = depositWorth * uint256(baseYieldPct)
                            / uint256(YIELD_FULL_PERCENT_INT + baseYieldPct)
                            * (dhwContParams.platformFees.ecosystemFeePct + dhwContParams.platformFees.treasuryFeePct)
                            / FULL_PERCENT;

                        depositWorth -= feeWorth;
                        executionInfo.feeWorth += feeWorth;
                    }

                    depositWorth += executionInfo.depositedDepositWorth;
                    executionInfo.depositShares = totalSupply_ * depositWorth / usdWorth;

                    usdWorth += depositWorth;
                    totalSupply_ += executionInfo.depositShares;
                }

                // now do the fees
                {
                    usdWorth += executionInfo.feeWorth;
                    executionInfo.feeShares = _calculateShareDilution(
                        totalSupply_, usdWorth, executionInfo.feeWorth, dhwContParams.platformFees
                    );

                    totalSupply_ += executionInfo.feeShares[0] + executionInfo.feeShares[1];
                }

                // fix shares
                if (totalSupply() > totalSupply_) {
                    _burn(address(this), totalSupply() - totalSupply_);
                } else {
                    _mint(address(this), totalSupply_ - totalSupply());
                }

                if (executionInfo.feeShares[0] + executionInfo.feeShares[1] > 0) {
                    _transfer(
                        address(this), dhwContParams.platformFees.ecosystemFeeReceiver, executionInfo.feeShares[0]
                    );
                    _transfer(address(this), dhwContParams.platformFees.treasuryFeeReceiver, executionInfo.feeShares[1]);
                }

                dhwInfo.sharesMinted = executionInfo.depositShares;
            }

            dhwInfo.assetsWithdrawn = new uint256[](dhwContParams.assetGroup.length);
            dhwInfo.continuationNeeded = false;
        } else {
            bool finished = _continueWithdrawalFromProtocol(dhwContParams.assetGroup, dhwContParams.continuationData);
            if (!finished) {
                revert ProtocolActionNotFinished();
            }

            uint256 totalSupply_ = totalSupply();
            dhwInfo.valueAtDhw = _getUsdWorth(dhwContParams.exchangeRates, dhwContParams.priceFeedManager);

            // collect withdrawn assets
            unchecked {
                dhwInfo.assetsWithdrawn = new uint256[](dhwContParams.assetGroup.length);
                for (uint256 i; i < dhwContParams.assetGroup.length; ++i) {
                    dhwInfo.assetsWithdrawn[i] = IERC20(dhwContParams.assetGroup[i]).balanceOf(address(this));
                    IERC20(dhwContParams.assetGroup[i]).safeTransfer(
                        dhwContParams.masterWallet, dhwInfo.assetsWithdrawn[i]
                    );
                }
            }

            DhwWithdrawalContinuationExecutionInfo memory executionInfo;

            // split strategy worth into legacy part, deposit part and fees for withdrawal
            // - fees for withdrawal: fees taken on withdrawn amount
            // - deposit: deposit amount
            // - legacy: what was untouched since last DHW
            executionInfo.feeWorth = dhwInfo.valueAtDhw * _withdrawalFeeShares / totalSupply_;
            executionInfo.depositWorth = dhwInfo.valueAtDhw * _depositShares / totalSupply_;
            executionInfo.legacyWorth = dhwInfo.valueAtDhw - executionInfo.feeWorth - executionInfo.depositWorth;

            uint256 usdWorth = executionInfo.legacyWorth;
            totalSupply_ -= _withdrawalFeeShares + _depositFeeShares + _depositShares;
            // lets start with legacy part
            {
                // calculate yield percentage for legacy part
                dhwInfo.yieldPercentage =
                    _yieldPercentage + baseYieldPct + _yieldPercentage * baseYieldPct / YIELD_FULL_PERCENT_INT;

                executionInfo.feeShares =
                    _calculatePlatformFees(dhwInfo.yieldPercentage, dhwContParams.platformFees, totalSupply_);
                uint256 feeWorth = usdWorth * (executionInfo.feeShares[0] + executionInfo.feeShares[1])
                    / (executionInfo.feeShares[0] + executionInfo.feeShares[1] + totalSupply_);
                usdWorth -= feeWorth;
                executionInfo.feeWorth += feeWorth;
            }

            // now to the deposited part
            {
                uint256 depositWorth = executionInfo.depositWorth;

                if (depositWorth > 0 && baseYieldPct > 0) {
                    uint256 feeWorth = depositWorth * uint256(baseYieldPct)
                        / uint256(YIELD_FULL_PERCENT_INT + baseYieldPct)
                        * (dhwContParams.platformFees.ecosystemFeePct + dhwContParams.platformFees.treasuryFeePct)
                        / FULL_PERCENT;
                    depositWorth -= feeWorth;
                    executionInfo.feeWorth += feeWorth;
                }

                dhwInfo.sharesMinted = totalSupply_ * depositWorth / usdWorth;

                usdWorth += depositWorth;
                totalSupply_ += dhwInfo.sharesMinted;
            }

            // now do the fees
            {
                usdWorth += executionInfo.feeWorth;
                executionInfo.feeShares =
                    _calculateShareDilution(totalSupply_, usdWorth, executionInfo.feeWorth, dhwContParams.platformFees);
                totalSupply_ += executionInfo.feeShares[0] + executionInfo.feeShares[1];
            }

            // fix shares
            if (totalSupply() > totalSupply_) {
                _burn(address(this), totalSupply() - totalSupply_);
            } else {
                _mint(address(this), totalSupply_ - totalSupply());
            }

            if (executionInfo.feeShares[0] + executionInfo.feeShares[1] > 0) {
                _transfer(address(this), dhwContParams.platformFees.ecosystemFeeReceiver, executionInfo.feeShares[0]);
                _transfer(address(this), dhwContParams.platformFees.treasuryFeeReceiver, executionInfo.feeShares[1]);
            }

            dhwInfo.continuationNeeded = false;
        }

        dhwInfo.totalSstsAtDhw = totalSupply();
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
                sstsToMint = _calculateInitialDepositShares(usdWorth[1], totalSupply_);
            }
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
        if (totalSupply_ < INITIAL_LOCKED_SHARES) {
            revert InitialDeposit();
        }
        if (valueBefore == 0) {
            revert StrategyWorthIsZero();
        }

        depositShares = totalSupply_ * valueAfter / valueBefore;
    }

    function _calculateInitialDepositShares(uint256 usdWorthAfter, uint256 totalSupply_)
        internal
        pure
        returns (uint256 depositShares)
    {
        //in practice, this should be called only once, for the initial deposit

        if (totalSupply_ >= INITIAL_LOCKED_SHARES) {
            revert NotInitialDeposit();
        }

        uint256 afterDepositShares = usdWorthAfter * INITIAL_SHARE_MULTIPLIER;

        if (afterDepositShares > totalSupply_) {
            depositShares = afterDepositShares - totalSupply_;
        }
        // otherwise no shares should be awarded for the deposit
        // - should not happen in practice
    }

    function _calculateFeeWorth(int256 yieldWorth, PlatformFees calldata platformFees)
        internal
        pure
        returns (uint256 feeWorth)
    {
        if (yieldWorth > 0) {
            feeWorth = uint256(yieldWorth) * (platformFees.ecosystemFeePct + platformFees.treasuryFeePct) / FULL_PERCENT;
        }
    }

    function _calculateShareDilution(
        uint256 totalSupply_,
        uint256 usdWorth,
        uint256 dilutionWorth,
        PlatformFees calldata platformFees
    ) internal pure returns (uint256[2] memory platformFeeShares) {
        uint256 dilutionShares = totalSupply_ * dilutionWorth / (usdWorth - dilutionWorth);

        platformFeeShares[0] =
            dilutionShares * platformFees.ecosystemFeePct / (platformFees.ecosystemFeePct + platformFees.treasuryFeePct);
        platformFeeShares[1] = dilutionShares - platformFeeShares[0];
    }

    function _calculatePlatformFees(int256 yieldPct, PlatformFees calldata platformFees, uint256 totalSupply_)
        internal
        virtual
        returns (uint256[2] memory platformFeeShares)
    {
        if (yieldPct > 0) {
            uint256 uint256YieldPct = uint256(yieldPct);

            uint256 yieldPctUsersPlusOne = uint256YieldPct
                * (FULL_PERCENT - platformFees.ecosystemFeePct - platformFees.treasuryFeePct)
                + FULL_PERCENT * YIELD_FULL_PERCENT;
            uint256 totalSupplyTimesYieldPct = totalSupply_ * uint256YieldPct;

            platformFeeShares[0] = totalSupplyTimesYieldPct * platformFees.ecosystemFeePct / yieldPctUsersPlusOne;
            platformFeeShares[1] = totalSupplyTimesYieldPct * platformFees.treasuryFeePct / yieldPctUsersPlusOne;
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

    function _mintToAddress(address recipient, uint256 sharesToMint) private returns (uint256 mintedShares) {
        uint256 totalSupply_ = totalSupply();
        mintedShares = sharesToMint;

        if (totalSupply_ < INITIAL_LOCKED_SHARES) {
            unchecked {
                uint256 lockedSharesLeftToMint = INITIAL_LOCKED_SHARES - totalSupply_;

                if (mintedShares < lockedSharesLeftToMint) {
                    lockedSharesLeftToMint = mintedShares;
                }

                mintedShares -= lockedSharesLeftToMint;

                _mint(INITIAL_LOCKED_SHARES_ADDRESS, lockedSharesLeftToMint);
            }
        }

        _mint(recipient, mintedShares);
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

    function _tryRedeemFromProtocol(address[] calldata tokens, uint256 ssts, uint256[] calldata slippages)
        internal
        returns (uint256[] memory withdrawnAssets)
    {
        withdrawnAssets = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            withdrawnAssets[i] = IERC20(tokens[i]).balanceOf(address(this));
        }

        bool finished = _initializeWithdrawalFromProtocol(tokens, ssts, slippages);
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
     */
    function _initializeWithdrawalFromProtocol(address[] calldata tokens, uint256 shares, uint256[] calldata slippages)
        internal
        virtual
        returns (bool finished);

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
