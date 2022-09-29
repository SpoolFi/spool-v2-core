// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "./RequestType.sol";

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

struct RequestContext {
    address receiver;
    address executor;
    RequestType requestType;
    uint256[] amounts;
    address[] tokens;
}

interface IGuardManager {
    function runGuards(address smartVault, RequestContext calldata context) external view;
    function readGuards(address smartVault) external view returns (GuardDefinition[] memory);
    function setGuards(address smartVault, GuardDefinition[] calldata guards) external;

    event GuardsInitialized(address indexed smartVaultId);
}
