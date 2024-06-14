// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

/**
 * @dev Library used for conversion between bytes and uint256[]
 */
library BytesUint256Lib {
    /**
     * @dev encode bytes to uint256[]
     * @param data arbitrary bytes
     * @return result array of uint256 representing bytes
     */
    function encode(bytes memory data) internal pure returns (uint256[] memory result) {
        assembly {
            let numChunks := shr(5, add(mload(data), 63))
            let limit := shl(5, numChunks)
            result := mload(0x40)
            mstore(0x40, add(result, limit))
            mstore(result, sub(numChunks, 1))
            for { let pos := 32 } lt(pos, limit) { pos := add(pos, 32) } {
                mstore(add(result, pos), mload(add(data, pos)))
            }
        }
    }

    /**
     * @dev decode uint256[] to original bytes
     * @param data uint256 array
     * @param originalLength original bytes length
     * @return result bytes
     */
    function decode(uint256[] memory data, uint256 originalLength) internal pure returns (bytes memory result) {
        require((originalLength + 31) >> 5 == data.length);
        assembly {
            let limit := shl(5, add(mload(data), 1))
            result := mload(0x40)
            mstore(0x40, add(result, shl(5, shr(5, add(originalLength, 63)))))
            mstore(result, originalLength)
            for { let pos := 32 } lt(pos, limit) { pos := add(pos, 32) } {
                mstore(add(result, pos), mload(add(data, pos)))
            }
        }
    }
}
