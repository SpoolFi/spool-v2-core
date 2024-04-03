// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface INFTPool {
    function exists(uint256 tokenId) external view returns (bool);

    function transfer(uint256 tokenId) external view returns (bool);

    function getPoolInfo()
        external
        view
        returns (
            address lpToken,
            address grailToken,
            address sbtToken,
            uint256 lastRewardTime,
            uint256 accRewardsPerShare,
            uint256 lpSupply,
            uint256 lpSupplyWithMultiplier,
            uint256 allocPoint
        );

    function getStakingPosition(uint256 tokenId)
        external
        view
        returns (
            uint256 amount,
            uint256 amountWithMultiplier,
            uint256 startLockTime,
            uint256 lockDuration,
            uint256 lockMultiplier,
            uint256 rewardDebt,
            uint256 boostPoints,
            uint256 totalMultiplier
        );

    function createPosition(uint256 amount, uint256 lockDuration) external;

    function addToPosition(uint256 tokenId, uint256 amountToAdd) external;

    function withdrawFromPosition(uint256 tokenId, uint256 amountToWithdraw) external;

    function harvestPositionTo(uint256 tokenId, address to) external;

    function lastTokenId() external view returns (uint256);

    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}
