// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "./ISmartVault.sol";

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
 * @custom:member assetGroupId Underlying asset group of the smart vault.
 * @custom:member strategies Strategies used by the smart vault.
 * @custom:member riskProvider Risk provider used by the smart vault.
 * @custom:member riskAppetite Risk appetite of the smart vault.
 */
struct SmartVaultRegistrationForm {
    uint256 assetGroupId;
    address[] strategies;
    address riskProvider;
    uint256 riskAppetite;
}

struct DepositBag {
    address smartVault;
    address owner;
    address receiver;
    address executor;
    uint256[] assets;
    address[] tokens;
    address[] strategies;
    uint256[] allocations;
    uint256 flushIndex;
    uint256 assetGroupId;
    address referral;
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

interface ISmartVaultBalance {
    /**
     * @notice Retrieves an amount of SVT tokens.
     * @param smartVault Smart Vault address.
     * @param user User address.
     * @return depositNTFIds An array of deposit NFT Ids.
     */
    function getUserSVTBalance(address smartVault, address user) external view returns (uint256);
}

interface ISmartVaultRegistry {
    function registerSmartVault(address smartVault, SmartVaultRegistrationForm calldata registrationForm) external;
}

interface IDepositManager {
    /**
     * @notice A deposit has been initiated
     * @param smartVault Smart vault address
     * @param receiver Beneficiary of the deposit
     * @param depositId Deposit NFT ID for this deposit
     * @param flushIndex Flush index the deposit was scheduled for
     * @param assetGroupId Asset group ID of the given smart vault
     * @param assets Amount of assets to deposit
     * @param executor Address that initiated the deposit
     * @param referral Referral address
     */
    event DepositInitiated(
        address indexed smartVault,
        address indexed receiver,
        uint256 indexed depositId,
        uint256 flushIndex,
        uint256 assetGroupId,
        uint256[] assets,
        address executor,
        address referral
    );

    function depositAssets(DepositBag memory bag) external returns (uint256);

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
}

interface ISmartVaultManager is ISmartVaultReallocator, ISmartVaultBalance, ISmartVaultRegistry {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function dhwIndexes(address smartVault, uint256 flushIndex) external view returns (uint256[] memory);

    function getLatestFlushIndex(address smartVault) external view returns (uint256);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function registerSmartVault(address smartVault, SmartVaultRegistrationForm calldata registrationForm) external;

    function flushSmartVault(address smartVault) external;

    function smartVaultDeposits(address smartVault, uint256 flushIdx) external returns (uint256[] memory);

    /**
     * @notice Syncs smart vault with strategies.
     * @param smartVault Smart vault to sync.
     */
    function syncSmartVault(address smartVault) external;

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
    function redeemFast(address smartVault, uint256 shares, uint256[] calldata nftIds, uint256[] calldata nftAmounts)
        external
        returns (uint256[] memory withdrawnAssets);

    /**
     * @notice Claims withdrawal of assets by burning withdrawal NFT.
     * @dev Requirements:
     * - withdrawal NFT must be valid
     * @param smartVault Address of the smart vault that issued the withdrawal NFT.
     * @param nftIds ID of withdrawal NFT to burn.
     * @param nftAmounts amounts
     * @param receiver Receiver of claimed assets.
     * @return assetAmounts Amounts of assets claimed.
     * @return assetGroupId ID of the asset group.
     */
    function claimWithdrawal(
        address smartVault,
        uint256[] calldata nftIds,
        uint256[] calldata nftAmounts,
        address receiver
    ) external returns (uint256[] memory assetAmounts, uint256 assetGroupId);

    /**
     * @notice Claims smart vault tokens by burning the deposit NFT.
     * @dev Requirements:
     * - deposit NFT must be valid
     * - flush must be synced
     * @param smartVaultAddress Address of the smart vault that issued the deposit NFT.
     * @param nftIds ID of the deposit NFT to burn.
     * @param nftAmounts amounts
     * @return claimedAmount Amount of smart vault tokens claimed.
     */
    function claimSmartVaultTokens(address smartVaultAddress, uint256[] calldata nftIds, uint256[] calldata nftAmounts)
        external
        returns (uint256 claimedAmount);

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
    function redeem(
        address smartVault,
        uint256 shares,
        address receiver,
        address owner,
        uint256[] calldata nftIds,
        uint256[] calldata nftAmounts
    ) external returns (uint256 receipt);

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

    /* ========== EVENTS ========== */

    /**
     * @notice Smart vault risk provider set
     * @param smartVault Smart vault address
     * @param riskProvider_ New risk provider address
     */
    event RiskProviderSet(address indexed smartVault, address indexed riskProvider_);

    /**
     * @notice Smart vault has been flushed
     * @param smartVault Smart vault address
     * @param flushIndex Flush index
     */
    event SmartVaultFlushed(address indexed smartVault, uint256 flushIndex);

    /**
     * @notice Smart vault has been synced
     * @param smartVault Smart vault address
     * @param flushIndex Flush index
     */
    event SmartVaultSynced(address indexed smartVault, uint256 flushIndex);

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
}
