// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

interface IRiskManager {
    function registerRiskProvider(address riskProvider, bool isEnabled) external;

    function setRiskScores(address riskProvider, uint256[] memory riskScores) external;

    function calculateAllocations(
        address riskProvider,
        address[] memory strategies,
        uint8 riskTolerance,
        uint256[] memory riskScores,
        uint256[] memory strategyApys
    ) external returns (uint256[][] memory);

    /// TODO: where to put this? will pass to smart vault
    function reallocate(address smartVault) external;

    function setAllocations(address smartVault, uint256[] memory allocations) external;

    /**
     * @notice TODO
     * @return riskTolerance
     */
    function riskTolerance(address smartVault) external view returns (int256 riskTolerance);

    /**
     * @notice TODO
     * @return riskProviderAddress
     */
    function riskProvider(address smartVault) external view returns (address riskProviderAddress);

    /**
     * @notice TODO
     * @return allocations
     */
    function allocations(address smartVault) external view returns (uint256[] memory allocations);
}
