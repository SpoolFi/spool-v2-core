// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

error SmartVaultAlreadyRegistered(address address_);
error InvalidAssetLengths();
error InvalidArrayLength();
error EmptyStrategyArray();
error InvalidSmartVault(address address_);
error InvalidRiskProvider(address address_);
error InvalidFlushAmount(address smartVault);
error InvalidDepositAmount(address smartVault);
error SwapTolerance();

struct SwapInfo {
    address swapTarget;
    bytes swapCallData;
}

struct DepositBag {
    address[] tokens;
    address[] strategies;
    uint256[] depositsIn;
    uint256[] decimals;
    uint256[] exchangeRates;
    uint256[][] depositRatios;
    uint256 depositUSD;
    uint256 usdDecimals;
}

struct DepositRatioQueryBag {
    address smartVault;
    address[] tokens;
    address[] strategies;
    uint256[] allocations;
    uint256[] exchangeRates;
    uint256[][] strategyRatios;
    uint256 usdDecimals;
}

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

interface ISmartVaultDeposits {
    function getDepositRatio(DepositRatioQueryBag calldata bag) external view returns (uint256[] memory);

    function distributeVaultDeposits(
        DepositRatioQueryBag memory bag,
        uint256[] memory depositsIn,
        SwapInfo[] calldata swapInfo
    ) external returns (uint256[][] memory);
}

interface ISmartVaultSyncer {
    function syncSmartVault(address smartVault) external;
}

interface ISmartVaultRegistry {
    function isSmartVault(address address_) external view returns (bool);

    function registerSmartVault(address address_) external;

    function removeSmartVault(address smartVault) external;
}

interface ISmartVaultManager is ISmartVaultRegistry, ISmartVaultReallocator, ISmartVaultSyncer {
    function dhwIndexes(address smartVault, uint256 flushIndex) external view returns (uint256[] memory);

    function getLatestFlushIndex(address smartVault) external view returns (uint256);

    function flushSmartVault(address smartVault, SwapInfo[] calldata swapInfo) external;

    function smartVaultDeposits(address smartVault, uint256 flushIdx) external returns (uint256[] memory);

    function addDeposits(address smartVault, uint256[] memory amounts) external returns (uint256);

    function getDepositRatio(address smartVault) external view returns (uint256[] memory);

    event SmartVaultFlushed(address smartVault, uint256 flushIdx);
}
