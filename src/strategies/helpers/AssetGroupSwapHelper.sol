// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/ISwapper.sol";
import "../../interfaces/CommonErrors.sol";

error InvalidSwapInfo();

abstract contract AssetGroupSwapHelper {
    using SafeERC20 for IERC20;

    ISwapper public immutable swapper;

    uint256 constant MIN_SWAP_INFO_SIZE = 4;

    constructor(ISwapper swapper_) {
        if (address(swapper_) == address(0)) {
            revert ConfigurationAddressZero();
        }

        swapper = swapper_;
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
