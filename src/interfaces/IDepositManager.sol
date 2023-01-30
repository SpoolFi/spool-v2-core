// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "./ISmartVault.sol";

/**
 * @notice Used when deposited assets are not the same length as underlying assets.
 */
error InvalidAssetLengths();

struct DepositBag {
    address smartVault;
    uint256[] assets;
    address receiver;
    address referral;
    bool doFlush;
}

struct DepositExtras {
    address executor;
    address owner;
    address[] tokens;
    address[] strategies;
    uint256[] allocations;
    uint256 flushIndex;
}

interface IDepositManager {
    /**
     * @notice User redeemed deposit NFTs for SVTs
     * @param smartVault Smart vault address
     * @param claimer Claimer address
     * @param claimedVaultTokens Amount of SVTs claimed
     * @param nftIds NFTs to burn
     * @param nftAmounts NFT shares to burn
     */
    event SmartVaultTokensClaimed(
        address indexed smartVault,
        address indexed claimer,
        uint256 claimedVaultTokens,
        uint256[] nftIds,
        uint256[] nftAmounts
    );

    /**
     * @notice A deposit has been initiated
     * @param smartVault Smart vault address
     * @param receiver Beneficiary of the deposit
     * @param depositId Deposit NFT ID for this deposit
     * @param flushIndex Flush index the deposit was scheduled for
     * @param assets Amount of assets to deposit
     * @param executor Address that initiated the deposit
     * @param referral Referral address
     */
    event DepositInitiated(
        address indexed smartVault,
        address indexed receiver,
        uint256 indexed depositId,
        uint256 flushIndex,
        uint256[] assets,
        address executor,
        address referral
    );

    /**
     * @notice Simulate vault synchronization (i.e. DHW was completed, but vault wasn't synced yet)
     * @param smartVault Smart Vault address
     * @param flushIndex vault flush index for which to simulate sync
     * @param strategies strategy addresses
     * @param dhwIndexes dhw indexes for given flushIndex
     * @param assetGroup vault asset group token addresses
     * @return number of SVTs minted and SSTs claimed
     */
    function syncDepositsSimulate(
        address smartVault,
        uint256 flushIndex,
        address[] memory strategies,
        uint256[] memory dhwIndexes,
        address[] memory assetGroup
    ) external view returns (uint256, uint256[] memory);

    /**
     * @notice Synchronize vault deposits for completed DHW runs
     * @param smartVault Smart Vault address
     * @param flushIndex index for which to synchronize deposits for
     * @param strategies vault strategy addresses
     * @param dhwIndexes dhw indexes for given flushIndex
     * @param assetGroup vault asset group token addresses
     */
    function syncDeposits(
        address smartVault,
        uint256 flushIndex,
        address[] memory strategies,
        uint256[] memory dhwIndexes,
        address[] memory assetGroup
    ) external;

    /**
     * @notice Prepare deposits for the next flush cycle
     */
    function depositAssets(DepositBag calldata bag, DepositExtras memory bag2)
        external
        returns (uint256[] memory, uint256);

    /**
     * @notice Mark deposits ready to be processed in the next DHW cycle
     * @param smartVault Smart Vault address
     * @param flushIndex index to flush
     * @param strategies vault strategy addresses
     * @param allocations vault strategy allocations
     * @param tokens vault asset group token addresses
     * @return DHW indexes in which the deposits will be included
     */
    function flushSmartVault(
        address smartVault,
        uint256 flushIndex,
        address[] memory strategies,
        uint256[] memory allocations,
        address[] memory tokens
    ) external returns (uint256[] memory);

    /**
     * @notice Get the number of SVTs that are available, but haven't been claimed yet, for the given NFT
     * @param smartVaultAddress Smart Vault address
     * @param data NFT deposit NFT metadata
     * @param nftShares amount of NFT shares to burn for SVTs
     * @param tokens vault asset group addresses
     * @param strategies vault strategy addresses
     * @param dhwIndexes dhw indexes for given metadata.flushIndex
     * @param allowSyncSimulate allow vault sync simulation, if it hasn't been executed yet
     */
    function getClaimedVaultTokensPreview(
        address smartVaultAddress,
        DepositMetadata memory data,
        uint256 nftShares,
        address[] memory tokens,
        address[] memory strategies,
        uint256[] memory dhwIndexes,
        bool allowSyncSimulate
    ) external view returns (uint256);

    /**
     * @notice Fetch assets deposited in a given vault flush
     */
    function smartVaultDeposits(address smartVault, uint256 flushIdx, uint256 assetGroupLength)
        external
        view
        returns (uint256[] memory);

    /**
     * @notice Claim SVTs by burning deposit NFTs
     * @param smartVault Smart Vault address
     * @param nftIds NFT ids to burn
     * @param nftAmounts NFT amounts to burn (support for partial burn)
     * @param tokens vault asset group token addresses
     * @param executor address executing the claim transaction
     */
    function claimSmartVaultTokens(
        address smartVault,
        uint256[] calldata nftIds,
        uint256[] calldata nftAmounts,
        address[] memory tokens,
        address executor
    ) external returns (uint256);
}
