// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

struct RedeemFastBag {
    address smartVaultAddress;
    uint256 shares;
    uint256[] nftIds;
    uint256[] nftAmounts;
    address[] strategies;
    address[] assetGroup;
    uint256 assetGroupId;
    address executor;
}

struct RedeemBag {
    address smartVaultAddress;
    uint256 vaultShares;
    address executor;
    address receiver;
    address owner;
    uint256[] nftIds;
    uint256[] nftAmounts;
    uint256 flushIndex;
}

struct WithdrawalClaimBag {
    address smartVault;
    uint256[] nftIds;
    uint256[] nftAmounts;
    address receiver;
    address executor;
    uint256 assetGroupId;
    address[] assetGroup;
}

interface IWithdrawalManager {
    /**
     * @notice User redeemed withdrawal NFTs for underlying assets
     * @param smartVault Smart vault address
     * @param claimer Claimer address
     * @param nftIds NFTs to burn
     * @param nftAmounts NFT shares to burn
     * @param withdrawnAssets Amount of underlying assets withdrawn
     */
    event WithdrawalClaimed(
        address indexed smartVault,
        address indexed claimer,
        uint256 assetGroupId,
        uint256[] nftIds,
        uint256[] nftAmounts,
        uint256[] withdrawnAssets
    );

    /**
     * @notice A deposit has been initiated
     * @param smartVault Smart vault address
     * @param owner Owner of shares to be redeemed
     * @param redeemId Withdrawal NFT ID for this redeemal
     * @param flushIndex Flush index the redeem was scheduled for
     * @param shares Amount of vault shares to redeem
     * @param receiver Beneficiary that will be able to claim the underlying assets
     */
    event RedeemInitiated(
        address indexed smartVault,
        address indexed owner,
        uint256 indexed redeemId,
        uint256 flushIndex,
        uint256 shares,
        address receiver
    );

    /**
     * @notice A deposit has been initiated
     * @param smartVault Smart vault address
     * @param redeemer Redeemal initiator and owner of shares
     * @param assetGroupId Asset group ID of the given smart vault
     * @param shares Amount of vault shares to redeem
     * @param nftIds NFTs to burn
     * @param nftAmounts NFT shares to burn
     * @param assetsWithdrawn Amount of underlying assets withdrawn
     */
    event FastRedeemInitiated(
        address indexed smartVault,
        address indexed redeemer,
        uint256 assetGroupId,
        uint256 shares,
        uint256[] nftIds,
        uint256[] nftAmounts,
        uint256[] assetsWithdrawn
    );

    function flushSmartVault(address smartVault, uint256 flushIndex, address[] memory strategies)
        external
        returns (uint256[] memory);

    function claimWithdrawal(
        WithdrawalClaimBag memory bag
    ) external returns (uint256[] memory, uint256);

    function syncWithdrawals(
        address smartVault,
        uint256 flushIndex,
        address[] memory strategies,
        uint256[] memory dhwIndexes_
    ) external;

    function redeem(RedeemBag memory bag) external returns (uint256);

    function redeemFast(RedeemFastBag memory bag) external returns (uint256[] memory);
}
