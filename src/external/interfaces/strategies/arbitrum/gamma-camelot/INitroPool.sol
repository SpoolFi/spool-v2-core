// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface INitroPool {
    function withdraw(uint256 tokenId) external;
    function nftPool() external returns (address);
    function rewardsToken1() external returns (address);
    function harvest() external;
}
