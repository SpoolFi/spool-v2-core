// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../interfaces/ISmartVault.sol";
import "../interfaces/Constants.sol";
import "../access/SpoolAccessControllable.sol";

/* ========== ERRORS ========== */

/**
 * @notice Used when the NFT passed is not a deposit NFT.
 * @param smartVault Address of the smart vault.
 * @param nftId ID of the NFT.
 */
error NotDepositNFT(address smartVault, uint256 nftId);

/* ========== CONTRACTS ========== */

contract TimelockGuard is SpoolAccessControllable {
    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when smart vault owner updates the timelock
     * @param smartVault Address of the smart vault.
     * @param timelock value of the timelock, in seconds
     */
    event UpdatedTimelock(address indexed smartVault, uint256 indexed timelock);

    /* ========== STATE VARIABLES ========== */

    /**
     * @notice Timelocks for a smart vault.
     * Each smart vault can have a single timelock, updated by the owner.
     */
    mapping(address => uint256) public timelocks;

    constructor(ISpoolAccessControl accessControl_) SpoolAccessControllable(accessControl_) {}

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Check if the timelock is valid for a range of dNFTs.
     * @param smartVault Address of the smart vault.
     * @param nftIds Array of dNFTs to check.
     * @return valid True when the timelock is valid, false otherwise.
     */
    function checkTimelock(address smartVault, uint256[] calldata nftIds) external view returns (bool) {
        bytes[] memory metadatas = ISmartVault(smartVault).getMetadata(nftIds);
        uint256 timelock = timelocks[smartVault];

        for (uint256 i; i < metadatas.length; i++) {
            uint256 nftId = nftIds[i];
            if (nftId >= MAXIMAL_DEPOSIT_ID) {
                revert NotDepositNFT(smartVault, nftId);
            }

            DepositMetadata memory metadata = abi.decode(metadatas[i], (DepositMetadata));

            if ((block.timestamp - metadata.initiated) <= timelock) {
                return false;
            }
        }

        return true;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Update the timelock for a smart vault.
     * @dev Requirements:
     * - caller must be the owner of the smart vault
     * @param smartVault Address of the smart vault.
     * @param timelock New timelock value, in seconds.
     */
    function updateTimelock(address smartVault, uint256 timelock)
        external
        onlySmartVaultRole(smartVault, ROLE_SMART_VAULT_ADMIN, msg.sender)
    {
        timelocks[smartVault] = timelock;

        emit UpdatedTimelock(smartVault, timelock);
    }
}
