// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "./ISmartVault.sol";

/**
 * @notice Used when deposited assets are not the same length as underlying assets.
 */
error InvalidAssetLengths();

struct Deposit {
    address smartVault;
    uint256[] assets;
    address receiver;
    address referral;
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

    function depositAssets(Deposit calldata bag, DepositExtras memory bag2) external returns (uint256[] memory, uint256);

    function syncDeposits(
        address smartVault,
        uint256 flushIndex,
        address[] memory strategies_,
        uint256[] memory dhwIndexes_,
        address[] memory assetGroup
    ) external;

    function flushSmartVault(
        address smartVault,
        uint256 flushIndex,
        address[] memory strategies_,
        uint256[] memory allocation,
        address[] memory tokens
    ) external returns (uint256[] memory);

    function getClaimedVaultTokensPreview(
        address smartVaultAddress,
        DepositMetadata memory data,
        uint256 nftShares,
        address[] memory assets
    ) external view returns (uint256);

    function smartVaultDeposits(address smartVault, uint256 flushIdx, uint256 assetGroupLength)
        external
        view
        returns (uint256[] memory);

    function claimSmartVaultTokens(
        address smartVault,
        uint256[] calldata nftIds,
        uint256[] calldata nftAmounts,
        address[] memory tokens,
        address executor
    ) external returns (uint256);
}
