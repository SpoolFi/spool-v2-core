// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;


enum GuardParamType {
    VaultAddress,
    UserAddress,
    UserDepositAmounts,
    Tokens,
    UserWithdrawalAmount,
    UserWithdrawalTokens,
    RiskModel,
    RiskApetite,
    TokenID,
    AssetGroup,
    CustomValue
}

struct Guard {
    address contractAddress;
    string methodSignature;
    GuardParamType[] methodParamTypes;
    bytes32[] methodParamValues;
    bytes2 operator;
    bytes32 expectedValue;
}

interface IGuardManager {
    function runGuards(address smartVaultId, address user) external;
    function readGuards(address smartVaultId) external view returns (Guard[] memory);

    event GuardsInitialized(address indexed smartVaultId);
}
