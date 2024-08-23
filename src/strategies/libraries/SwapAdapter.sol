// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../libraries/BytesUint256Lib.sol";
import "../../interfaces/ISwapper.sol";

/// Generic strategy swap adapter, to assist when asset group token
/// differs from the underlying token of the strategy.
/// Builds arguments and executes swap on the Swapper contract from slippages
/// array passed to the strategy.
/// @dev swaps "tokenInAmount" of "tokenIn" to "tokenOut" using "slippages"
/// to build swap payload for Swapper.
library SwapAdapter {
    using SafeERC20 for IERC20;

    /// @dev used for parameter gatherer to prepare swap payload
    event SwapEstimation(address tokenIn, address tokenOut, uint256 tokenInAmount);

    /// @dev thrown if slippages array is not valid for swap
    error SwapSlippage();

    uint256 constant MIN_ARGS_LENGTH = 3;
    uint256 constant LENGTH_OFFSET = 1;
    uint256 constant DATA_OFFSET = 2;

    /// @dev swaps "tokenInAmount" of "tokenIn" to "tokenOut" using "slippages" to build swap payload for Swapper
    function swap(
        ISwapper swapper,
        address tokenIn,
        address tokenOut,
        uint256 tokenInAmount,
        uint256[] calldata slippages,
        uint256 offset
    ) external returns (uint256) {
        // used for parameter gatherer in order to prepare swap calldata
        if (_isViewExecution() && slippages[0] == 1) {
            emit SwapEstimation(tokenIn, tokenOut, tokenInAmount);
            return 0;
        }
        address[] memory tokensIn = new address[](1);
        tokensIn[0] = tokenIn;

        SwapInfo[] memory swapInfos = new SwapInfo[](1);
        address swapTarget = address(uint160(slippages[offset]));
        bytes memory payload = _getPayload(slippages, offset);
        swapInfos[0] = SwapInfo(swapTarget, tokensIn[0], payload);

        address[] memory tokensOut = new address[](1);
        tokensOut[0] = tokenOut;

        IERC20(tokenIn).safeTransfer(address(swapper), tokenInAmount);
        return swapper.swap(tokensIn, swapInfos, tokensOut, address(this))[0];
    }

    function _getPayload(uint256[] calldata slippages, uint256 offset) private pure returns (bytes memory payload) {
        uint256 bytesLength = slippages[offset + LENGTH_OFFSET];
        uint256 wordsLength = (bytesLength % 32 > 0) ? (bytesLength / 32) + 1 : (bytesLength / 32);
        if (slippages.length < offset + DATA_OFFSET + wordsLength) revert SwapSlippage();
        uint256[] memory toDecode = new uint256[](wordsLength);
        for (uint256 i; i < wordsLength; ++i) {
            toDecode[i] = slippages[offset + DATA_OFFSET + i];
        }
        payload = BytesUint256Lib.decode(toDecode, bytesLength);
    }

    function _isViewExecution() private view returns (bool) {
        return tx.origin == address(0);
    }
}
