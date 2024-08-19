// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IXGrail {
    function minRedeemDuration() external view returns (uint256);

    function redeem(uint256 xGrailAmount, uint256 duration) external;

    function finalizeRedeem(uint256 redeemIndex) external;

    function getUserRedeem(address userAddress, uint256 redeemIndex)
        external
        view
        returns (
            uint256 grailAmount,
            uint256 xGrailAmount,
            uint256 endTime,
            address dividendsContract,
            uint256 dividendsAllocation
        );

    function getUserRedeemsLength(address userAddress) external view returns (uint256);

    function dividendsAddress() external view returns (address);
}
