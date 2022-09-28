// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
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

    /* ========== CONSTRUCTOR ========== */

    function _getGuards(address smartVaultId) internal view returns (Guard[] memory guards) { 
        // TODO: Load guards from contract bytecode using that fancy lib
        revert("0"); 
    }

    function saveGuards(address smartVaultId, Guard[] calldata guard) external {

    }

    function toBytes(address a) public pure returns (bytes memory b){
        assembly {
            let m := mload(0x40)
            a := and(a, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            mstore(add(m, 20), xor(0x140000000000000000000000000000000000000000, a))
            mstore(0x40, add(m, 52))
            b := m
        }
    }

    function _resolveParameters(address smartVaultId, Guard memory guard) internal view returns (bytes[] memory) {
        // TODO: loop through methodParamValues + methodParamTypes and resolve values
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

    function runGuards(address smartVaultId, Guard[] memory guards) public view {
        Guard[] memory guards = _getGuards(smartVaultId);

        // TODO: loop through guards
        for(uint256 i = 0; i < guards.length; i++) {
            Guard memory guard = guards[i];

            bytes[] memory parameters = _resolveParameters(smartVaultId, guard);
            bytes memory encoded = abi.encodeWithSignature(guard.methodSignature, parameters);
            (bool success, bytes memory data) = guard.contractAddress.staticcall(encoded);
            require(success, "Guard failed");
        }
    }

    /* ========== MODIFIERS ========== */

    /* ========== EXTERNAL FUNCTIONS ========== */

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /* ========== PUBLIC FUNCTIONS ========== */

    /* ========== INTERNAL FUNCTIONS ========== */

    /* ========== PRIVATE FUNCTIONS ========== */
}
