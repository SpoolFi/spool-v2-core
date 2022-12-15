// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ISwapper.sol";
import "./libraries/SpoolUtils.sol";

contract Swapper is ISwapper {
    using SafeERC20 for IERC20;

    function swap(address[] calldata tokens, SwapInfo[] calldata swapInfo, address receiver) external {
        // Perform the swaps.
        for (uint256 i = 0; i < swapInfo.length; i++) {
            IERC20(swapInfo[i].token).safeApprove(swapInfo[i].swapTarget, swapInfo[i].amountIn);

            (bool success, bytes memory data) = swapInfo[i].swapTarget.call(swapInfo[i].swapCallData);
            if (!success) revert(SpoolUtils.getRevertMsg(data));

            IERC20(swapInfo[i].token).safeApprove(swapInfo[i].swapTarget, 0);
        }

        // Return unswapped tokens.
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransfer(receiver, IERC20(tokens[i]).balanceOf(address(this)));
        }
    }
}
