// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {console} from "forge-std/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@0xsequence/sstore2/contracts/SSTORE2Map.sol";
import "./interfaces/IGuardManager.sol";


contract GuardManager is Ownable, IGuardManager {

    /* ========== STATE VARIABLES ========== */

    mapping(address => bool) public guardsInitialized;

    constructor () {}

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice Loop through and run guards for given Smart Vault.
     * @param smartVaultId Smart Vault address
     * @param context Request context
     */
    function runGuards(
        address smartVaultId, 
        RequestContext calldata context
    ) 
        external 
        view 
        hasGuards(smartVaultId) 
    {
        Guard[] memory guards = _readGuards(smartVaultId);

        for(uint256 i = 0; i < guards.length; i++) {
            Guard memory guard = guards[i];

            bytes memory encoded = _encodeFunctionCall(smartVaultId, guard, context);
            (bool success, bytes memory data) = guard.contractAddress.staticcall(encoded);
            _checkResult(success, data, guard.operator, guard.expectedValue);
        }
    }

    /**
     * @notice Return persisted guards for given Smart Vault
     * @param smartVaultId Smart Vault address
     * @return Array of guards
     */
    function readGuards(address smartVaultId) external view returns (Guard[] memory) {
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
    function setGuards(address smartVaultId, Guard[] calldata guards) public hasNoGuards(smartVaultId) {
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

    /**
     * @notice Reverts if smart vault doesn't have guards initialized
     */
    modifier hasGuards(address smartVaultId) {
        _guardsInitialized(smartVaultId);
        _;
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    /* ========== INTERNAL FUNCTIONS ========== */

    function _guardsNotInitialized(address smartVaultId) internal view {
        require(!guardsInitialized[smartVaultId], "GuardManager::_guardsNotInitialized: Guards already initialized.");
    }

    function _guardsInitialized(address smartVaultId) internal view {
        require(guardsInitialized[smartVaultId], "GuardManager::_guardsInitialized: Guards not initialized.");
    }

    function _readGuards(address smartVaultId) internal view returns (Guard[] memory guards) { 
        string memory key = _addressToString(smartVaultId);
        bytes memory value = SSTORE2Map.read(key);
        return abi.decode(value, (Guard[]));
    }

    function _writeGuards(address smartVaultId, Guard[] calldata guards) internal {
        string memory key = _addressToString(smartVaultId);
        SSTORE2Map.write(key, abi.encode(guards));
    }

    function _addressToString(address address_) internal pure returns(string memory) {
        return Strings.toHexString(uint256(uint160(address_)), 20);
    }

    function _checkResult(
        bool success,
        bytes memory returnValue,
        bytes2 operator,
        bytes32 value
    ) 
        internal
        pure
    {
        require(success, "GuardManager::_checkResult: Guard call failed.");
        string memory errorMessage = "GuardManager::_checkResult: A-a, go back.";

        if (operator == bytes2("==")) {
            require(abi.decode(returnValue, (bytes32)) == value, errorMessage);
        } else if (operator == bytes2("<=")) {
            require(abi.decode(returnValue, (bytes32)) <= value, errorMessage);
        } else if (operator == bytes2(">=")) {
            require(abi.decode(returnValue, (bytes32)) >= value, errorMessage);
        } else if (operator == bytes2("<")) {
            require(abi.decode(returnValue, (bytes32)) < value, errorMessage);
        } else if (operator == bytes2(">")) {
            require(abi.decode(returnValue, (bytes32)) > value, errorMessage);
        } else {
            require(abi.decode(returnValue, (bool)), errorMessage);
        }
    }

    /**
     * @notice Resolve parameter values to be used in the guard function call - based on parameter types defined in the guard object.
     */
    function _encodeFunctionCall(
        address smartVaultId,
        Guard memory guard,
        RequestContext memory context
    ) 
        internal
        pure
        returns (bytes memory)
    {
        uint16 customValueCounter = 0;

        bytes4 methodID = bytes4(keccak256(abi.encodePacked(guard.methodSignature)));
        bytes memory result = new bytes(0);

        result = bytes.concat(result, methodID);

        for (uint8 i = 0; i < guard.methodParamTypes.length; i++) {
            GuardParamType paramType = guard.methodParamTypes[i];
            
            if (paramType == GuardParamType.CustomValue) {
                result = bytes.concat(result, abi.encode(guard.methodParamValues[i]));
                customValueCounter++;
            } else if (paramType == GuardParamType.VaultAddress) {
                result = bytes.concat(result, abi.encode(smartVaultId));
            } else if (paramType == GuardParamType.Receiver) {
                result = bytes.concat(result, abi.encode(context.receiver));
            } else if (paramType == GuardParamType.Depositor) {
                result = bytes.concat(result, abi.encode(context.depositor));
            } else if (paramType == GuardParamType.Amounts) {
                result = bytes.concat(result, abi.encode(context.amounts));
            } else if (paramType == GuardParamType.Tokens) {
                result = bytes.concat(result, abi.encode(context.tokens));
            } else if (paramType == GuardParamType.RiskModel) {
            } else if (paramType == GuardParamType.RiskApetite) {
            } else if (paramType == GuardParamType.TokenID) {
            } else if (paramType == GuardParamType.AssetGroup) {
            } else {
                revert("Invalid param type");
            }
        }

        return result;
    }
}
