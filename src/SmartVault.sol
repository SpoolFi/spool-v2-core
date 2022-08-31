// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "./interfaces/ISmartVault.sol";

contract SmartVault is ISmartVault, Ownable, ERC721 {
    /* ========== STATE VARIABLES ========== */

    /* ========== CONSTRUCTOR ========== */

    address[] internal _assetGroup;

    /**
     * @notice Initializes variables
     */
    constructor(address[] _assets) {
        _assetGroup = _assets;
    }

    /* ========== MODIFIERS ========== */

    /* ========== EXTERNAL FUNCTIONS ========== */

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /* ========== PUBLIC FUNCTIONS ========== */

    /* ========== INTERNAL FUNCTIONS ========== */

    /* ========== PRIVATE FUNCTIONS ========== */
}
