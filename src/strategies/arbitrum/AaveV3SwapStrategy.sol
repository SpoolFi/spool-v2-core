// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../../libraries/PackedRange.sol";
import "../helpers/AssetGroupSwapHelper.sol";
import "./base/AaveV3StrategyBase.sol";

error AaveV3BeforeDepositCheckFailed();
error AaveV3BeforeRedeemalCheckFailed();
error AaveV3DepositSlippagesFailed();
error AaveV3RedeemalSlippagesFailed();

// one asset
// no rewards
// slippages (for asset group swap to underlying pool token)
// - mode selection: slippages[0]
// - DHW with deposit: slippages[0] == 0
//   - beforeDepositCheck: slippages[1]
//   - beforeRedeemalCheck: slippages[2]
//   - _depositToProtocol: slippages[3]
// - DHW with withdrawal: slippages[0] == 1
//   - beforeDepositCheck: slippages[1]
//   - beforeRedeemalCheck: slippages[2]
//   - _redeemFromProtocol: slippages[3]
// - reallocate: slippages[0] == 2
//   - beforeDepositCheck: depositSlippages[1]
//   - _depositToProtocol: depositSlippages[2]
//   - beforeRedeemalCheck: withdrawalSlippages[1]
//   - _redeemFromProtocol: withdrawalSlippages[2]
// - redeemFast: slippages[0] == 3
//   - _redeemFromProtocol: slippages[1]
// NOTE: As with other strategies (eg. Convex-StFrxEth), For emergency withdraw, we withdraw pool token balance
// directly, so no slippages needed (we are not swapping back to asset group token).
// Different asset group token and underlying token on the Aave pool.
contract AaveV3SwapStrategy is AaveV3StrategyBase, AssetGroupSwapHelper {
    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        IPoolAddressesProvider provider_,
        IRewardsController incentive_,
        uint24 fee_
    )
        AaveV3StrategyBase(assetGroupRegistry_, accessControl_, swapper_, provider_, incentive_)
        AssetGroupSwapHelper(fee_)
    {}

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public override {
        if (_isViewExecution()) {
            uint256[] memory beforeDepositCheckSlippageAmounts = new uint256[](1);
            beforeDepositCheckSlippageAmounts[0] = amounts[0];

            emit BeforeDepositCheckSlippages(beforeDepositCheckSlippageAmounts);
            return;
        }

        if (slippages[0] > 2) {
            revert AaveV3BeforeDepositCheckFailed();
        }

        if (!PackedRange.isWithinRange(slippages[1], amounts[0])) {
            revert AaveV3BeforeDepositCheckFailed();
        }
    }

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public override {
        if (_isViewExecution()) {
            emit BeforeRedeemalCheckSlippages(ssts);
            return;
        }

        uint256 slippage;
        if (slippages[0] < 2) {
            slippage = slippages[2];
        } else if (slippages[0] == 2) {
            slippage = slippages[1];
        } else {
            revert AaveV3BeforeRedeemalCheckFailed();
        }

        if (!PackedRange.isWithinRange(slippage, ssts)) {
            revert AaveV3BeforeRedeemalCheckFailed();
        }
    }

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata slippages)
        internal
        override
    {
        uint256 slippage;
        if (slippages[0] == 0) {
            slippage = slippages[3];
        } else if (slippages[0] == 2) {
            slippage = slippages[2];
        } else {
            revert AaveV3DepositSlippagesFailed();
        }

        if (amounts[0] == 0) {
            return;
        }

        amounts[0] = _assetGroupSwap(tokens[0], underlying, amounts[0], slippage);

        if (_isViewExecution()) {
            emit Slippages(true, amounts[0], "");
        }

        super._depositToProtocol(tokens, amounts, slippages);
    }

    function _redeemFromProtocol(address[] calldata tokens, uint256 ssts, uint256[] calldata slippages)
        internal
        override
    {
        super._redeemFromProtocol(tokens, ssts, slippages);

        uint256 slippage;
        if (slippages[0] == 1) {
            slippage = slippages[3];
        } else if (slippages[0] == 2) {
            slippage = slippages[2];
        } else if (slippages[0] == 3) {
            slippage = slippages[1];
        } else if (_isViewExecution()) {} else {
            revert AaveV3RedeemalSlippagesFailed();
        }

        uint256 amount = IERC20(underlying).balanceOf(address(this));
        uint256 bought = _assetGroupSwap(underlying, tokens[0], amount, slippage);

        if (_isViewExecution()) {
            emit Slippages(false, bought, "");
        }
    }
}
