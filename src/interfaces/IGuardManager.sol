// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./ISmartVault.sol";
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
 * @custom:member Receiver Receiver of receipt NFT.
 * @custom:member Executor In case of deposit, executor of deposit action; in case of withdrawal, executor of redeem action.
 * @custom:member Owner In case of deposit, owner of assets; in case of withdrawal, owner of vault shares.
 */
enum GuardParamType {
    VaultAddress,
    Executor,
    Receiver,
    Owner,
    Assets,
    Tokens,
    AssetGroup,
    CustomValue,
    DynamicCustomValue
}

/**
 * @custom:member contractAddress Address of the contract to invoke
 * @custom:member methodSignature Signature of the method to invoke
 * @custom:member expectedValue Value to use when comparing with the guard function result.
 * - System only supports guards with return values that can be cast to uint256.
 * @custom:member methodParamTypes Types of parameters that the guard function is expecting.
 * @custom:member methodParamValues Parameter values that will be passed into the guard function call.
 * - This array should only include fixed/static values. Parameters that are resolved at runtime should be omitted.
 * - All values should be encoded using "abi.encode" before passing them to the GuardManager contract.
 * - We assume that all static types are encoded to 32 bytes. Fixed-size static arrays and structs with only static
 *      type members are not supported.
 * @custom:member operator The operator to use when comparing expectedValue to guard's function result.
 * - If empty, system will assume the expected value is bool(true).
 */
struct GuardDefinition {
    address contractAddress;
    string methodSignature;
    uint256 expectedValue;
    GuardParamType[] methodParamTypes;
    bytes[] methodParamValues;
    bytes2 operator;
}

/**
 * @custom:member receiver Receiver of receipt NFT.
 * @custom:member executor In case of deposit, executor of deposit action; in case of withdrawal, executor of redeem action.
 * @custom:member owner In case of deposit, owner of assets; in case of withdrawal, owner of vault shares.
 */
struct RequestContext {
    address receiver;
    address executor;
    address owner;
    RequestType requestType;
    uint256[] assets;
    address[] tokens;
}

interface IGuardManager {
    /**
     * @notice Runs guards for a smart vault.
     * @dev Reverts if any guard fails.
     * The context.methodParamValues array should only include fixed/static values.
     * Parameters that are resolved at runtime should be omitted. All values should be encoded using "abi.encode" before
     * passing them to the GuardManager contract. We assume that all static types are encoded to 32 bytes. Fixed-size
     * static arrays and structs with only static type members are not supported.
     * @param smartVault Smart vault for which to run the guards.
     * @param context Context for running the guards.
     */
    function runGuards(address smartVault, RequestContext calldata context) external view;

    /**
     * @notice Gets guards for smart vault and request type.
     * @param smartVault Smart vault for which to get guards.
     * @param requestType Request type for which to get guards.
     * @return guards Guards for the smart vault and request type.
     */
    function readGuards(address smartVault, RequestType requestType)
        external
        view
        returns (GuardDefinition[] memory guards);

    /**
     * @notice Sets guards for the smart vault.
     * @dev
     * @dev Requirements:
     * - caller must have role ROLE_SMART_VAULT_INTEGRATOR
     * - guards should not have been already set for the smart vault
     * @param smartVault Smart vault for which to set the guards.
     * @param guards Guards to set. Grouped by the request types.
     * @param requestTypes Request types for groups of guards.
     */
    function setGuards(address smartVault, GuardDefinition[][] calldata guards, RequestType[] calldata requestTypes)
        external;

    /**
     * @notice Emitted when guards are set for a smart vault.
     * @param smartVault Smart vault for which guards were set.
     */
    event GuardsInitialized(address indexed smartVault);
}
