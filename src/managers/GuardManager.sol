// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {console} from "forge-std/console.sol";
import "@openzeppelin/utils/Strings.sol";
import "@0xsequence/sstore2/SSTORE2.sol";
import "../interfaces/IGuardManager.sol";

contract GuardManager is IGuardManager {
    /* ========== STATE VARIABLES ========== */

    mapping(address => bool) public guardsInitialized;
    mapping(address => address) internal guardPointer;

    constructor() {}

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice Loop through and run guards for given Smart Vault.
     * @param smartVaultId Smart Vault address
     * @param context Request context
     */
    function runGuards(address smartVaultId, RequestContext calldata context) external view {
        if (!guardsInitialized[smartVaultId]) {
            return;
        }

        GuardDefinition[] memory guards = _readGuards(smartVaultId);

        for (uint256 i = 0; i < guards.length; i++) {
            GuardDefinition memory guard = guards[i];

            if (guard.requestType != context.requestType) {
                continue;
            }

            bytes memory encoded = _encodeFunctionCall(smartVaultId, guard, context);
            (bool success, bytes memory data) = guard.contractAddress.staticcall(encoded);
            _checkResult(success, data, guard.operator, guard.expectedValue, i);
        }
    }

    /**
     * @notice Return persisted guards for given Smart Vault
     * @param smartVaultId Smart Vault address
     * @return Array of guards
     */
    function readGuards(address smartVaultId) external view returns (GuardDefinition[] memory) {
        return _readGuards(smartVaultId);
    }

    /**
     * @notice Persist guards for given Smart Vault
     * Requirements:
     * - smart vault should not have prior guards initialized
     *
     * @param smartVaultId Smart Vault address
     * @param guards Array of guards
     */
    function setGuards(address smartVaultId, GuardDefinition[] calldata guards) public hasNoGuards(smartVaultId) {
        _writeGuards(smartVaultId, guards);
        guardsInitialized[smartVaultId] = true;

        emit GuardsInitialized(smartVaultId);
    }

    /* ========== MODIFIERS ========== */

    /**
     * @notice Reverts if smart vault already has guards initialized
     */
    modifier hasNoGuards(address smartVaultId) {
        _guardsNotInitialized(smartVaultId);
        _;
    }
    /* ========== PUBLIC FUNCTIONS ========== */

    /* ========== INTERNAL FUNCTIONS ========== */

    function _guardsNotInitialized(address smartVaultId) internal view {
        if (guardsInitialized[smartVaultId]) revert GuardsAlreadyInitialized();
    }

    function _readGuards(address smartVaultId) internal view returns (GuardDefinition[] memory guards) {
        bytes memory value = SSTORE2.read(guardPointer[smartVaultId]);
        return abi.decode(value, (GuardDefinition[]));
    }

    function _writeGuards(address smartVaultId, GuardDefinition[] calldata guards) internal {
        address key = SSTORE2.write(abi.encode(guards));
        guardPointer[smartVaultId] = key;
    }

    function _addressToString(address address_) internal pure returns (string memory) {
        return Strings.toHexString(uint256(uint160(address_)), 20);
    }

    function _checkResult(bool success, bytes memory returnValue, bytes2 operator, bytes32 value, uint256 guardNum)
        internal
        pure
    {
        if (!success) revert GuardError();

        bool result = true;

        if (operator == bytes2("==")) {
            result = abi.decode(returnValue, (bytes32)) == value;
        } else if (operator == bytes2("<=")) {
            result = abi.decode(returnValue, (bytes32)) <= value;
        } else if (operator == bytes2(">=")) {
            result = abi.decode(returnValue, (bytes32)) >= value;
        } else if (operator == bytes2("<")) {
            result = abi.decode(returnValue, (bytes32)) < value;
        } else if (operator == bytes2(">")) {
            result = abi.decode(returnValue, (bytes32)) > value;
        } else {
            result = abi.decode(returnValue, (bool));
        }

        if (!result) revert GuardFailed(guardNum);
    }

    /**
     * @notice Resolve parameter values to be used in the guard function call and encode
     * together with methodID.
     * @dev As specified in https://docs.soliditylang.org/en/v0.8.17/abi-spec.html#use-of-dynamic-types
     */
    function _encodeFunctionCall(address smartVaultId, GuardDefinition memory guard, RequestContext memory context)
        internal
        pure
        returns (bytes memory)
    {
        bytes4 methodID = bytes4(keccak256(abi.encodePacked(guard.methodSignature)));
        uint256 paramsLength = guard.methodParamTypes.length;
        bytes memory result = new bytes(0);

        result = bytes.concat(result, methodID);
        uint16 customValueIdx = 0;
        uint256 paramsEndLoc = paramsLength * 32;

        // Loop through parameters and
        // - store values for simple types
        // - store param value location for dynamic types
        for (uint256 i = 0; i < paramsLength; i++) {
            GuardParamType paramType = guard.methodParamTypes[i];

            if (paramType == GuardParamType.DynamicCustomValue) {
                result = bytes.concat(result, abi.encode(paramsEndLoc));
                paramsEndLoc += 32 + guard.methodParamValues[customValueIdx].length;
                customValueIdx++;
            } else if (paramType == GuardParamType.CustomValue) {
                result = bytes.concat(result, guard.methodParamValues[customValueIdx]);
                customValueIdx++;
            } else if (paramType == GuardParamType.VaultAddress) {
                result = bytes.concat(result, abi.encode(smartVaultId));
            } else if (paramType == GuardParamType.Receiver) {
                result = bytes.concat(result, abi.encode(context.receiver));
            } else if (paramType == GuardParamType.Executor) {
                result = bytes.concat(result, abi.encode(context.executor));
            } else if (paramType == GuardParamType.Owner) {
                result = bytes.concat(result, abi.encode(context.owner));
            } else if (paramType == GuardParamType.Amounts) {
                result = bytes.concat(result, abi.encode(paramsEndLoc));
                paramsEndLoc += 32 + context.amounts.length * 32;
            } else if (paramType == GuardParamType.Tokens) {
                result = bytes.concat(result, abi.encode(paramsEndLoc));
                paramsEndLoc += 32 + context.tokens.length * 32;
            } else {
                revert InvalidGuardParamType(uint256(paramType));
            }
        }

        // Loop through params again and store values for dynamic types.
        customValueIdx = 0;
        for (uint256 i = 0; i < paramsLength; i++) {
            GuardParamType paramType = guard.methodParamTypes[i];

            if (paramType == GuardParamType.DynamicCustomValue) {
                result = bytes.concat(result, abi.encode(guard.methodParamValues[customValueIdx].length / 32));
                result = bytes.concat(result, guard.methodParamValues[customValueIdx]);
                customValueIdx++;
            } else if (paramType == GuardParamType.CustomValue) {
                customValueIdx++;
            } else if (paramType == GuardParamType.Amounts) {
                result = bytes.concat(result, abi.encode(context.amounts.length));
                result = bytes.concat(result, abi.encodePacked(context.amounts));
            } else if (paramType == GuardParamType.Tokens) {
                result = bytes.concat(result, abi.encode(context.tokens.length));
                result = bytes.concat(result, abi.encodePacked(context.tokens));
            }
        }

        return result;
    }
}
