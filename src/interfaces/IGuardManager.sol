// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;


enum GuardParamType {
    VaultAddress,
    Depositor,
    Receiver,
    Amounts,
    Tokens,
    RiskModel,
    RiskApetite,
    TokenID,
    AssetGroup,
    CustomValue
}

struct Guard {
    address contractAddress;
    string methodSignature;
    bytes32 expectedValue;
    GuardParamType[] methodParamTypes;
    bytes32[] methodParamValues;
    bytes2 operator;
}

struct RequestContext {
    address receiver;
    address depositor;
    bool isDeposit;
    uint256[] amounts;
    address[] tokens;
}

interface IGuardManager {
    function runGuards(address smartVaultId, RequestContext calldata context) external view;
    function readGuards(address smartVaultId) external view returns (Guard[] memory);

    event GuardsInitialized(address indexed smartVaultId);
}
