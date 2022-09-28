// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@0xsequence/sstore2/contracts/SSTORE2Map.sol";
import "./interfaces/IGuardManager.sol";

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
    bytes[] methodParamValues;
    string operator;
    bytes value;
}

contract GuardManager is Ownable, IGuardManager {

    /* ========== STATE VARIABLES ========== */

    constructor () {}

    /* ========== EXTERNAL FUNCTIONS ========== */

    function runGuards(address smartVaultId) public view {
        Guard[] memory guards = _readGuards(smartVaultId);

        // TODO: loop through guards
        for(uint256 i = 0; i < guards.length; i++) {
            Guard memory guard = guards[i];

            bytes[] memory parameters = _resolveParameters(smartVaultId, guard);
            bytes memory encoded = abi.encodeWithSignature(guard.methodSignature, parameters);
            (bool success, bytes memory data) = guard.contractAddress.staticcall(encoded);
            require(success, "Guard failed");
        }
    }

    function readGuards(address smartVaultId) public view returns (Guard[] memory) {
        return _readGuards(smartVaultId);
    }

    function setGuards(address smartVaultId, Guard[] calldata guards) public {
        _writeGuards(smartVaultId, guards);
    }

    /* ========== MODIFIERS ========== */

    /* ========== PUBLIC FUNCTIONS ========== */

    /* ========== INTERNAL FUNCTIONS ========== */

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

    /**
     * @notice Resolve parameter values to be used in the guard function call - based on parameter types defined in the guard object.
     */
    function _resolveParameters(address smartVaultId, Guard memory guard) internal view returns (bytes[] memory) {
        uint16 customValueCounter = 0;
        bytes[] memory params = new bytes[](guard.methodParamTypes.length);

        for (uint16 i = 0; i < guard.methodParamTypes.length; i++) {
            GuardParamType paramType = guard.methodParamTypes[i];

            if (paramType == GuardParamType.CustomValue) {
                params[i] = guard.methodParamValues[customValueCounter];
                customValueCounter++;
            } else if (paramType == GuardParamType.VaultAddress) {
                params[i] = abi.encodePacked(smartVaultId);
            } else if (paramType == GuardParamType.UserAddress) {
                params[i] = abi.encodePacked(msg.sender);
            } else {
                revert("Invalid param type");
            }
        }

        return params;
    }
}
