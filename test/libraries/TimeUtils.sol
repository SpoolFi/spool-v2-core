// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

library TimeUtils {
    function getTimestampInFuture(
        uint secondsAfterNow
    ) internal view returns (uint256) {
        return block.timestamp + secondsAfterNow;
    }

    function getTimestampInPast(
        uint secondsBeforeNow
    ) internal view returns (uint256) {
        return block.timestamp - secondsBeforeNow;
    }

    function getTimestampInInfiniteFuture() internal pure returns (uint256) {
        return type(uint256).max;
    }
}
