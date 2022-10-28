// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "./IVault.sol";

/* ========== ERRORS ========== */

/**
 * @notice Used when the balance is too low to perform an action.
 * @param available Balance available for the action.
 * @param required Balance required for the action.
 */
error InsufficientBalance(uint256 available, uint256 required);

/**
 * @notice Used when the ID for withdrawal NFTs overflows.
 * @dev Should never happen.
 */
error WithdrawalIdOverflow();

/**
 * @notice Used when ID does not represent a withdrawal NFT.
 * @param withdrawalNftId Invalid withdrawal NFT ID.
 */
error InvalidWithdrawalNftId(uint256 withdrawalNftId);

/**
 * @notice Used when balance of the NFT is invalid.
 * @param balance Actual balance of the NFT.
 */
error InvalidNftBalance(uint256 balance);

/**
 * @notice Used when function that can only be called by SmartVaultManagerd is called by some other account.
 * @param caller Actual caller of the function.
 */
error NotSmartVaultManager(address caller);

/* ========== STRUCTS ========== */

struct DepositMetadata {
    uint256[] assets;
    uint256 initiated; // TODO: initiated / locked until / timelock ?
    uint256 flushIndex;
}

/**
 * @notice Holds metadata detailing the withdrawal behind the NFT.
 * @param vaultShares Vault shares withdrawn.
 * @param flushIndex Flush index into which withdrawal is included.
 */
struct WithdrawalMetadata {
    uint256 vaultShares;
    uint256 flushIndex;
}

/* ========== INTERFACES ========== */

interface ISmartVault is IVault, IERC1155Upgradeable {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @return name Name of the vault
     */
    function vaultName() external view returns (string memory name);

    /**
     * @notice TODO
     * @return isTransferable
     */
    function isShareTokenTransferable() external view returns (bool isTransferable);

    /**
     * @notice Gets metadata for a withdrawal NFT.
     * @param withdrawalNftId ID of the withdrawal NFT.
     * @return Metadata of the withdrawal NFT.
     */
    function getWithdrawalMetadata(uint256 withdrawalNftId) external view returns (WithdrawalMetadata memory);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice TODO
     * @param nftIds TODO
     * @return shares TODO
     */
    function burnDepositNFTs(uint256[] calldata nftIds) external returns (uint256 shares);

    /**
     * @notice TODO
     * @param nftIds TODO
     * @return assets TODO
     */
    function burnWithdrawalNFTs(uint256[] calldata nftIds) external returns (uint256[] memory assets);

    /**
     * @notice TODO
     * @param assets TODO
     * @param receiver TODO
     * @param depositor TODO
     * @return depositNFTId TODO
     */
    function depositFor(uint256[] calldata assets, address receiver, address depositor)
        external
        returns (uint256 depositNFTId);

    /**
     * @notice TODO
     * @param assets TODO
     * @param receiver TODO
     * @param slippages TODO
     * @return receipt TODO
     */
    function depositFast(uint256[] calldata assets, address receiver, uint256[][] calldata slippages)
        external
        returns (uint256 receipt);

    /**
     * @notice Used to withdraw underlying asset.
     * @param assets TODO
     * @param tokens TODO
     * @param receiver TODO
     * @param owner TODO
     * @param slippages TODO
     * @param owner TODO
     * @return returnedAssets  TODO
     */
    function withdrawFast(
        uint256[] calldata assets,
        address[] calldata tokens,
        address receiver,
        uint256[][] calldata slippages,
        address owner
    ) external returns (uint256[] memory returnedAssets);

    /**
     * @notice Requests withdrawal of assets by burning vault shares.
     * @dev Requirements:
     * - owner must have enough shares
     * - caller must be authorized to request withdrawal by owner
     * @param vaultShares Amount of vault shares to burn.
     * @param receiver Receiver of the withdrawal NFT.
     * @param owner Owner of shares.
     * @return ID of the withdrawal NFT.
     */
    function requestWithdrawal(uint256 vaultShares, address receiver, address owner) external returns (uint256);

    /**
     * @notice Handles withdrawals when flushing vault.
     * @dev Internal function.
     * Requirements:
     * - must be called by SmartVaultManager contract
     * @param withdrawnVaultShares Amount of vault's shares withdrawn in this flush.
     * @param withdrawnStrategyShares Amount of strategies' shares withdrawn in this flush.
     * @param strategies Strategies from where withdrawals are made.
     */
    function handleWithdrawalFlush(
        uint256 withdrawnVaultShares,
        uint256[] memory withdrawnStrategyShares,
        address[] memory strategies
    ) external;

    /**
     * @notice Claims withdrawal of assets by burning withdrawal NFT.
     * @dev Requirements:
     * - withdrawal NFT must be valid
     * @param withdrawalNftId ID of withdrawal NFT to burn.
     * @param receiver Receiver of claimed assets.
     * @return assetAmounts Amounts of assets claimed.
     * @return assetTokens Addresses of assets claimed.
     */
    function claimWithdrawal(uint256 withdrawalNftId, address receiver)
        external
        returns (uint256[] memory, address[] memory);
}
