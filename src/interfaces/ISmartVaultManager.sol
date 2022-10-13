// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface ISmartVaultReallocator {
    function allocations(address smartVault) external view returns (uint256[] memory allocations);

    function strategies(address smartVault) external view returns (address[] memory);

    function riskTolerance(address smartVault) external view returns (int256 riskTolerance);

    function riskProvider(address smartVault) external view returns (address riskProviderAddress);

    function setRiskProvider(address smartVault, address riskProvider_) external;

    function setAllocations(address smartVault, uint256[] memory allocations) external;

    function setStrategies(address smartVault, address[] memory strategies_) external;

    function reallocate() external;
}

interface ISmartVaultFlusher {
    function getLatestFlushIndex(address smartVault) external view returns (uint256);

    function flushSmartVault(address smartVault) external;
}

interface ISmartVaultSyncer {
    function syncSmartVault(address smartVault) external;
}

interface ISmartVaultRegistry {
    function isSmartVault(address address_) external view returns (bool);

    function registerSmartVault(address address_) external;

    function removeSmartVault(address smartVault) external;

    function addDeposits(
        address smartVault,
        uint256[] memory allocations,
        uint256[] memory amounts,
        address[] memory tokens
    ) external returns (uint256);
}

interface ISmartVaultManager is ISmartVaultRegistry, ISmartVaultReallocator, ISmartVaultFlusher, ISmartVaultSyncer {}
