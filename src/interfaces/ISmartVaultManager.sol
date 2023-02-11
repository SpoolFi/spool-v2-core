// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "./IDepositManager.sol";
import "./ISmartVault.sol";
import "./ISwapper.sol";
import "./IWithdrawalManager.sol";

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
 * @notice Used when too many strategies were provided during smart vault registration.
 */
error StrategyCapExceeded();

/**
 * @notice Used when user tries to configure a vault with too large management fee.
 */
error ManagementFeeTooLarge(uint256 mgmtFeePct);

/**
 * @notice Used when strategies provided for reallocation are invalid.
 */
error InvalidStrategies();

/**
 * @notice Used when smart vault in reallocation has statically set allocation.
 */
error StaticAllocationSmartVault();

/**
 * @notice Used when user tries to configure a vault with too large deposit fee.
 */
error DepositFeeTooLarge(uint256 depositFeePct);

/**
 * @notice Used when user tries to flush a vault, but DHW indexes overlap with previous flush
 */
error FlushOverlap(address strategy);

/**
 * @notice Used when user tries redeem on behalf of another user, but the vault does not support it
 */
error RedeemForNotAllowed();

/* ========== STRUCTS ========== */

/**
 * @notice Struct holding all data for registration of smart vault.
 * @custom:member assetGroupId Underlying asset group of the smart vault.
 * @custom:member strategies Strategies used by the smart vault.
 * @custom:member strategyAllocation Optional. If empty array, values will be calculated on the spot.
 * @custom:member riskProvider Risk provider used by the smart vault.
 * @custom:member managementFeePct Management fee of the smart vault.
 * @custom:member depositFeePct Deposit fee of the smart vault.
 * @custom:member allocationProvider Allocation provider used by the smart vault.
 * @custom:member riskTolerance Risk appetite of the smart vault.
 */
struct SmartVaultRegistrationForm {
    uint256 assetGroupId;
    address[] strategies;
    uint256[] strategyAllocation;
    address riskProvider;
    address allocationProvider;
    int8 riskTolerance;
    uint16 managementFeePct;
    uint16 depositFeePct;
}

/**
 * @notice Parameters for reallocation.
 * @param smartVaults Smart vaults to reallocate.
 * @param strategies Set of strategies involved in the reallocation.
 * @param swapInfo Information for swapping assets before depositing into the protocol.
 * @param depositSlippages Slippages used to constrain depositing into the protocol.
 * @param withdrawalSlippages Slippages used to contrain withdrawal from the protocol.
 * @param exchangeRateSlippages Slippages used to constratrain exchange rates for asset tokens.
 */
struct ReallocateParamBag {
    address[] smartVaults;
    address[] strategies;
    SwapInfo[][] swapInfo;
    uint256[][] depositSlippages;
    uint256[][] withdrawalSlippages;
    uint256[2][] exchangeRateSlippages;
}

/* ========== INTERFACES ========== */

interface ISmartVaultBalance {
    /**
     * @notice Retrieves an amount of SVT tokens.
     * @param smartVault Smart Vault address.
     * @param user User address.
     * @return balance SVT balance
     */
    function getUserSVTBalance(address smartVault, address user) external view returns (uint256);

    /**
     * @notice Retrieves total supply of SVTs.
     * Includes deposits that were processed by DHW, but still need SVTs to be minted.
     * @param smartVault Smart Vault address.
     * @return totalSupply Simulated total supply
     */
    function getSVTTotalSupply(address smartVault) external view returns (uint256);
}

interface ISmartVaultRegistry {
    function registerSmartVault(address smartVault, SmartVaultRegistrationForm calldata registrationForm) external;
}

interface ISmartVaultManager is ISmartVaultBalance, ISmartVaultRegistry {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function dhwIndexes(address smartVault, uint256 flushIndex) external view returns (uint16a16);

    function getLatestFlushIndex(address smartVault) external view returns (uint256);

    function allocations(address smartVault) external view returns (uint16a16);

    function strategies(address smartVault) external view returns (address[] memory);

    function assetGroupId(address smartVault) external view returns (uint256 assetGroupId_);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function registerSmartVault(address smartVault, SmartVaultRegistrationForm calldata registrationForm) external;

    function flushSmartVault(address smartVault) external;

    /**
     * @notice Reallocates smart vaults.
     * @dev Requirements:
     * - caller must have a ROLE_REALLOCATOR role
     * - smart vaults must be registered
     * - smart vaults must use same asset group
     * - strategies must represent a set of strategies used by smart vaults
     * @param reallocateParams Paramaters for reallocation.
     */
    function reallocate(ReallocateParamBag calldata reallocateParams) external;

    function removeStrategy(address strategy) external;

    /**
     * @notice Syncs smart vault with strategies.
     * @param smartVault Smart vault to sync.
     */
    function syncSmartVault(address smartVault, bool revertOnMissingDHW) external;

    /**
     * @notice Instantly redeems smart vault shares for assets.
     * @param bag Parameters for fast redeemal.
     * @param withdrawalSlippages Slippages guarding redeemal.
     * @param exchangeRateSlippages Slippages used to constrain exchange rates for asset tokens.
     * @return withdrawnAssets Amount of assets withdrawn.
     */
    function redeemFast(
        RedeemBag calldata bag,
        uint256[][] calldata withdrawalSlippages,
        uint256[2][] calldata exchangeRateSlippages
    ) external returns (uint256[] memory withdrawnAssets);

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
     * @notice Initiates a withdrawal process and mints a withdrawal NFT. Once all DHWs are executed, user can
     * use the withdrawal NFT to claim the assets.
     * Optionally, caller can pas a list of deposit NFTs to unwrap.
     * @param bag smart vault address, amount of shares to redeem, nft ids and amounts to burn
     * @param receiver address that will receive the withdrawal NFT
     * @param doFlush optionally flush the smart vault
     */
    function redeem(RedeemBag calldata bag, address receiver, bool doFlush) external returns (uint256 receipt);

    /**
     * @notice Initiates a withdrawal process and mints a withdrawal NFT. Once all DHWs are executed, user can
     * use the withdrawal NFT to claim the assets.
     * Optionally, caller can pas a list of deposit NFTs to unwrap.
     * @param bag smart vault address, amount of shares to redeem, nft ids and amounts to burn
     * @param owner address that owns the shares to be redeemed and will receive the withdrawal NFT
     * @param doFlush optionally flush the smart vault
     */
    function redeemFor(RedeemBag calldata bag, address owner, bool doFlush) external returns (uint256 receipt);

    /**
     * @notice Initiated a deposit and mints a deposit NFT. Once all DHWs are executed, user can
     * unwrap the deposit NDF and claim his SVTs.
     * @param bag smartVault address, assets, NFT receiver address, referral address, doFlush
     */
    function deposit(DepositBag calldata bag) external returns (uint256 receipt);

    /* ========== EVENTS ========== */

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
}
