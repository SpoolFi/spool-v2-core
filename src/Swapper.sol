// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "./interfaces/ISwapper.sol";
import "./libraries/SpoolUtils.sol";

contract Swapper is ISwapper {
    function swap(address[] calldata tokens, SwapInfo[] calldata swapInfo, address receiver) external {
        // Perform the swaps.
        for (uint256 i = 0; i < swapInfo.length; i++) {
            IERC20(swapInfo[i].token).approve(swapInfo[i].swapTarget, swapInfo[i].amountIn);

            (bool success, bytes memory data) = swapInfo[i].swapTarget.call(swapInfo[i].swapCallData);
            if (!success) revert(SpoolUtils.getRevertMsg(data));

            IERC20(swapInfo[i].token).approve(swapInfo[i].swapTarget, 0);
        }

        // Return unswapped tokens.
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).transfer(receiver, IERC20(tokens[i]).balanceOf(address(this)));
        }
    }
}
