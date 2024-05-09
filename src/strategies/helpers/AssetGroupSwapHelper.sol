// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../external/interfaces/strategies/uniswap/v3/IV3SwapRouter.sol";
import "../../interfaces/ISwapper.sol";
import "../../interfaces/CommonErrors.sol";

// Description:
// This contract is a helper contract for swapping between an asset group token and a different strategy token.
// we do this so that we can have multiple strategies under one asset group, even if the strategy uses a different
// base token that the asset group token.
// For example, in Arbitrum Aave V3, we use USDC as an asset group, but we have both a USDC pool, and a USDC.e pool.
// Both tokens are extremely close in price and swapping them is cheap (in terms of both gas and swap fees). We would
// like to have both strategies under the same asset group to maximise the amount of strategies in vaults under USDC,
// and in the case of the USDC.e pool in this example, accept that there will be some fee for swapping.
// The contract defaults to a Uniswap V3 swap, with a default fee of 0.01% set. The inheriting contract can override the
// fee, or override the default method and implement it's own.
abstract contract AssetGroupSwapHelper {
    using SafeERC20 for IERC20;

    IV3SwapRouter public immutable swapRouter = IV3SwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    uint24 public immutable fee;

    constructor(uint24 fee_) {
        fee = fee_;
    }

    function _assetGroupSwap(address tokenIn, address tokenOut, uint256 amount, uint256 slippage)
        internal
        virtual
        returns (uint256)
    {
        return _defaultSwap(tokenIn, tokenOut, amount, slippage);
    }

    function _defaultSwap(address tokenIn, address tokenOut, uint256 amount, uint256 slippage)
        internal
        virtual
        returns (uint256)
    {
        IERC20(tokenIn).safeApprove(address(swapRouter), amount);
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amount,
            amountOutMinimum: slippage,
            sqrtPriceLimitX96: 0
        });

        return swapRouter.exactInputSingle(params);
    }
}
