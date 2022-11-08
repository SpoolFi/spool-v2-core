pragma solidity ^0.8.17;

library ArrayMapping {
    /**
     * @notice Map mapping(uint256 => uint256)) values to an array
     */
    function toArray(mapping(uint256 => uint256) storage _self, uint256 length)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory arrayOut = new uint256[](length);
        for (uint8 i = 0; i < length; i++) {
            arrayOut[i] = _self[i];
        }
        return arrayOut;
    }

    /**
     * @notice Set array values to mapping slots
     */
    function setValues(mapping(uint256 => uint256) storage _self, uint256[] calldata values) external {
        for (uint8 i = 0; i < values.length; i++) {
            _self[i] = values[i];
        }
    }
}
