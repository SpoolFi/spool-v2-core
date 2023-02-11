// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "@openzeppelin-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./RequestType.sol";
import "./Constants.sol";

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

/**
 * @notice Used when someone wants to transfer invalid NFT shares amount.
 * @param transferAmount Amount of shares requested to be transferred.
 */
error InvalidNftTransferAmount(uint256 transferAmount);

/* ========== STRUCTS ========== */

struct DepositMetadata {
    uint256[] assets;
    uint256 initiated;
    uint256 flushIndex;
}

/**
 * @notice Holds metadata detailing the withdrawal behind the NFT.
 * @custom:member vaultShares Vault shares withdrawn.
 * @custom:member flushIndex Flush index into which withdrawal is included.
 */
struct WithdrawalMetadata {
    uint256 vaultShares;
    uint256 flushIndex;
}

/**
 * @notice Holds all smart vault fee percentages.
 * @custom:member managementFeePct Management fee of the smart vault.
 * @custom:member depositFeePct Deposit fee of the smart vault.
 * @custom:member performanceFeePct Performance fee of the smart vault.
 */
struct SmartVaultFees {
    uint16 managementFeePct;
    uint16 depositFeePct;
    uint16 performanceFeePct;
}

/* ========== INTERFACES ========== */

interface ISmartVault is IERC20Upgradeable, IERC1155Upgradeable {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Fractional balance of a NFT (0 - NFT_MINTED_SHARES)
     */
    function balanceOfFractional(address account, uint256 id) external view returns (uint256);

    /**
     * @notice Fractional balance of a NFT array (0 - NFT_MINTED_SHARES)
     */
    function balanceOfFractionalBatch(address account, uint256[] memory ids) external view returns (uint256[] memory);

    /**
     * @notice Retrieves a list of active NFTs for User.
     */
    function activeUserNFTIds(address userAddress) external view returns (uint256[] memory nftIds);

    /**
     * @return id ID of the asset group.
     */
    function assetGroupId() external view returns (uint256 id);

    /**
     * @return name Name of the vault.
     */
    function vaultName() external view returns (string memory name);

    function getMetadata(uint256[] calldata nftIds) external view returns (bytes[] memory metadata);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Mint ERC20 SVTs for given receiver address
     * @param receiver Address to mint to
     * @param vaultShares Amount of tokens to mint
     */
    function mint(address receiver, uint256 vaultShares) external;

    /**
     * @notice Burn SVTs and release strategy shares back to strategies
     * @param owner Address for which to burn SVTs
     * @param vaultShares Amount of SVTs to burn
     * @param strategies Strategies to which release the shares to
     * @param shares Amount of strategy shares to release
     */
    function burn(address owner, uint256 vaultShares, address[] memory strategies, uint256[] memory shares) external;

    /**
     * @notice Mint a new Withdrawal NFT
     * @dev Supply of minted NFT is NFT_MINTED_SHARES (for partial burning)
     * @param receiver Address that will receive the NFT
     * @param metadata Metadata to store for minted NFT
     */
    function mintWithdrawalNFT(address receiver, WithdrawalMetadata memory metadata)
        external
        returns (uint256 receipt);

    /**
     * @notice Burn NFTs and return their metadata
     * @param owner Owner of NFTs
     * @param nftIds NFTs to burn
     * @param nftAmounts NFT shares to burn (partial burn)
     */
    function burnNFTs(address owner, uint256[] calldata nftIds, uint256[] calldata nftAmounts)
        external
        returns (bytes[] memory metadata);

    /**
     * @notice Mint a new Deposit NFT
     * @dev Supply of minted NFT is NFT_MINTED_SHARES (for partial burning)
     * @param receiver Address that will receive the NFT
     * @param metadata Metadata to store for minted NFT
     */
    function mintDepositNFT(address receiver, DepositMetadata memory metadata) external returns (uint256 receipt);

    /**
     * @notice Transfers smart vault tokens.
     * @dev Requirements:
     * - spender must have approprite allowance set
     * @param from Address from which tokens will be transferred.
     * @param to Address to which tokens will be transferred.
     * @param amount Amount of tokens to transfer.
     * @param spender Executor of transfer.
     */
    function transferFromSpender(address from, address to, uint256 amount, address spender) external returns (bool);

    /**
     * @notice Transfers unclaimed shares to claimer.
     * @dev Requirements:
     * - can only be called from smart vault manager.
     * @param claimer Address that claims the shares.
     * @param amount Amount of shares to transfer.
     */
    function claimShares(address claimer, uint256 amount) external;
}
