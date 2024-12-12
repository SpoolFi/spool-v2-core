// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/IAssetGroupRegistry.sol";
import "../../libraries/PackedRange.sol";
import "../../external/interfaces/strategies/curve/ICurvePool.sol";

error StratBeforeDepositCheckFailed();
error StratBeforeRedeemalCheckFailed();

library ConvexAlUsdStrategyLib {
    using SafeERC20 for IERC20;

    function emergencyWithdraw(
        IAssetGroupRegistry assetGroupRegistry,
        uint256 assetGroupId,
        address recipient
    ) external {
        address[] memory tokens = assetGroupRegistry.listAssetGroup(assetGroupId);

        unchecked {
            for (uint256 i; i < tokens.length; ++i) {
                IERC20(tokens[i]).safeTransfer(recipient, IERC20(tokens[i]).balanceOf(address(this)));
            }
        }
    }

    function beforeDepositCheck(
        uint256[] calldata amounts,
        uint256[] calldata slippages,
        uint256 tokenLength,
        address pool,
        address poolMeta,
        uint256 nCoins,
        uint256 nCoinsMeta
    ) external {
        if (slippages[0] > 2) {
                revert StratBeforeDepositCheckFailed();
            }

            for (uint256 i; i < tokenLength; ++i) {
                if (!PackedRange.isWithinRange(slippages[i + 1], amounts[i])) {
                    revert StratBeforeDepositCheckFailed();
                }
            }

            for (uint256 i; i < nCoins; ++i) {
                if (!PackedRange.isWithinRange(slippages[i + 4], ICurvePoolUint256(address(pool)).balances(i))) {
                    revert StratBeforeDepositCheckFailed();
                }
            }

            for (uint256 i; i < nCoinsMeta; ++i) {
                if (!PackedRange.isWithinRange(slippages[i + 7], ICurvePoolUint256(address(poolMeta)).balances(i))) {
                    revert StratBeforeDepositCheckFailed();
                }
            }
    }

    function beforeRedeemalCheck(
        uint256 ssts,
        uint256[] calldata slippages
    ) external {
        uint256 slippage;
        if (slippages[0] < 2) {
            slippage = slippages[9];
        } else if (slippages[0] == 2) {
            slippage = slippages[1];
        } else {
            revert StratBeforeRedeemalCheckFailed();
        }

        if (!PackedRange.isWithinRange(slippage, ssts)) {
            revert StratBeforeRedeemalCheckFailed();
        }
    }
}
