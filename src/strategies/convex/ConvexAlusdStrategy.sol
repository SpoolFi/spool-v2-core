// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../external/interfaces/strategies/convex/IBaseRewardPool.sol";
import "../../external/interfaces/strategies/convex/IBooster.sol";
import "../curve/CurveAdapter.sol";
import "../Strategy.sol";
import "../helpers/StrategyManualYieldVerifier.sol";

error StratBeforeDepositCheckFailed();
error StratBeforeRedeemalCheckFailed();
error StratDepositSlippagesFailed();
error StratRedeemSlippagesFailed();

// multiple assets
// multiple rewards
// slippages
// - mode selection: slippages[0]
// - DHW with deposit: slippages[0] == 0
//   - beforeDepositCheck: slippages[1..2*tokenLength]
//   - beforeRedeemalCheck: slippages[2*tokenLength+1..2*tokenLength+2]
//   - compound: slippages[2*tokenLength+3]
//   - _depositToProtocol: slippages[2*tokenLength+4]
// - DHW with withdrawal: slippages[0] == 1
//   - beforeDepositCheck: slippages[1..2*tokenLength]
//   - beforeRedeemalCheck: slippages[2*tokenLength+1..2*tokenLength+2]
//   - compound: slippages[2*tokenLength+3]
//   - _redeemFromProtocol: slippages[2*tokenLength+4..2*tokenLength+5]
// - reallocate: slippages[0] == 2
//   - beforeDepositCheck: depositSlippages[1..2*tokenLength]
//   - _depositToProtocol: depositSlippages[2*tokenLength+1]
//   - beforeRedeemalCheck: withdrawalSlippages[1..2]
//   - _redeemFromProtocol: withdrawalSlippages[3..tokenLength+2]
// - redeemFast or emergencyWithdraw: slippages[0] == 3
//   - _redeemFromProtocol or _emergencyWithdrawImpl: slippages[1..tokenLength]
contract ConvexAlusdStrategy is
    StrategyManualYieldVerifier,
    Strategy,
    CurveMetaPoolAdapter,
    Curve3CoinPoolAdapter,
    CurveUint256PoolAdapter
{
    using SafeERC20 for IERC20;
    using uint16a16Lib for uint16a16;

    uint256 public tokenLength;

    ISwapper public immutable swapper;

    address private _pool;
    address private _lpToken;
    uint16a16 _assetMapping;

    address private _poolMeta;

    uint256 constant BASE_REWARD_COUNT = 2;
    IBooster public immutable booster;
    IBaseRewardPool public crvRewards;
    address public crvRewardToken;
    address public cvxRewardToken;
    uint96 public pid;
    bool extraRewards;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        uint256 assetGroupId_,
        ISwapper swapper_,
        IBooster booster_,
        int128 coinIndexBase_
    ) Strategy(assetGroupRegistry_, accessControl_, assetGroupId_) CurveMetaPoolAdapter(coinIndexBase_) {
        swapper = swapper_;
        booster = booster_;
    }

    function initialize(
        string memory strategyName_,
        address pool_,
        address lpToken_,
        uint16a16 assetMapping_,
        address poolMeta_,
        uint96 pid_,
        bool extraRewards_,
        int128 positiveYieldLimit_,
        int128 negativeYieldLimit_
    ) external initializer {
        __Strategy_init(strategyName_, NULL_ASSET_GROUP_ID);

        if (pool_ == address(0)) {
            revert ConfigurationAddressZero();
        }
        if (lpToken_ == address(0)) {
            revert ConfigurationAddressZero();
        }
        if (poolMeta_ == address(0)) {
            revert ConfigurationAddressZero();
        }

        _pool = pool_;
        _lpToken = lpToken_;
        _assetMapping = assetMapping_;

        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId());
        if (tokens.length != N_COINS) {
            revert InvalidAssetGroup(assetGroupId());
        }
        for (uint256 i; i < tokens.length; ++i) {
            if (tokens[i] != _coins(i)) {
                revert InvalidAssetGroup(assetGroupId());
            }
        }
        tokenLength = tokens.length;

        _poolMeta = poolMeta_;

        pid = pid_;
        extraRewards = extraRewards_;
        IBooster.PoolInfo memory cvxPool = booster.poolInfo(pid_);
        crvRewards = IBaseRewardPool(cvxPool.crvRewards);
        crvRewardToken = crvRewards.rewardToken();
        cvxRewardToken = booster.minter();

        _setPositiveYieldLimit(positiveYieldLimit_);
        _setNegativeYieldLimit(negativeYieldLimit_);
    }

    // adapters

    function pool() public view override(Curve3CoinPoolAdapter, CurveUint256PoolAdapter) returns (address) {
        return _pool;
    }

    function poolMeta() public view override returns (address) {
        return _poolMeta;
    }

    function assetMapping() public view override(Curve3CoinPoolAdapter, CurveUint256PoolAdapter) returns (uint16a16) {
        return _assetMapping;
    }

    // strategy

    function assetRatio() external view override returns (uint256[] memory) {
        uint256[] memory assetRatio_ = new uint256[](tokenLength);

        for (uint256 i; i < tokenLength; ++i) {
            assetRatio_[i] = _balances(i);
        }

        return assetRatio_;
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public view override {
        if (slippages[0] > 2) {
            revert StratBeforeDepositCheckFailed();
        }

        for (uint256 i; i < tokenLength; ++i) {
            if (amounts[i] < slippages[1 + 2 * i] || amounts[i] > slippages[2 + 2 * i]) {
                revert StratBeforeDepositCheckFailed();
            }
        }
    }

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public view override {
        uint256 offset;
        if (slippages[0] < 2) {
            offset = 2 * tokenLength + 1;
        } else if (slippages[0] == 2) {
            offset = 1;
        } else {
            revert StratBeforeRedeemalCheckFailed();
        }

        if (ssts < slippages[offset] || ssts > slippages[offset + 1]) {
            revert StratBeforeRedeemalCheckFailed();
        }
    }

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata slippages)
        internal
        override
    {
        uint256 slippage;
        if (slippages[0] == 0) {
            slippage = 2 * tokenLength + 4;
        } else if (slippages[0] == 2) {
            slippage = 2 * tokenLength + 1;
        } else {
            revert StratDepositSlippagesFailed();
        }

        _depositInner(tokens, amounts, slippage);
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata slippages) internal override {
        uint256 slippageOffset;
        if (slippages[0] == 1) {
            slippageOffset = 2 * tokenLength + 4;
        } else if (slippages[0] == 2) {
            slippageOffset = 3;
        } else if (slippages[0] == 3) {
            slippageOffset = 1;
        } else {
            revert StratRedeemSlippagesFailed();
        }

        _redeemInner(ssts, slippages, slippageOffset);
    }

    function _emergencyWithdrawImpl(uint256[] calldata slippages, address recipient) internal override {
        uint256 slippageOffset;
        if (slippages[0] == 3) {
            slippageOffset = 1;
        } else {
            revert StratRedeemSlippagesFailed();
        }

        _redeemInner(totalSupply(), slippages, slippageOffset);

        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId());

        for (uint256 i; i < tokenLength; ++i) {
            IERC20(tokens[i]).safeTransfer(recipient, IERC20(tokens[i]).balanceOf(address(this)));
        }
    }

    function _compound(address[] calldata tokens, SwapInfo[] calldata compoundSwapInfo, uint256[] calldata slippages)
        internal
        override
        returns (int256 compoundYield)
    {
        if (compoundSwapInfo.length == 0) {
            return compoundYield;
        }

        address[] memory rewardTokens = _getRewards();

        for (uint256 i; i < rewardTokens.length; ++i) {
            uint256 balance = IERC20(rewardTokens[i]).balanceOf(address(this));
            if (balance > 0) {
                IERC20(rewardTokens[i]).safeTransfer(address(swapper), balance);
            }
        }

        uint256[] memory swapped = swapper.swap(rewardTokens, compoundSwapInfo, tokens, address(this));

        uint256 lpTokensBefore = _lpTokenBalance();
        _depositInner(tokens, swapped, slippages[2 * tokenLength + 3]);
        uint256 lpTokensMinted = _lpTokenBalance() - lpTokensBefore;

        compoundYield = int256(YIELD_FULL_PERCENT * lpTokensMinted / lpTokensBefore);
    }

    function _getYieldPercentage(int256 manualYield) internal view override returns (int256) {
        _verifyManualYieldPercentage(manualYield);
        return manualYield;
    }

    function _swapAssets(address[] memory tokens, uint256[] memory toSwap, SwapInfo[] calldata swapInfo)
        internal
        pure
        override
    {}

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256)
    {
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId());
        uint256[] memory tokenWorth = _getTokenWorth(tokens);

        return priceFeedManager.assetToUsdCustomPriceBulk(tokens, tokenWorth, exchangeRates);
    }

    // specific

    function _depositInner(address[] calldata tokens, uint256[] memory amounts, uint256 slippage) private {
        // to curve base
        for (uint256 i; i < tokenLength; ++i) {
            _resetAndApprove(IERC20(tokens[i]), pool(), amounts[i]);
        }
        _addLiquidity(amounts, 0);

        // to curve meta
        uint256 lpTokenAmount = IERC20(_lpToken).balanceOf(address(this));
        _resetAndApprove(IERC20(_lpToken), _poolMeta, lpTokenAmount);
        _addLiquidityMeta(lpTokenAmount, 0, slippage);

        // to convex
        lpTokenAmount = IERC20(_poolMeta).balanceOf(address(this));
        _resetAndApprove(IERC20(_poolMeta), address(booster), lpTokenAmount);
        booster.deposit(pid, lpTokenAmount, true);
    }

    function _redeemInner(uint256 ssts, uint256[] calldata slippages, uint256 slippageOffset) private {
        // from convex
        uint256 lpTokenAmount = crvRewards.balanceOf(address(this)) * ssts / totalSupply();
        crvRewards.withdrawAndUnwrap(lpTokenAmount, false);

        // from curve meta
        lpTokenAmount = IERC20(_poolMeta).balanceOf(address(this));
        _removeLiquidityBase(lpTokenAmount, 0);

        // from curve base
        lpTokenAmount = IERC20(_lpToken).balanceOf(address(this));
        _removeLiquidity(lpTokenAmount, slippages, slippageOffset);
    }

    function _getRewards() private returns (address[] memory) {
        // get CRV and extra rewards
        crvRewards.getReward(address(this), extraRewards);

        address[] memory rewardTokens;
        if (extraRewards) {
            uint256 extraRewardCount = crvRewards.extraRewardsLength();
            rewardTokens = new address[](BASE_REWARD_COUNT + extraRewardCount);

            for (uint256 i; i < extraRewardCount; ++i) {
                rewardTokens[BASE_REWARD_COUNT + i] = crvRewards.extraRewards(i);
            }
        } else {
            rewardTokens = new address[](BASE_REWARD_COUNT);
        }

        rewardTokens[0] = crvRewardToken;
        rewardTokens[1] = cvxRewardToken;

        return rewardTokens;
    }

    function _lpTokenBalance() internal view returns (uint256) {
        return crvRewards.balanceOf(address(this));
    }

    function _getTokenWorth(address[] memory tokens) internal view returns (uint256[] memory) {
        // convex
        uint256 lpTokenAmount = crvRewards.balanceOf(address(this));

        // curve meta
        uint256 oneLpToken = 10 ** IERC20Metadata(_poolMeta).decimals();
        lpTokenAmount = _calcWithdrawBase(oneLpToken) * lpTokenAmount / oneLpToken;

        // curve base
        uint256 lpTokenTotalSupply = IERC20(_lpToken).totalSupply();
        uint256[] memory tokenWorth = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokenWorth[i] = _balances(i) * lpTokenAmount / lpTokenTotalSupply;
        }

        return tokenWorth;
    }
}
