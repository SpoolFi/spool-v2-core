// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "./RequestType.sol";

error GuardsAlreadyInitialized();
error GuardsNotInitialized();
error GuardError();

/**
 * @notice Used when a guard fails.
 * @param guardNum Sequential number of the guard that failed.
 */
error GuardFailed(uint256 guardNum);

error InvalidGuardParamType(uint256 paramType);

/**
 * @param Receiver Receiver of receipt NFT.
 * @param Executor In case of deposit, executor of deposit action; in case of withdrawal, executor of redeem action.
 * @param Owner In case of deposit, owner of assets; in case of withdrawal, owner of vault shares.
 */
enum GuardParamType {
    VaultAddress,
    Executor,
    Receiver,
    Owner,
    Amounts,
    Tokens,
    AssetGroup,
    CustomValue,
    DynamicCustomValue
}

struct GuardDefinition {
    address contractAddress;
    string methodSignature;
    bytes32 expectedValue;
    GuardParamType[] methodParamTypes;
    bytes[] methodParamValues;
    RequestType requestType;
    bytes2 operator;
}

/**
 * @param receiver Receiver of receipt NFT.
 * @param executor In case of deposit, executor of deposit action; in case of withdrawal, executor of redeem action.
 * @param owner In case of deposit, owner of assets; in case of withdrawal, owner of vault shares.
 */
struct RequestContext {
    address receiver;
    address executor;
    address owner;
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
