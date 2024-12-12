// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../external/interfaces/strategies/aave/IStakedGho.sol";
import "../../interfaces/ISwapper.sol";

/**
 * @dev This library should only be used by the AaveGhoStakingStrategy contract.
 */

library AaveGhoStakingStrategyLib {
    using SafeERC20 for IERC20Metadata;

    /**
     * @notice Emitted when the swap estimation is performed.
     * @param tokenIn Token to swap.
     * @param tokenOut Token to receive.
     * @param tokenInAmount Amount of token to swap.
     */
    event SwapEstimation(address tokenIn, address tokenOut, uint256 tokenInAmount);

    /**
     * @notice Continues the withdrawal from the underlying protocol.
     * @param tokens Asset tokens.
     * @param continuationData Data for the continuation.
     * @param gho GHO token.
     * @param stakedGho Staked GHO contract.
     * @param swapper Swapper contract.
     * @param toUnstake Amount of GHO to unstake.
     */
    function continueWithdrawalFromProtocol(
        address[] calldata tokens,
        bytes calldata continuationData,
        IERC20Metadata gho,
        IStakedGho stakedGho,
        ISwapper swapper,
        uint256 toUnstake
    ) external returns (bool) {
        stakedGho.redeem(address(this), toUnstake);

        uint256 tokenInAmount = gho.balanceOf(address(this));

        _swapWithdrawals(tokens[0], tokenInAmount, continuationData, gho, swapper);

        return true;
    }

    /**
     * @dev Swaps the GHO token to the underlying asset.
     * @param tokenOut Underlying asset.
     * @param tokenInAmount Amount of GHO to swap.
     * @param continuationData Data for the continuation, includes swap data.
     * @param gho GHO token.
     * @param swapper Swapper contract.
     */
    function _swapWithdrawals(
        address tokenOut,
        uint256 tokenInAmount,
        bytes calldata continuationData,
        IERC20Metadata gho,
        ISwapper swapper
    ) private returns (uint256) {
        (address swapTarget, bytes memory swapCallData) = abi.decode(continuationData, (address, bytes));

        if (_isViewExecution() && swapTarget == address(0)) {
            emit SwapEstimation(address(gho), tokenOut, tokenInAmount);
            return 0;
        }

        address[] memory tokensIn = new address[](1);
        tokensIn[0] = address(gho);
        SwapInfo[] memory swapInfos = new SwapInfo[](1);
        swapInfos[0] = SwapInfo(swapTarget, address(gho), swapCallData);
        address[] memory tokensOut = new address[](1);
        tokensOut[0] = tokenOut;

        gho.safeTransfer(address(swapper), tokenInAmount);
        return swapper.swap(tokensIn, swapInfos, tokensOut, address(this))[0];
    }

    function _isViewExecution() internal view returns (bool) {
        return tx.origin == address(0);
    }
}
