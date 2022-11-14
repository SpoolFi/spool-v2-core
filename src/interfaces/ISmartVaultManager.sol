// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

/* ========== ERRORS ========== */

error InvalidAssetLengths();
error InvalidArrayLength();
error InvalidDepositAmount(address smartVault);
error IncorrectDepositRatio();
error InsufficientBalance(uint256 available, uint256 required);

/**
 * @notice Used when trying to claim SVTs for deposit that was not synced yet.
 */
error DepositNotSyncedYet();

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

/**
 * @notice Used when length of allocation does not match length of strategies provided during smart vault registration.
 */
error SmartVaultRegistrationIncorrectAllocationLength();

/**
 * @notice Used when provided allocation for a strategy is zero during smart vault registration.
 */
error SmartVaultRegistrationZeroAllocation();

/* ========== STRUCTS ========== */

/**
 * @notice Struct holding all data for registration of smart vault.
 *
 */
struct SmartVaultRegistrationForm {
    uint256 assetGroupId;
    address[] strategies;
    uint256[] strategyAllocations;
    address riskProvider;
}

struct SwapInfo {
    address swapTarget;
    address token;
    uint256 amountIn;
    bytes swapCallData;
}

struct DepositBag {
    address[] tokens;
    address[] strategies;
    uint256[] depositsIn;
    uint256[] decimals;
    uint256[] exchangeRates;
    uint256[][] depositRatios;
    uint256 depositUSD;
    uint256 usdDecimals;
    address masterWallet;
    address swapper;
}

struct DepositRatioQueryBag {
    address smartVault;
    address[] tokens;
    address[] strategies;
    uint256[] allocations;
    uint256[] exchangeRates;
    uint256[][] strategyRatios;
    uint256 usdDecimals;
    address masterWallet;
    address swapper;
}

/* ========== INTERFACES ========== */

interface ISmartVaultReallocator {
    function allocations(address smartVault) external view returns (uint256[] memory allocations);

    function strategies(address smartVault) external view returns (address[] memory);

    function riskTolerance(address smartVault) external view returns (int256 riskTolerance);

    function riskProvider(address smartVault) external view returns (address riskProviderAddress);

    function assetGroupId(address smartVault) external view returns (uint256 assetGroupId);

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

    function getDepositRatio(address smartVault) external view returns (uint256[] memory);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function registerSmartVault(address smartVault, SmartVaultRegistrationForm calldata registrationForm) external;

    function flushSmartVault(address smartVault, SwapInfo[] calldata swapInfo) external;

    function smartVaultDeposits(address smartVault, uint256 flushIdx) external returns (uint256[] memory);

    /**
     * @notice TODO
     * @param assets TODO
     * @param receiver TODO
     * @param depositor TODO
     * @return depositNFTId TODO
     */
    function depositFor(address smartVault, uint256[] calldata assets, address receiver, address depositor)
        external
        returns (uint256 depositNFTId);

    /**
     * @notice TODO
     * @param assets TODO
     * @param receiver TODO
     * @param slippages TODO
     * @return receipt TODO
     */
    function depositFast(
        address smartVault,
        uint256[] calldata assets,
        address receiver,
        uint256[][] calldata slippages
    ) external returns (uint256 receipt);

    /**
     * @notice Used to withdraw underlying asset.
     * @param shares TODO
     * @param receiver TODO
     * @param owner TODO
     * @param slippages TODO
     * @param owner TODO
     * @return returnedAssets  TODO
     */
    function redeemFast(
        address smartVault,
        uint256 shares,
        address receiver,
        uint256[][] calldata slippages,
        address owner
    ) external returns (uint256[] memory returnedAssets);

    /**
     * @notice Claims withdrawal of assets by burning withdrawal NFT.
     * @dev Requirements:
     * - withdrawal NFT must be valid
     * @param smartVault Address of the smart vault that issued the withdrawal NFT.
     * @param withdrawalNftId ID of withdrawal NFT to burn.
     * @param receiver Receiver of claimed assets.
     * @return assetAmounts Amounts of assets claimed.
     * @return assetTokens Addresses of assets claimed.
     */
    function claimWithdrawal(address smartVault, uint256 withdrawalNftId, address receiver)
        external
        returns (uint256[] memory, uint256);

    /**
     * @notice Claims smart vault tokens by burning the deposit NFT.
     * @dev Requirements:
     * - deposit NFT must be valid
     * - flush must be synced
     * @param smartVaultAddress Address of the smart vault that issued the deposit NFT.
     * @param depositNftId ID of the deposit NFT to burn.
     * @return Amount of smart vault tokens claimed.
     */
    function claimSmartVaultTokens(address smartVaultAddress, uint256 depositNftId) external returns (uint256);

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
    function deposit(address smartVault, uint256[] calldata assets, address receiver)
        external
        returns (uint256 receipt);

    event SmartVaultFlushed(address smartVault, uint256 flushIdx);
}
