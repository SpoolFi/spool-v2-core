// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC1155/IERC1155ReceiverUpgradeable.sol";

import "../external/interfaces/dai/IDAI.sol";

interface IMetaVault is IERC20Upgradeable, IERC1155ReceiverUpgradeable {
    // ========================== ERRORS ==========================

    /**
     * @dev There are no MVTs to claim
     */
    error NothingToClaim();
    /**
     * @dev There are no SVTs to claim for nft id
     */
    error NoDepositNft(uint256 nftId);
    /**
     * @dev User has nothing to withdraw
     */
    error NothingToWithdraw();
    /**
     * @dev There are no withdrawal nfts
     */
    error NothingToFulfill(uint256 nftId);
    /**
     * @dev Total allocation does not sum up to 100 bp
     */
    error WrongAllocation();
    /**
     * @dev Length of arrays is not equal
     */
    error ArgumentLengthMismatch();
    /**
     * @dev Maximum smart vault amount is exceeded
     */
    error MaxSmartVaultAmount();
    /**
     * @dev Flush and reallocation are blocked if there is pending sync
     */
    error PendingSync();
    /**
     * @dev Called method is paused
     */
    error Paused(bytes4 selector);
    /**
     * @dev Flush is blocked until reallocation is not done
     */
    error NeedReallocation();

    // ========================== EVENTS ==========================

    /**
     * @dev User deposited assets into MetaVault
     */
    event Deposit(address indexed user, uint128 indexed flushIndex, uint256 assets);
    /**
     * @dev User claimed MetaVault shares
     */
    event Claim(address indexed user, uint128 indexed flushIndex, uint256 shares);
    /**
     * @dev User redeemed MetaVault shares to get assets back
     */
    event Redeem(address indexed user, uint256 indexed flushIndex, uint256 shares);
    /**
     * @dev User has withdrawn his assets
     */
    event Withdraw(address indexed user, uint256 indexed flushIndex, uint256 assets);
    /**
     * @dev flushDeposit has run
     */
    event FlushDeposit(uint256 indexed flushIndex, uint256 assets);
    /**
     * @dev flushWithdrawal has run
     */
    event FlushWithdrawal(uint256 indexed flushIndex, uint256 shares);
    /**
     * @dev syncDeposit has run
     */
    event SyncDeposit(uint256 indexed flushIndex, uint256 shares);
    /**
     * @dev syncWithdrawal has run
     */
    event SyncWithdrawal(uint256 indexed flushIndex, uint256 assets);
    /**
     * @dev reallocate has run
     */
    event Reallocate(uint256 indexed reallocationIndex);
    /**
     * @dev reallocateSync has run
     */
    event ReallocateSync(uint256 indexed reallocationIndex);
    /**
     * @dev SmartVaults have been changed
     */
    event SmartVaultsChange(address[] vaults);
    /**
     * @dev Allocations have been changed
     */
    event AllocationChange(uint256[] allocations);
    /**
     * @dev Used for parameter gatherer to prepare slippages data
     */
    event SvtToRedeem(address smartVault, uint256 amount);
    /**
     * @dev Emitted when method is paused / unpaused
     */
    event PausedChange(bytes4 selector, bool paused);
    /**
     * @dev Emitted when needReallocation is changed
     */
    event NeedReallocationState(bool state);

    // ========================== FUNCTIONS ==========================

    /**
     * @notice Maximum amount of smart vaults MetaVault can manage
     */
    function MAX_SMART_VAULT_AMOUNT() external view returns (uint256);

    /**
     * @notice Owner of MetaVault can add new smart vaults for management
     * @param vaults list to add
     * @param allocations for all smart vaults
     */
    function addSmartVaults(address[] memory vaults, uint256[] memory allocations) external;

    /**
     * @notice Underlying asset used for investments
     */
    function asset() external view returns (address);

    /**
     * @notice claim MetaVault shares
     * @param flushIndex to claim from
     */
    function claim(uint128 flushIndex) external;

    /**
     * @notice deposit assets into MetaVault
     * @param amount of assets
     */
    function deposit(uint256 amount) external;

