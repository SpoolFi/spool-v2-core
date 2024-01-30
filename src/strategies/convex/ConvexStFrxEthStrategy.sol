// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../external/interfaces/strategies/convex/IBaseRewardPool.sol";
import "../../external/interfaces/strategies/convex/IBooster.sol";
import "../../libraries/PackedRange.sol";
import "../curve/CurveAdapter.sol";
import "../libraries/EthStEthAssetGroupAdapter.sol";
import "../libraries/EthFrxEthAssetGroupAdapter.sol";
import "../Strategy.sol";
import "../helpers/StrategyManualYieldVerifier.sol";
import "../helpers/WethHelper.sol";

error ConvexStFrxEthDepositCheckFailed();
error ConvexStFrxEthRedeemalCheckFailed();
error ConvexStFrxEthDepositSlippagesFailed();
error ConvexStFrxEthRedeemSlippagesFailed();
error ConvexStFrxEthCompoundSlippagesFailed();

// One asset: WETH
//
// multiple rewards: CRV, CVX
//
// slippages:
// - mode selection: slippages[0]
//
// - DHW with deposit: slippages[0] == 0
//   - beforeDepositCheck: slippages[1..3]
//   - beforeRedeemalCheck: slippages[4]
//   - compound: slippages[5]
//   - _depositToProtocol: slippages[6..8]
//   -- breakdown --
//      - 1: amount check (eth)
//      - 2, 3: balance checks (pool)
//      - 4: SSTs check (beforeRedeemalCheck)
//      - 5: compound
//      - 6: steth: mode choice
//      - 7: frxeth: mode choice
//      - 8: addLiquidity: slippage
//      -- mode choice --
//          - if value == uint256 max -> stake
//            else -> buy on curve
//
// - DHW with withdrawal: slippages[0] == 1
//   - beforeDepositCheck: slippages[1..3]
//   - beforeRedeemalCheck: slippages[4]
//   - compound: slippages[5]
//   - _redeemFromProtocol: slippages[6]
//   -- breakdown --
//      - 1: amount check (eth)
//      - 2, 3: balance checks (pool)
//      - 4: ssts check (beforeRedeemalCheck)
//      - 5: compound
//      - 6: weth output: slippage
//
// - reallocate: slippages[0] == 2
//   - beforeDepositCheck: depositSlippages[1..3]
//   - _depositToProtocol: depositSlippages[4..6]
//   - beforeRedeemalCheck: withdrawalSlippages[1]
//   - _redeemFromProtocol: withdrawalSlippages[2]
//   -- breakdown --
//      ----------------
//      depositSlippages
//      ----------------
//      1: amount check (eth)
//      2, 3: balance checks (pool)
//      4, 5: steth/frxeth: slippages
//      6: addLiquidity: slippage
//      ----------------
//      withdrawalSlippages
//      ----------------
//      1: ssts check
//      2: weth output: slippage
//
// - redeemFast or emergencyWithdraw: slippages[0] == 3
//   - _redeemFromProtocol: slippages[1]
//   - _emergencyWithdrawImpl: slippages[1..2]
//   -- breakdown --
//      - 1: weth output: slippage (_redeemFromProtocol)
//        or
//      - 1,2: steth/frxeth: slippages (_emergencyWithdrawImpl)
//
// Description:
// This is a Convex strategy. ETH is swapped for stETH (Lido) and frxETH,
// and used to add proportional liquidity to the Curve st-frxETH Factory
// Plain Pool, with the outgoing LP token being staked on Convex for boosted
// rewards.
//
// The strategy supports two ways to obtain each of the stETH and frxETH tokens:
// either by acquiring it directly on their respective protocols, or by buying
// the token via their respective Curve ETH pools (See the adapter libraries
// for each token).
//
// The do-hard-worker can decide which way to use based on profitability by
// setting appropriate slippages (see slippages above).
//
// Since staked ETH on Lido and Frax is used to spin-up validators, it cannot
// be unstaked immediately. To exit the protocol, the strategy sells the
// tokens on their respective Curve ETH pools.
contract ConvexStFrxEthStrategy is StrategyManualYieldVerifier, Strategy, Curve2CoinPoolAdapter, WethHelper {
    using SafeERC20 for IERC20;
    using uint16a16Lib for uint16a16;

    ISwapper private immutable _swapper;

    uint96 private constant _pid = 161;
    bool private constant _extraRewards = false;
    IBooster private constant _booster = IBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address private constant _pool = 0x4d9f9D15101EEC665F77210cB999639f760F831E;
    IBaseRewardPool private constant _crvRewards = IBaseRewardPool(0xC3D0B8170E105d6476fE407934492930CAc3BDAC);
    address private constant _crvRewardToken = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address private constant _cvxRewardToken = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address private constant _weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // curve _tokens
    address[] private _tokens;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        uint256 assetGroupId_,
        ISwapper swapper_
    ) Strategy(assetGroupRegistry_, accessControl_, assetGroupId_) WethHelper(_weth) {
        _swapper = swapper_;
    }

    function initialize(string memory strategyName_, int128 positiveYieldLimit_, int128 negativeYieldLimit_)
        external
        initializer
    {
        __Strategy_init(strategyName_, NULL_ASSET_GROUP_ID);

        address[] memory assetGroupTokens = _assetGroupRegistry.listAssetGroup(assetGroupId());

        if (assetGroupTokens.length != 1 || assetGroupTokens[0] != weth) {
            revert InvalidAssetGroup(assetGroupId());
        }

        _setPositiveYieldLimit(positiveYieldLimit_);
        _setNegativeYieldLimit(negativeYieldLimit_);

        _tokens = new address[](2);
        _tokens[0] = _coins(0);
        _tokens[1] = _coins(1);
    }

    // adapters

    function pool() public pure override(Curve2CoinPoolAdapter) returns (address) {
        return _pool;
    }

    // strategy

    function assetRatio() external pure override returns (uint256[] memory) {
        uint256[] memory _assetRatio = new uint256[](1);
        _assetRatio[0] = 1;
        return _assetRatio;
    }

    function getUnderlyingAssetAmounts() external view returns (uint256[] memory) {
        return _getTokenWorth();
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public override {
        unchecked {
            if (_isViewExecution()) {
                uint256[] memory beforeDepositCheckSlippageAmounts = new uint256[](3);
                beforeDepositCheckSlippageAmounts[0] = amounts[0];
                beforeDepositCheckSlippageAmounts[1] = ICurvePoolUint256(address(_pool)).balances(0);
                beforeDepositCheckSlippageAmounts[2] = ICurvePoolUint256(address(_pool)).balances(1);

                emit BeforeDepositCheckSlippages(beforeDepositCheckSlippageAmounts);
                return;
            }

            if (slippages[0] > 2) {
                revert ConvexStFrxEthDepositCheckFailed();
            }

            if (
                (!PackedRange.isWithinRange(slippages[1], amounts[0]))
                    || (!PackedRange.isWithinRange(slippages[2], ICurvePoolUint256(address(_pool)).balances(0)))
                    || (!PackedRange.isWithinRange(slippages[3], ICurvePoolUint256(address(_pool)).balances(1)))
            ) {
                revert ConvexStFrxEthDepositCheckFailed();
            }
        }
    }

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public override {
        if (_isViewExecution()) {
            emit BeforeRedeemalCheckSlippages(ssts);
            return;
        }

        uint256 slippage;
        if (slippages[0] < 2) {
            slippage = slippages[4];
        } else if (slippages[0] == 2) {
            slippage = slippages[1];
        } else {
            revert ConvexStFrxEthRedeemalCheckFailed();
        }

        if (!PackedRange.isWithinRange(slippage, ssts)) {
            revert ConvexStFrxEthRedeemalCheckFailed();
        }
    }

    function _depositToProtocol(address[] calldata, uint256[] memory amounts, uint256[] calldata slippages)
        internal
        override
    {
        uint256 slippageOffset;
        if (slippages[0] == 0) {
            slippageOffset = 6;
        } else if (slippages[0] == 2) {
            slippageOffset = 4;
        } else {
            revert ConvexStFrxEthDepositSlippagesFailed();
        }

        (uint256[] memory wrappedAmounts, uint256[] memory ratio) =
            _assetGroupWrap(amounts[0], slippages, slippageOffset);

        uint256 lpAmount = _depositInner(wrappedAmounts, slippages[slippageOffset + 2]);

        if (_isViewExecution()) {
            uint256[] memory bought = new uint256[](5);
            for (uint256 i; i < wrappedAmounts.length; ++i) {
                bought[i] = ratio[i];
                bought[i + 2] = wrappedAmounts[i];
            }
            bought[4] = lpAmount;
            emit Slippages(true, 0, abi.encode(bought));
        }
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata slippages) internal override {
        uint256 slippage;
        if (slippages[0] == 1) {
            slippage = slippages[6];
        } else if (slippages[0] == 2) {
            slippage = slippages[2];
        } else if (slippages[0] == 3) {
            slippage = slippages[1];
        } else if (slippages[0] == 0 && _isViewExecution()) {
            slippage = slippages[6];
        } else {
            revert ConvexStFrxEthRedeemSlippagesFailed();
        }

        uint256[] memory amounts = _redeemInner(ssts, new uint256[](2));

        uint256 bought = _assetGroupUnwrap(amounts);

        if (bought < slippage) {
            revert ConvexStFrxEthRedeemSlippagesFailed();
        }

        if (_isViewExecution()) {
            emit Slippages(false, bought, "");
        }
    }

    function _emergencyWithdrawImpl(uint256[] calldata slippages, address recipient) internal override {
        if (slippages[0] != 3) {
            revert ConvexStFrxEthRedeemSlippagesFailed();
        }

        uint256[] memory bought = _redeemInner(totalSupply(), slippages[1:]);

        if (_isViewExecution()) {
            emit Slippages(false, 0, abi.encode(bought));
        }

        unchecked {
            for (uint256 i; i < 2; ++i) {
                IERC20(_tokens[i]).safeTransfer(recipient, IERC20(_tokens[i]).balanceOf(address(this)));
            }
        }
    }

    function _compound(address[] calldata, SwapInfo[] calldata compoundSwapInfo, uint256[] calldata slippages)
        internal
        override
        returns (int256 compoundYield)
    {
        uint256 slippageOffset;
        if (slippages[0] < 2) {
            slippageOffset = 5;
        } else {
            revert ConvexStFrxEthCompoundSlippagesFailed();
        }

        if (compoundSwapInfo.length == 0) {
            return compoundYield;
        }

        (address[] memory rewardTokens,) = _getProtocolRewardsInternal();

        uint256[] memory swapped = _swapper.swap(rewardTokens, compoundSwapInfo, _tokens, address(this));

        uint256 lpTokensBefore = _lpTokenBalance();
        uint256 lpAmount = _depositInner(swapped, slippages[slippageOffset]);
        if (_isViewExecution()) {
            emit Slippages(true, lpAmount, "");
        }

        compoundYield = int256(YIELD_FULL_PERCENT * (_lpTokenBalance() - lpTokensBefore) / lpTokensBefore);
    }

    function _getYieldPercentage(int256 manualYield) internal view override returns (int256) {
        _verifyManualYieldPercentage(manualYield);
        return manualYield;
    }

    function _swapAssets(address[] memory, uint256[] memory, SwapInfo[] calldata) internal pure override {}

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256)
    {
        return priceFeedManager.assetToUsdCustomPrice(weth, _getTokenWorth()[0], exchangeRates[0]);
    }

    // specific

    function _depositInner(uint256[] memory amounts, uint256 slippage) private returns (uint256 lpTokenAmount) {
        // to curve base
        unchecked {
            for (uint256 i; i < 2; ++i) {
                _resetAndApprove(IERC20(_tokens[i]), pool(), amounts[i]);
            }
        }

        _addLiquidity(amounts, slippage);

        // to convex
        lpTokenAmount = IERC20(_pool).balanceOf(address(this));
        _resetAndApprove(IERC20(_pool), address(_booster), lpTokenAmount);
        _booster.deposit(_pid, lpTokenAmount, true);
    }

    function _redeemInner(uint256 ssts, uint256[] memory slippages) private returns (uint256[] memory bought) {
        // from convex
        uint256 lpTokenAmount = _crvRewards.balanceOf(address(this)) * ssts / totalSupply();
        _crvRewards.withdrawAndUnwrap(lpTokenAmount, false);

        // from curve base
        lpTokenAmount = IERC20(_pool).balanceOf(address(this));
        _removeLiquidity(lpTokenAmount, slippages);

        bought = new uint256[](_tokens.length);
        unchecked {
            for (uint256 i; i < _tokens.length; ++i) {
                bought[i] = IERC20(_tokens[i]).balanceOf(address(this));
            }
        }
    }

    function _getRewards() private returns (address[] memory) {
        // get CRV and extra rewards
        _crvRewards.getReward(address(this), _extraRewards);

        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = _crvRewardToken;
        rewardTokens[1] = _cvxRewardToken;

        return rewardTokens;
    }

    function _assetGroupWrap(uint256 amount, uint256[] calldata slippages, uint256 slippageOffset)
        private
        returns (uint256[] memory amounts, uint256[] memory ratio)
    {
        amounts = new uint256[](2);
        ratio = new uint256[](2);

        unwrapEth(amount);
        uint256 balance0 = _balances(0);
        ratio[0] = amount * balance0 / (balance0 + _balances(1));
        ratio[1] = amount - ratio[0];
        amounts[0] = EthStEthAssetGroupAdapter.wrap(ratio[0], slippages[slippageOffset]);
        amounts[1] = EthFrxEthAssetGroupAdapter.wrap(ratio[1], slippages[slippageOffset + 1]);
    }

    function _assetGroupUnwrap(uint256[] memory amounts) private returns (uint256 bought) {
        bought = EthStEthAssetGroupAdapter.unwrap(amounts[0], 0);
        bought += EthFrxEthAssetGroupAdapter.unwrap(amounts[1], 0);
        wrapEth(bought);
    }

    function _lpTokenBalance() internal view returns (uint256) {
        return _crvRewards.balanceOf(address(this));
    }

    function _getTokenWorth() internal view returns (uint256[] memory amount) {
        amount = new uint256[](1);

        // convex
        uint256 lpTokenAmount = _lpTokenBalance();

        // curve base
        uint256 lpTokenTotalSupply = IERC20(_pool).totalSupply();

        amount[0] = _balances(0) * lpTokenAmount / lpTokenTotalSupply;
        amount[0] += _balances(1) * lpTokenAmount / lpTokenTotalSupply;

        return amount;
    }

    function _getProtocolRewardsInternal() internal virtual override returns (address[] memory, uint256[] memory) {
        address[] memory rewardTokens = _getRewards();
        uint256[] memory balances = new uint256[](rewardTokens.length);

        unchecked {
            for (uint256 i; i < rewardTokens.length; ++i) {
                uint256 balance = IERC20(rewardTokens[i]).balanceOf(address(this));
                if (balance > 0) {
                    IERC20(rewardTokens[i]).safeTransfer(address(_swapper), balance);

                    balances[i] = balance;
                }
            }
        }

        return (rewardTokens, balances);
    }
}
