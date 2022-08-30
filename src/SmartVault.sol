// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "./interfaces/ISmartVault.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract SmartVault is ERC721, ISmartVault {
    /* ========== STATE VARIABLES ========== */

    /* ========== CONSTRUCTOR ========== */

    address[] internal _assetGroup;

    /**
     * @notice Initializes variables
     */
    constructor(address[] _assets) {
        _assetGroup = _assets;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /* ========== MUTATIVE FUNCTIONS ========== */

    /* ========== PRIVATE FUNCTIONS ========== */

    /* ========== RESTRICTION FUNCTIONS ========== */

    /* ========== MODIFIERS ========== */
}
