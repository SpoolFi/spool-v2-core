// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../external/interfaces/strategies/uniswap/v3/IV3SwapRouter.sol";
import "../../interfaces/ISwapper.sol";
import "../../interfaces/CommonErrors.sol";

error InvalidSwapInfo();

abstract contract AssetGroupSwapHelper {
    using SafeERC20 for IERC20;

    ISwapper public immutable swapper;
    IV3SwapRouter public immutable swapRouter = IV3SwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    uint256 constant MIN_SWAP_INFO_SIZE = 4;

    constructor(ISwapper swapper_) {
        if (address(swapper_) == address(0)) {
            revert ConfigurationAddressZero();
        }

        swapper = swapper_;
    }

    function _defaultSwap(address tokenIn, address tokenOut, uint256 amount) private returns (uint256) {
        IERC20(tokenIn).safeApprove(address(swapRouter), amount);
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: 100,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        return swapRouter.exactInputSingle(params);
    }

    function _assetGroupSwap(
        address[] memory tokensIn,
        address[] memory tokensOut,
        uint256[] memory amounts,
        uint256[] calldata rawSwapInfo
    ) internal virtual returns (uint256) {
        // only swap if tokens are different.
        if (tokensIn[0] == tokensOut[0]) {
            return amounts[0];
        }

        // fallback on default swapper (Uniswap V3) for empty swap Info
        if (rawSwapInfo.length == 0) {
            return _defaultSwap(tokensIn[0], tokensOut[0], amounts[0]);
        }

        SwapInfo[] memory swapInfo = _buildSwapInfo(tokensIn, rawSwapInfo);

        IERC20(tokensIn[0]).safeTransfer(address(swapper), amounts[0]);

        return swapper.swap(tokensIn, swapInfo, tokensOut, address(this))[0];
    }

    function _buildSwapInfo(address[] memory tokensIn, uint256[] calldata rawSwapInfo)
        internal
        virtual
        returns (SwapInfo[] memory swapInfo)
    {
        address swapTarget = address(uint160(rawSwapInfo[0]));
        address token = address(uint160(rawSwapInfo[1]));
        uint256 swapCallDataSize = rawSwapInfo[2];
        bytes memory swapCallData = new bytes(swapCallDataSize);

        if (rawSwapInfo.length < MIN_SWAP_INFO_SIZE || token != tokensIn[0]) {
            revert InvalidSwapInfo();
        }

        assembly {
            calldatacopy(add(swapCallData, 0x20), add(rawSwapInfo.offset, 0x60), swapCallDataSize)
        }

        swapInfo = new SwapInfo[](1);
        swapInfo[0].swapTarget = swapTarget;
        swapInfo[0].token = token;
        swapInfo[0].swapCallData = swapCallData;
    }
}