    /**
     * @notice deposit assets into MetaVault
     * @param amount of assets
     * @param receiver of future shares
     */
    function deposit(uint256 amount, address receiver) external;

    /**
     * @notice flush deposits and redeems accumulated on MetaVault.
     */
    function flush() external;

    /**
     * @notice total amount of assets deposited by users in particular flush cycle
     */
    function flushToDepositedAssets(uint128) external view returns (uint256);

    /**
     * @notice total amount of shares minted for particular flush cycle
     */
    function flushToMintedShares(uint128) external view returns (uint256);

    /**
     * @notice total amount of shares redeemed by users in particular flush cycle
     */
    function flushToRedeemedShares(uint128) external view returns (uint256);

    /**
     * @notice withdrawal nft id associated with particular smart vault for specific flush index
     */
    function flushToSmartVaultToWithdrawalNftId(uint128, address) external view returns (uint256);

    /**
     * @notice total amount of assets received by MetaVault in particular flush cycle
     */
    function flushToWithdrawnAssets(uint128) external view returns (uint256);

    /**
     * @notice get the balance of underlying asset invested into smart vaults
     * @param vaults addresses
     * @return totalBalance of MetaVault and balances for each particular smart vault
     */
    function getBalances(address[] memory vaults)
        external
        returns (uint256 totalBalance, uint256[][] memory balances);

    /**
     * @notice get the list of smart vaults currently managed by MetaVault
     * @return array of smart vaults
     */
    function getSmartVaults() external view returns (address[] memory);

    /**
     * @notice current flush index. Used to process batch of deposits and redeems
     */
    function index() external view returns (uint128 flush, uint128 sync);

    /**
     * @notice indicates that allocation has changed and there is a need for reallocation
     */
    function needReallocation() external view returns (bool);

    /// @notice if asset supports EIP712
    function permitAsset(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    /// @notice if asset is DAI
    function permitDai(uint256 nonce, uint256 deadline, bool allowed, uint8 v, bytes32 r, bytes32 s) external;

    /**
     * @notice only DoHardWorker can reallocate positions
     * if smartVaultToAllocation is zero all funds are withdrawn from this vault and it is removed from _smartVault.list
     * @param slippages for redeemFast
     */
    function reallocate(uint256[][][] memory slippages) external;

    /**
     * @notice Finalize reallocation of MetaVault
     * revert - DHW should be run
     */
    function reallocateSync() external;

    /**
     * @notice current reallocation index
     */
    function reallocationIndex() external view returns (uint128 flush, uint128 sync);

    /**
     * @notice create a redeem request to get assets back
     * @param shares of MetaVault to burn
     */
    function redeem(uint256 shares) external;

    /**
     * @notice function paused state
     */
    function selectorToPaused(bytes4) external view returns (bool);

    /**
     * @notice selectively pause functions
     */
    function setPaused(bytes4 selector, bool paused) external;

    /**
     * @notice only owner of MetaVault can change the allocations for managed smart vaults
     * @param allocations to set
     */
    function setSmartVaultAllocations(uint256[] memory allocations) external;

    /**
     * @notice allocation is in base points
     */
    function smartVaultToAllocation(address) external view returns (uint256);

    /**
     * @notice deposit nft from regular deposit
     */
    function smartVaultToDepositNftId(address) external view returns (uint256);

    /**
     * @notice deposit nft from reallocation
     */
    function smartVaultToDepositNftIdFromReallocation(address) external view returns (uint256);

    /**
     * @notice flush indexes on SmartVaultManager
     */
    function smartVaultToManagerFlushIndex(address) external view returns (uint256);

    /**
     * @notice sync MetaVault deposits and withdrawals
     */
    function sync() external;

    /**
     * @notice amount of shares user deposited in specific flush index
     */
    function userToFlushToDepositedAssets(address, uint128) external view returns (uint256);

    /**
     * @notice amount of shares user redeemed in specific flush index
     */
    function userToFlushToRedeemedShares(address, uint128) external view returns (uint256);

    /**
     * @notice user can withdraw assets once his request with specific withdrawal index is fulfilled
     * @param flushIndex index
     */
    function withdraw(uint128 flushIndex) external returns (uint256 amount);
}
