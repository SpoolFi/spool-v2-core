// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "./interfaces/ISwapper.sol";
import "./libraries/SmartVaultManagerLib.sol";

contract Swapper is ISwapper {
    function swap(SwapInfo memory swapInfo) external {
        (bool success, bytes memory data) = swapInfo.swapTarget.call(swapInfo.swapCallData);
        if (!success) revert(SpoolUtils.getRevertMsg(data));
    }
}
