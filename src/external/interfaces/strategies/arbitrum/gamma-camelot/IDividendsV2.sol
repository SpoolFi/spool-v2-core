// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IDividendsV2 {
    function distributedTokensLength() external view returns (uint256);

    function distributedToken(uint256 index) external view returns (address);

    function isDistributedToken(address token) external view returns (bool);

    function addDividendsToPending(address token, uint256 amount) external;

    function harvestAllDividends() external;
}
