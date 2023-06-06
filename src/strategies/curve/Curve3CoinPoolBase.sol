// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../external/interfaces/strategies/curve/ICurvePool.sol";
import "../../libraries/uint16a16Lib.sol";
import "../Strategy.sol";
import "./CurvePoolBase.sol";

error CurveBeforeDepositCheckFailed();
error CurveBeforeRedeemalCheckFailed();
error CurveDepositSlippagesFailed();
error CurveRedeemSlippagesFailed();

// multiple assets
// slippages
// - mode selection: slippages[0]
// - DHW with deposit: slippages[0] == 0
//   - beforeDepositCheck: slippages[1..6]
//   - beforeRedeemalCheck: slippages[7..8]
//   - compound: slippages[9]
//   - _depositToProtocol: slippages[10]
// - DHW with withdrawal: slippages[0] == 1
//   - beforeDepositCheck: slippages[1..6]
//   - beforeRedeemalCheck: slippages[7..8]
//   - compound: slippages[9]
//   - _redeemFromProtocol: slippages[10..12]
// - reallocate: slippages[0] == 2
//   - beforeDepositCheck: depositSlippages[1..6]
//   - _depositToProtocol: depositSlippages[7]
//   - beforeRedeemalCheck: withdrawalSlippages[1..2]
//   - _redeemFromProtocol: withdrawalSlippages[3..5]
// - redeemFast or emergencyWithdraw: slippages[0] == 3
//   - _redeemFromProtocol or _emergencyWithdrawImpl: slippages[1..3]
abstract contract Curve3CoinPoolBase is CurvePoolBase {
    using SafeERC20 for IERC20;
    using uint16a16Lib for uint16a16;

    uint256 constant N_COINS = 3;

    ICurve3CoinPool public pool;

    function __Curve3CoinPoolBase_init(
        string memory strategyName_,
        uint256 assetGroupId_,
        IERC20 lpToken_,
        uint16a16 assetMapping_,
        ICurve3CoinPool pool_,
        int128 positiveYieldLimit_,
        int128 negativeYieldLimit_
    ) internal onlyInitializing {
        pool = pool_;

        __CurvePoolBase_init(
            strategyName_, assetGroupId_, lpToken_, assetMapping_, positiveYieldLimit_, negativeYieldLimit_
        );
    }

    function assetRatio() external view override returns (uint256[] memory) {
        uint256[] memory assetRatio_ = new uint256[](N_COINS);

        for (uint256 i; i < N_COINS; ++i) {
            assetRatio_[i] = _balances(assetMapping.get(i));
        }

        return assetRatio_;
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public override {
        if (_isViewExecution()) {
            emit BeforeDepositCheckSlippages(amounts);
        }

        if (slippages[0] > 2) {
            revert CurveBeforeDepositCheckFailed();
        }

        for (uint256 i; i < N_COINS; ++i) {
            if (amounts[i] < slippages[1 + 2 * i] || amounts[i] > slippages[2 + 2 * i]) {
                revert CurveBeforeDepositCheckFailed();
            }
        }
    }

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public override {
        if (_isViewExecution()) {
            emit BeforeRedeemalCheckSlippages(ssts);
        }

        uint256 offset;
        if (slippages[0] < 2) {
            offset = 7;
        } else if (slippages[0] == 2) {
            offset = 1;
        } else {
            revert CurveBeforeRedeemalCheckFailed();
        }

        if (ssts < slippages[offset] || ssts > slippages[offset + 1]) {
            revert CurveBeforeRedeemalCheckFailed();
        }
    }

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata slippages)
        internal
        override
    {
        uint256 slippage;
        if (slippages[0] == 0) {
            slippage = slippages[10];
        } else if (slippages[0] == 2) {
            slippage = slippages[7];
        } else {
            revert CurveDepositSlippagesFailed();
        }

        _depositToCurve(tokens, amounts, slippage);
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata slippages) internal override {
        uint256 lpTokensToRedeem = _lpTokenBalance() * ssts / totalSupply();
        uint256 slippageOffset;
        if (slippages[0] == 1) {
            slippageOffset = 10;
        } else if (slippages[0] == 2) {
            slippageOffset = 3;
        } else if (slippages[0] == 3) {
            slippageOffset = 1;
        } else if (slippages[0] == 0 && _isViewExecution()) {
            slippageOffset = 10;
        } else {
            revert CurveRedeemSlippagesFailed();
        }

        _redeemFromCurve(lpTokensToRedeem, slippageOffset, slippages);
    }

    function _emergencyWithdrawImpl(uint256[] calldata slippages, address recipient) internal override {
        uint256 lpTokensToRedeem = _lpTokenBalance();
        uint256 slippageOffset;
        if (slippages[0] == 3) {
            slippageOffset = 1;
        } else {
            revert CurveRedeemSlippagesFailed();
        }

        _redeemFromCurve(lpTokensToRedeem, slippageOffset, slippages);

        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId());

        for (uint256 i; i < N_COINS; ++i) {
            IERC20(tokens[i]).safeTransfer(recipient, IERC20(tokens[i]).balanceOf(address(this)));
        }
    }

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256)
    {
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId());

        uint256 usdWorth;
        uint256 lpTokenBalance = _lpTokenBalance();
        uint256 lpTokenTotalSupply = lpToken.totalSupply();
        for (uint256 i; i < tokens.length; ++i) {
            usdWorth += priceFeedManager.assetToUsdCustomPrice(
                tokens[i], _balances(assetMapping.get(i)) * lpTokenBalance / lpTokenTotalSupply, exchangeRates[i]
            );
        }

        return usdWorth;
    }

    function _depositToCurveCompound(address[] memory tokens, uint256[] memory amounts, uint256[] calldata slippages)
        internal
        override
    {
        _depositToCurve(tokens, amounts, slippages[9]);
    }

    function _depositToCurve(address[] memory tokens, uint256[] memory amounts, uint256 slippage) private {
        uint256[N_COINS] memory curveAmounts;

        for (uint256 i; i < N_COINS; ++i) {
            curveAmounts[assetMapping.get(i)] = amounts[i];
            _resetAndApprove(IERC20(tokens[i]), address(pool), amounts[i]);
        }

        pool.add_liquidity(curveAmounts, slippage);

        _handleDeposit();
    }

    function _redeemFromCurve(uint256 lpTokens, uint256 slippageOffset, uint256[] calldata slippages) private {
        _handleWithdrawal(lpTokens);

        uint256[3] memory minOuts;
        for (uint256 i; i < N_COINS; ++i) {
            minOuts[assetMapping.get(i)] = slippages[slippageOffset + i];
        }

        pool.remove_liquidity(lpTokens, minOuts);

        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId());
        uint256[] memory bought = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            bought[i] = IERC20(tokens[i]).balanceOf(address(this));
        }

        if (_isViewExecution()) {
            emit Slippages(false, 0, abi.encode(bought));
        }
    }

    function _ncoins() internal pure override returns (uint256) {
        return N_COINS;
    }
}
