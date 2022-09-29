// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;


enum GuardParamType {
    VaultAddress,
    Executor,
    Receiver,
    Amounts,
    Tokens,
    RiskModel,
    RiskApetite,
    TokenID,
    AssetGroup,
    CustomValue
}

struct GuardDefinition {
    address contractAddress;
    string methodSignature;
    bytes32 expectedValue;
    GuardParamType[] methodParamTypes;
    bytes32[] methodParamValues;
    RequestType requestType;
    bytes2 operator;
}

enum RequestType {
    Deposit,
    Withdrawal
}

struct RequestContext {
    address receiver;
    address executor;
    RequestType requestType;
    uint256[] amounts;
    address[] tokens;
}

interface IGuardManager {
    function runGuards(address smartVaultId, RequestContext calldata context) external view;
    function readGuards(address smartVaultId) external view returns (GuardDefinition[] memory);

    event GuardsInitialized(address indexed smartVaultId);
}
