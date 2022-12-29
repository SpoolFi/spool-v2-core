// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/* ========== ERRORS ========== */

/**
 * @notice Used when trying to claim SVTs for deposit that was not synced yet.
 */
error DepositNotSyncedYet();

/**
 * @notice Used when user has insufficient balance for redeemal of shares.
 */
error InsufficientBalance(uint256 available, uint256 required);

/**
 * @notice Used when deposited assets are not the same length as underlying assets.
 */
error InvalidAssetLengths();

/**
 * @notice Used when there is nothing to flush.
 */
error NothingToFlush();

/**
 * @notice Used when trying to register a smart vault that was already registered.
 */
error SmartVaultAlreadyRegistered();

/**
 * @notice Used when trying to perform an action for smart vault that was not registered yet.
 */
error SmartVaultNotRegisteredYet();

/**
 * @notice Used when no strategy was provided during smart vault registration.
 */
error SmartVaultRegistrationNoStrategies();

/* ========== STRUCTS ========== */

/**
 * @notice Struct holding all data for registration of smart vault.
 * @param assetGroupId Underlying asset group of the smart vault.
 * @param strategies Strategies used by the smart vault.
 * @param riskProvider Risk provider used by the smart vault.
 * @param riskAppetite Risk appetite of the smart vault.
 */
struct SmartVaultRegistrationForm {
    uint256 assetGroupId;
    address[] strategies;
    address riskProvider;
    uint256 riskAppetite;
}

/* ========== INTERFACES ========== */

interface ISmartVaultReallocator {
    function allocations(address smartVault) external view returns (uint256[] memory allocations_);

    function strategies(address smartVault) external view returns (address[] memory);

    function riskTolerance(address smartVault) external view returns (int256 riskTolerance_);

    function riskProvider(address smartVault) external view returns (address riskProviderAddress_);

    function assetGroupId(address smartVault) external view returns (uint256 assetGroupId_);

    function reallocate() external;
}

interface ISmartVaultSyncer {
    /**
     * @notice Syncs smart vault with strategies.
     * @param smartVault Smart vault to sync.
     */
    function syncSmartVault(address smartVault) external;
}

interface ISmartVaultManager is ISmartVaultReallocator, ISmartVaultSyncer {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function dhwIndexes(address smartVault, uint256 flushIndex) external view returns (uint256[] memory);

    function getLatestFlushIndex(address smartVault) external view returns (uint256);

    /**
     * @notice Retrieves an amount of SVT tokens.
     * @param smartVault Smart Vault address.
     * @param user User address.
     * @return depositNTFIds An array of deposit NFT Ids.
     */
    function getUserSVTBalance(address smartVault, address user) external view returns (uint256);
    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function registerSmartVault(address smartVault, SmartVaultRegistrationForm calldata registrationForm) external;

    function flushSmartVault(address smartVault) external;

    function smartVaultDeposits(address smartVault, uint256 flushIdx) external returns (uint256[] memory);

    /**
     * @notice TODO
     * @param assets TODO
     * @param receiver TODO
     * @param depositor TODO
     * @return depositNFTId TODO
     */
    function depositFor(
        address smartVault,
        uint256[] calldata assets,
        address receiver,
        address depositor,
        address referral
    ) external returns (uint256 depositNFTId);

    /**
     * @notice Instantly redeems smart vault shares for assets.
     * @param smartVault Address of the smart vault.
     * @param shares Amount of shares to redeem.
     * @return withdrawnAssets Amount of assets withdrawn.
     */
    function redeemFast(address smartVault, uint256 shares) external returns (uint256[] memory withdrawnAssets);

    /**
     * @notice Claims withdrawal of assets by burning withdrawal NFT.
     * @dev Requirements:
     * - withdrawal NFT must be valid
     * @param smartVault Address of the smart vault that issued the withdrawal NFT.
     * @param nftIDs ID of withdrawal NFT to burn.
     * @param nftAmounts amounts
     * @param receiver Receiver of claimed assets.
     * @return assetAmounts Amounts of assets claimed.
     * @return assetTokens Addresses of assets claimed.
     */
    function claimWithdrawal(
        address smartVault,
        uint256[] calldata nftIDs,
        uint256[] calldata nftAmounts,
        address receiver
    ) external returns (uint256[] memory, uint256);

    /**
     * @notice Claims smart vault tokens by burning the deposit NFT.
     * @dev Requirements:
     * - deposit NFT must be valid
     * - flush must be synced
     * @param smartVaultAddress Address of the smart vault that issued the deposit NFT.
     * @param nftIDs ID of the deposit NFT to burn.
     * @param nftAmounts amounts
     * @return Amount of smart vault tokens claimed.
     */
    function claimSmartVaultTokens(address smartVaultAddress, uint256[] calldata nftIDs, uint256[] calldata nftAmounts)
        external
        returns (uint256);

    /**
     * @dev Burns exactly shares from owner and sends assets of underlying tokens to receiver.
     *
     * - MUST emit the Withdraw event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
     *   redeem execution, and are accounted for during redeem.
     * - MUST revert if all of shares cannot be redeemed (due to withdrawal limit being reached, slippage, the owner
     *   not having enough shares, etc).
     *
     * NOTE: some implementations will require pre-requesting to the Vault before a withdrawal may be performed.
     * Those methods should be performed separately.
     */
    function redeem(address smartVault, uint256 shares, address receiver, address owner)
        external
        returns (uint256 receipt);

    /**
     * @dev Mints shares Vault shares to receiver by depositing exactly amount of underlying tokens.
     *
     * - MUST emit the Deposit event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
     *   deposit execution, and are accounted for during deposit.
     * - MUST revert if all of assets cannot be deposited (due to deposit limit being reached, slippage, the user not
     *   approving enough underlying tokens to the Vault contract, etc).
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault’s underlying asset token.
     */
    function deposit(address smartVault, uint256[] calldata assets, address receiver, address referral)
        external
        returns (uint256 receipt);

    event SmartVaultFlushed(address smartVault, uint256 flushIdx);
}
