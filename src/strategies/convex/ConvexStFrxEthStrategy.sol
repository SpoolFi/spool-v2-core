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

error StratBeforeDepositCheckFailed();
error StratBeforeRedeemalCheckFailed();
error StratDepositSlippagesFailed();
error StratRedeemSlippagesFailed();
error StratCompoundSlippagesFailed();

// One asset
// multiple rewards
// slippages
// - mode selection: slippages[0]
//
// - DHW with deposit: slippages[0] == 0
//   - beforeDepositCheck: slippages[1..5]
//   - beforeRedeemalCheck: slippages[9]
//   - compound: slippages[10]
//   - _depositToProtocol: slippages[4..8]
//   -- breakdown --
//      - 1: amount check (eth)
//      - 2, 3: balance checks (pool)
//      - 4, 5: steth/frxeth: amount split (check slippages[4..5] == amounts[0])
//      - 6, 7: steth/frxeth: slippages
//      - 8: addLiquidity: slippage
//      - 9: SSTs check (beforeRedeemalCheck)
//      - 10: compound
//
// - DHW with withdrawal: slippages[0] == 1
//   - beforeDepositCheck: slippages[1..3]
//   - beforeRedeemalCheck: slippages[8]
//   - compound: slippages[9]
//   - _redeemFromProtocol: slippages[4..7]
//   -- breakdown --
//      - 1: amount check (eth)
//      - 2, 3: balance checks (pool)
//      - 4, 5: removeLiquidity: slippages
//      - 6, 7: steth/frxeth: slippages
//      - 8: ssts check (beforeRedeemalCheck)
//      - 9: compound
//
// - reallocate: slippages[0] == 2
//   - beforeDepositCheck: depositSlippages[1..5]
//   - _depositToProtocol: depositSlippages[6..8]
//   - beforeRedeemalCheck: withdrawalSlippages[1]
//   - _redeemFromProtocol: withdrawalSlippages[2..5]
//   -- breakdown --
//      ----------------
//      depositSlippages
//      ----------------
//      1: amount check (eth)
//      2, 3: balance checks (pool)
//      4, 5: steth/frxeth: amount split (check depositSlippages[4..5] == amounts[0])
//      6, 7: steth/frxeth: slippages
//      8: addLiquidity: slippage
//      ----------------
//      withdrawalSlippages
//      ----------------
//      1: ssts check
//      2, 3: removeLiquidity: slippages
//      4, 5: steth/frxeth: slippages
//
// - redeemFast or emergencyWithdraw: slippages[0] == 3
//   - _redeemFromProtocol or _emergencyWithdrawImpl: slippages[1..2]
//   -- breakdown --
//     - 1,2: removeLiquidity: slippages
//     - 3,4: steth/frxeth: slippages
contract ConvexStFrxEthStrategy is StrategyManualYieldVerifier, Strategy, Curve2CoinPoolAdapter {
    using SafeERC20 for IERC20;
    using uint16a16Lib for uint16a16;

    ISwapper public immutable swapper;
    uint256 constant BASE_REWARD_COUNT = 2;
    IBooster public immutable booster;
    uint96 public pid;
    bool extraRewards;

    address private _pool;
    IBaseRewardPool private crvRewards;
    address private crvRewardToken;
    address private cvxRewardToken;
    // curve _tokens
    address[] private _tokens;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        uint256 assetGroupId_,
        ISwapper swapper_,
        IBooster booster_
    ) Strategy(assetGroupRegistry_, accessControl_, assetGroupId_) {
        swapper = swapper_;
        booster = booster_;
    }

    function initialize(
        string memory strategyName_,
        address pool_,
        address weth_,
        uint96 pid_,
        bool extraRewards_,
        int128 positiveYieldLimit_,
        int128 negativeYieldLimit_
    ) external initializer {
        __Strategy_init(strategyName_, NULL_ASSET_GROUP_ID);

        _noAddressZero(pool_);

        _pool = pool_;

        address[] memory assetGroupTokens = _assetGroupRegistry.listAssetGroup(assetGroupId());

        if (assetGroupTokens.length != 1 || assetGroupTokens[0] != weth_) {
            revert InvalidAssetGroup(assetGroupId());
        }

        pid = pid_;
        extraRewards = extraRewards_;
        crvRewards = IBaseRewardPool(booster.poolInfo(pid_).crvRewards);
        crvRewardToken = crvRewards.rewardToken();
        cvxRewardToken = booster.minter();

        _setPositiveYieldLimit(positiveYieldLimit_);
        _setNegativeYieldLimit(negativeYieldLimit_);

        _tokens = new address[](2);
        _tokens[0] = _coins(0);
        _tokens[1] = _coins(1);
    }

    // adapters

    function pool() public view override(Curve2CoinPoolAdapter) returns (address) {
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
                revert StratBeforeDepositCheckFailed();
            }

            if (
                (!PackedRange.isWithinRange(slippages[1], amounts[0]))
                    || (!PackedRange.isWithinRange(slippages[2], ICurvePoolUint256(address(_pool)).balances(0)))
                    || (!PackedRange.isWithinRange(slippages[3], ICurvePoolUint256(address(_pool)).balances(1)))
            ) {
                revert StratBeforeDepositCheckFailed();
            }

            if (slippages[0] != 1) {
                // == 0 (DHW with deposit) or == 2 (reallocate)
                if ((slippages[4] + slippages[5]) != amounts[0]) {
                    revert StratBeforeDepositCheckFailed();
                }
            }
        }
    }

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public override {
        if (_isViewExecution()) {
            emit BeforeRedeemalCheckSlippages(ssts);
            return;
        }

        uint256 slippage;
        if (slippages[0] == 0) {
            slippage = slippages[9];
        } else if (slippages[0] == 1) {
            slippage = slippages[8];
        } else if (slippages[0] == 2) {
            slippage = slippages[1];
        } else {
            revert StratBeforeRedeemalCheckFailed();
        }

        if (!PackedRange.isWithinRange(slippage, ssts)) {
            revert StratBeforeRedeemalCheckFailed();
        }
    }

    function _depositToProtocol(address[] calldata, uint256[] memory, uint256[] calldata slippages) internal override {
        uint256 slippageOffset;
        if (slippages[0] == 0 || slippages[0] == 2) {
            slippageOffset = 4;
        } else {
            revert StratDepositSlippagesFailed();
        }

        uint256[] memory wrappedAmounts = _assetGroupWrap(slippages, slippageOffset);

        _depositInner(wrappedAmounts, slippages[slippageOffset + 4]);
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata slippages) internal override {
        uint256 slippageOffset;
        if (slippages[0] == 1) {
            slippageOffset = 4;
        } else if (slippages[0] == 2) {
            slippageOffset = 2;
        } else if (slippages[0] == 3) {
            slippageOffset = 1;
        } else if (slippages[0] == 0 && _isViewExecution()) {
            slippageOffset = 4;
        } else {
            revert StratRedeemSlippagesFailed();
        }

        uint256[] memory amounts = _redeemInner(ssts, slippages, slippageOffset);

        _assetGroupUnwrap(amounts, slippages, slippageOffset + 2);
    }

    function _emergencyWithdrawImpl(uint256[] calldata slippages, address recipient) internal override {
        if (slippages[0] != 3) {
            revert StratRedeemSlippagesFailed();
        }

        _redeemInner(totalSupply(), slippages, 1);

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
        if (slippages[0] == 0) {
            slippageOffset = 10;
        } else if (slippages[0] == 1) {
            slippageOffset = 9;
        } else {
            revert StratCompoundSlippagesFailed();
        }

        if (compoundSwapInfo.length == 0) {
            return compoundYield;
        }

        (address[] memory rewardTokens,) = _getProtocolRewardsInternal();

        uint256[] memory swapped = swapper.swap(rewardTokens, compoundSwapInfo, _tokens, address(this));

        uint256 lpTokensBefore = _lpTokenBalance();
        _depositInner(swapped, slippages[slippageOffset]);

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
        return priceFeedManager.assetToUsdCustomPriceBulk(
            _assetGroupRegistry.listAssetGroup(assetGroupId()), _getTokenWorth(), exchangeRates
        );
    }

    // specific

    function _depositInner(uint256[] memory amounts, uint256 slippage) private {
        // to curve base
        unchecked {
            for (uint256 i; i < 2; ++i) {
                _resetAndApprove(IERC20(_tokens[i]), pool(), amounts[i]);
            }
        }

        _addLiquidity(amounts, slippage);

        // to convex
        uint256 lpTokenAmount = IERC20(_pool).balanceOf(address(this));
        _resetAndApprove(IERC20(_pool), address(booster), lpTokenAmount);
        booster.deposit(pid, lpTokenAmount, true);

        if (_isViewExecution()) {
            emit Slippages(true, lpTokenAmount, "");
        }
    }

    function _redeemInner(uint256 ssts, uint256[] calldata slippages, uint256 slippageOffset)
        private
        returns (uint256[] memory bought)
    {
        // from convex
        uint256 lpTokenAmount = crvRewards.balanceOf(address(this)) * ssts / totalSupply();
        crvRewards.withdrawAndUnwrap(lpTokenAmount, false);

        // from curve base
        lpTokenAmount = IERC20(_pool).balanceOf(address(this));
        _removeLiquidity(lpTokenAmount, slippages, slippageOffset);

        bought = new uint256[](_tokens.length);
        unchecked {
            for (uint256 i; i < _tokens.length; ++i) {
                bought[i] = IERC20(_tokens[i]).balanceOf(address(this));
            }
        }

        if (_isViewExecution()) {
            emit Slippages(false, 0, abi.encode(bought));
        }
    }

    function _getRewards() private returns (address[] memory) {
        // get CRV and extra rewards
        crvRewards.getReward(address(this), extraRewards);

        address[] memory rewardTokens;
        if (extraRewards) {
            uint256 extraRewardCount = crvRewards.extraRewardsLength();

            unchecked {
                rewardTokens = new address[](BASE_REWARD_COUNT + extraRewardCount);
                for (uint256 i; i < extraRewardCount; ++i) {
                    rewardTokens[BASE_REWARD_COUNT + i] = crvRewards.extraRewards(i);
                }
            }
        } else {
            rewardTokens = new address[](BASE_REWARD_COUNT);
        }

        rewardTokens[0] = crvRewardToken;
        rewardTokens[1] = cvxRewardToken;

        return rewardTokens;
    }

    function _assetGroupWrap(uint256[] calldata slippages, uint256 slippageOffset)
        private
        returns (uint256[] memory amounts)
    {
        amounts = new uint[](2);
        amounts[0] = EthStEthAssetGroupAdapter.wrap(slippages[slippageOffset], slippages[slippageOffset + 2]);
        amounts[1] = EthFrxEthAssetGroupAdapter.wrap(slippages[slippageOffset + 1], slippages[slippageOffset + 3]);

        if (_isViewExecution()) {
            emit Slippages(true, 0, abi.encode(amounts));
        }
    }

    function _assetGroupUnwrap(uint256[] memory amounts, uint256[] calldata slippages, uint256 slippageOffset)
        private
    {
        amounts[0] = EthStEthAssetGroupAdapter.unwrap(amounts[0], slippages[slippageOffset]);
        amounts[1] = EthFrxEthAssetGroupAdapter.unwrap(amounts[1], slippages[slippageOffset + 1]);

        if (_isViewExecution()) {
            emit Slippages(false, 0, abi.encode(amounts));
        }
    }

    function _lpTokenBalance() internal view returns (uint256) {
        return crvRewards.balanceOf(address(this));
    }

    function _getTokenWorth() internal view returns (uint256[] memory amount) {
        amount = new uint256[](1);

        // convex
        uint256 lpTokenAmount = crvRewards.balanceOf(address(this));

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
                    IERC20(rewardTokens[i]).safeTransfer(address(swapper), balance);

                    balances[i] = balance;
                }
            }
        }

        return (rewardTokens, balances);
    }

    function _noAddressZero(address addr) private pure {
        if (addr == address(0)) {
            revert ConfigurationAddressZero();
        }
    }

    receive() external payable {}
}
