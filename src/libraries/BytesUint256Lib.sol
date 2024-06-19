// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

/**
 * @dev Library used for conversion between bytes and uint256[]
 */
library BytesUint256Lib {
    /**
     * @dev encode bytes to uint256[]
     * @param data arbitrary bytes
     * @return array of uint256 representing bytes
     */
    function encode(bytes memory data) internal pure returns (uint256[] memory) {
        uint256 numChunks = (data.length + 31) / 32;
        uint256[] memory result = new uint256[](numChunks);

        for (uint256 i = 0; i < numChunks; i++) {
            uint256 chunk;
            assembly {
                chunk := mload(add(data, add(32, mul(i, 32))))
            }
            result[i] = chunk;
        }

        return result;
    }

    /**
     * @dev decode uint256[] to original bytes
     * @param data uint256 array
     * @param originalLength original bytes length
     * @return bytes
     */
    function decode(uint256[] memory data, uint256 originalLength) public pure returns (bytes memory) {
        bytes memory result = new bytes(originalLength);

        for (uint256 i = 0; i < data.length; i++) {
            uint256 chunk = data[i];
            assembly {
                mstore(add(result, add(32, mul(i, 32))), chunk)
            }
        }

        return result;
    }
}
