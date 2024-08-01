// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

interface IMetaVault {
    /**
     * @notice Retrieves the underlying asset
     * @return address of asset
     */
    function asset() external view returns (address);
}
