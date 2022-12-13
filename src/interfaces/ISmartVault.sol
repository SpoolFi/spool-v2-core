// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./RequestType.sol";

/* ========== ERRORS ========== */

/**
 * @notice Used when the ID for deposit NFTs overflows.
 * @dev Should never happen.
 */
error DepositIdOverflow();

/**
 * @notice Used when the ID for withdrawal NFTs overflows.
 * @dev Should never happen.
 */
error WithdrawalIdOverflow();

/**
 * @notice Used when ID does not represent a deposit NFT.
 * @param depositNftId Invalid ID for deposit NFT.
 */
error InvalidDepositNftId(uint256 depositNftId);

/**
 * @notice Used when ID does not represent a withdrawal NFT.
 * @param withdrawalNftId Invalid ID for withdrawal NFT.
 */
error InvalidWithdrawalNftId(uint256 withdrawalNftId);

/**
 * @notice Used when balance of the NFT is invalid.
 * @param balance Actual balance of the NFT.
 */
error InvalidNftBalance(uint256 balance);

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

interface ISmartVault is IERC20Upgradeable, IERC1155Upgradeable {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @return asset group ID
     */
    function assetGroupId() external view returns (uint256);

    /**
     * @return name Name of the vault
     */
    function vaultName() external view returns (string memory name);

    /**
     * @notice Gets metadata for a deposit NFT.
     * @param depositNftId ID of the deposit NFT.
     * @return Metadata of the deposit NFT.
     */
    function getDepositMetadata(uint256 depositNftId) external view returns (DepositMetadata memory);

    /**
     * @notice Gets metadata for a withdrawal NFT.
     * @param withdrawalNftId ID of the withdrawal NFT.
     * @return Metadata of the withdrawal NFT.
     */
    function getWithdrawalMetadata(uint256 withdrawalNftId) external view returns (WithdrawalMetadata memory);

    /**
     * @dev Returns the total amount of the underlying asset that is “managed” by Vault.
     *
     * - SHOULD include any compounding that occurs from yield.
     * - MUST be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT revert.
     */
    function totalAssets() external view returns (uint256[] memory totalManagedAssets);

    /**
     * @dev Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
     * scenario where all the conditions are met.
     *
     * - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
     * - MUST NOT revert.
     *
     * NOTE: This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the
     * “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and
     * from.
     */
    function convertToAssets(uint256 shares) external view returns (uint256[] memory assets);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function mint(address receiver, uint256 vaultShares) external;

    function burn(address owner, uint256 vaultShares, address[] memory strategies, uint256[] memory shares) external;

    function mintWithdrawalNFT(address receiver, WithdrawalMetadata memory metadata)
        external
        returns (uint256 receipt);

    function burnNFT(address owner, uint256 nftId, RequestType type_) external;

    function mintDepositNFT(address receiver, DepositMetadata memory metadata) external returns (uint256 receipt);

    /**
     * @notice Transfers unclaimed shares to claimer.
     * @dev Requirements:
     * - can only be called from smart vault manager.
     * @param claimer Address that claims the shares.
     * @param amount Amount of shares to transfer.
     */
    function claimShares(address claimer, uint256 amount) external;
}
