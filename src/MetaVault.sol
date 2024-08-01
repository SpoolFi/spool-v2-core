/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC1155/utils/ERC1155ReceiverUpgradeable.sol";
import "@openzeppelin-upgradeable/utils/MulticallUpgradeable.sol";

import "./access/SpoolAccessControllable.sol";
import "./libraries/ListMap.sol";
import "./interfaces/ISmartVaultManager.sol";
import "./interfaces/IMetaVaultGuard.sol";
import "./interfaces/ISpoolLens.sol";
import "./external/interfaces/dai/IDAI.sol";
import "./external/interfaces/permit2/IPermit2.sol";

/**
 * @dev MetaVault is a contract which facilitates investment in various SmartVaults.
 * It has an owner, which is responsible for managing smart vaults allocations.
 * In this way MetaVault owner can manage funds from users in trustless manner.
 * MetaVault supports only one ERC-20 asset.
 * Users can deposit funds and in return they get MetaVault shares.
 * To redeem users are required to burn they MetaVault shares, while creating redeem request,
 * which is processed in asynchronous manner.
 */
contract MetaVault is
    Ownable2StepUpgradeable,
    ERC20Upgradeable,
    ERC1155ReceiverUpgradeable,
    MulticallUpgradeable,
    SpoolAccessControllable
{
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
    using ListMap for ListMap.Address;

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

    // ========================== IMMUTABLES ==========================

    /**
     * @dev Maximum amount of smart vaults MetaVault can manage
     */
    uint256 public constant MAX_SMART_VAULT_AMOUNT = 8;
    /**
     * @dev SmartVaultManager contract. Gateway to Spool protocol
     */
    ISmartVaultManager internal immutable smartVaultManager;
    /**
     * @dev MetaVaultGuard contract
     */
    IMetaVaultGuard internal immutable metaVaultGuard;
    /**
     * @dev SpoolLens contract
     */
    ISpoolLens internal immutable spoolLens;

    // ========================== STATE ==========================

    /**
     * @dev Underlying asset used for investments
     */
    address public asset;
    /**
     * @dev decimals of shares to match those in asset
     */
    uint8 private _decimals;

    /**
     * @dev list of managed SmartVaults
     */
    ListMap.Address internal _smartVaults;
    /**
     * @dev deposit nft from regular deposit
     */
    mapping(address => uint256) public smartVaultToDepositNftId;
    /**
     * @dev deposit nft from reallocation
     */
    mapping(address => uint256) public smartVaultToDepositNftIdFromReallocation;
    /**
     * @dev allocation is in base points
     */
    mapping(address => uint256) public smartVaultToAllocation;
    /**
     * @dev flush indexes on SmartVaultManager
     */
    mapping(address => uint256) public smartVaultToManagerFlushIndex;

    /**
     * @dev both start with zero.
     * if sync == flush it means whole cycle is completed
     * if flush > sync - there is pending sync
     */
    struct Index {
        uint128 flush;
        uint128 sync;
    }

    /**
     * @dev current flush index. Used to process batch of deposits and redeems
     */
    Index public index;
    /**
     * @dev current reallocation index
     */
    Index public reallocationIndex;
    /**
     * @dev total amount of assets deposited by users in particular flush cycle
     */
    mapping(uint128 => uint256) public flushToDepositedAssets;
    /**
     * @dev total amount of shares minted for particular flush cycle
     */
    mapping(uint128 => uint256) public flushToMintedShares;
    /**
     * @dev total amount of shares redeemed by users in particular flush cycle
     */
    mapping(uint128 => uint256) public flushToRedeemedShares;
    /**
     * @dev total amount of assets received by MetaVault in particular flush cycle
     */
    mapping(uint128 => uint256) public flushToWithdrawnAssets;
    /**
     * @dev withdrawal nft id associated with particular smart vault for specific flush index
     */
    mapping(uint128 => mapping(address => uint256)) public flushToSmartVaultToWithdrawalNftId;
    /**
     * @dev amount of shares user deposited in specific flush index
     */
    mapping(address => mapping(uint128 => uint256)) public userToFlushToDepositedAssets;
    /**
     * @dev amount of shares user redeemed in specific flush index
     */
    mapping(address => mapping(uint128 => uint256)) public userToFlushToRedeemedShares;
    /**
     * @dev selectively pause functions
     */
    mapping(bytes4 => bool) public selectorToPaused;
    /**
     * @dev indicates that allocation has changed and there is a need for reallocation
     */
    bool public needReallocation;

    // ========================== CONSTRUCTOR ==========================

    constructor(
        ISmartVaultManager smartVaultManager_,
        ISpoolAccessControl spoolAccessControl_,
        IMetaVaultGuard metaVaultGuard_,
        ISpoolLens spoolLens_
    ) SpoolAccessControllable(spoolAccessControl_) {
        if (
            address(smartVaultManager_) == address(0) || address(metaVaultGuard_) == address(0)
                || address(spoolLens_) == address(0)
        ) revert ConfigurationAddressZero();
        smartVaultManager = smartVaultManager_;
        metaVaultGuard = metaVaultGuard_;
        spoolLens = spoolLens_;
    }

    // ========================== INITIALIZER ==========================

    function initialize(
        address owner,
        address asset_,
        string memory name_,
        string memory symbol_,
        address[] calldata vaults,
        uint256[] calldata allocations
    ) external initializer {
        __Multicall_init();
        __ERC20_init(name_, symbol_);
        asset = asset_;
        _decimals = uint8(IERC20MetadataUpgradeable(asset).decimals());
        _addSmartVaults(vaults, allocations, true);
        IERC20MetadataUpgradeable(asset).approve(address(smartVaultManager), type(uint256).max);
        _transferOwnership(owner);
    }

    // ==================== PAUSING ====================

    function setPaused(bytes4 selector, bool paused) external {
        if (paused) {
            _checkRole(ROLE_PAUSER, msg.sender);
        } else {
            _checkRole(ROLE_UNPAUSER, msg.sender);
        }
        selectorToPaused[selector] = paused;
        emit PausedChange(selector, paused);
    }

    /**
     * @dev checks that called method is not paused
     */
    function _checkNotPaused() internal view {
        if (selectorToPaused[msg.sig]) revert Paused(msg.sig);
    }

    // ==================== SMART VAULTS MANAGEMENT ====================

    /**
     * @dev get the list of smart vaults currently managed by MetaVault
     * @return array of smart vaults
     */
    function getSmartVaults() external view returns (address[] memory) {
        return _smartVaults.list;
    }

    /**
     * @dev Owner of MetaVault can add new smart vaults for management
     * @param vaults list to add
     * @param allocations for all smart vaults
     */
    function addSmartVaults(address[] calldata vaults, uint256[] calldata allocations) external onlyOwner {
        _checkNotPaused();
        _addSmartVaults(vaults, allocations, false);
    }

    /**
     * @param vaults list to add
     * @param allocations for all smart vaults
     */
    function _addSmartVaults(address[] calldata vaults, uint256[] calldata allocations, bool initialization) internal {
        if (vaults.length > 0) {
            /// if there is pending sync adding smart vaults is prohibited
            if (_smartVaults.list.length + vaults.length > MAX_SMART_VAULT_AMOUNT) revert MaxSmartVaultAmount();
            metaVaultGuard.validateSmartVaults(asset, vaults);
            _smartVaults.addList(vaults);
            emit SmartVaultsChange(_smartVaults.list);
            _setSmartVaultAllocations(allocations, initialization);
        }
    }

    /**
     * @dev only owner of MetaVault can change the allocations for managed smart vaults
     * @param allocations to set
     */
    function setSmartVaultAllocations(uint256[] calldata allocations) external onlyOwner {
        _checkNotPaused();
        _setSmartVaultAllocations(allocations, false);
    }

    /**
     * @dev set allocations for managed smart vaults
     * @param allocations to set
     */
    function _setSmartVaultAllocations(uint256[] calldata allocations, bool initialization) internal {
        address[] memory vaults = _smartVaults.list;
        if (allocations.length != vaults.length) revert ArgumentLengthMismatch();
        uint256 sum;
        for (uint256 i; i < vaults.length; i++) {
            sum += allocations[i];
            smartVaultToAllocation[vaults[i]] = allocations[i];
        }
        if (sum != 100_00) revert WrongAllocation();
        emit AllocationChange(allocations);
        if (!initialization) {
            needReallocation = true;
        }
    }

    // ========================== USER FACING ==========================

    /**
     * @dev deposit assets into MetaVault
     * @param amount of assets
     */
    function deposit(uint256 amount) external {
        _checkNotPaused();
        uint128 flushIndex = index.flush;
        /// MetaVault has now more funds to manage
        flushToDepositedAssets[flushIndex] += amount;
        userToFlushToDepositedAssets[msg.sender][flushIndex] += amount;
        IERC20MetadataUpgradeable(asset).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, flushIndex, amount);
    }

    /**
     * @dev claim MetaVault shares
     * @param flushIndex to claim from
     */
    function claim(uint128 flushIndex) external {
        _checkNotPaused();
        uint256 userAssets = userToFlushToDepositedAssets[msg.sender][flushIndex];
        if (index.sync < flushIndex || userAssets == 0) revert NothingToClaim();
        uint256 shares = flushToMintedShares[flushIndex] * userAssets / flushToDepositedAssets[flushIndex];
        delete userToFlushToDepositedAssets[msg.sender][flushIndex];
        _transfer(address(this), msg.sender, shares);
        emit Claim(msg.sender, flushIndex, shares);
    }

    /**
     * @dev create a redeem request to get assets back
     * @param shares of MetaVault to burn
     */
    function redeem(uint256 shares) external {
        _checkNotPaused();
        _burn(msg.sender, shares);
        uint128 flushIndex = index.flush;
        /// accumulate redeems for all users for current flush index
        flushToRedeemedShares[flushIndex] += shares;
        /// accumulate redeems for particular user for current flush index
        userToFlushToRedeemedShares[msg.sender][flushIndex] += shares;
        emit Redeem(msg.sender, flushIndex, shares);
    }

    /**
     * @dev user can withdraw assets once his request with specific withdrawal index is fulfilled
     * @param flushIndex index
     */
    function withdraw(uint128 flushIndex) external returns (uint256 amount) {
        _checkNotPaused();
        uint256 shares = userToFlushToRedeemedShares[msg.sender][flushIndex];
        /// user can withdraw funds only for synced flush
        if (index.sync < flushIndex || shares == 0) revert NothingToWithdraw();
        /// amount of funds user get from specified withdrawal index
        amount = shares * flushToWithdrawnAssets[flushIndex] / flushToRedeemedShares[flushIndex];
        /// delete entry for user to disable repeated withdrawal
        delete userToFlushToRedeemedShares[msg.sender][flushIndex];
        IERC20MetadataUpgradeable(asset).safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, flushIndex, amount);
    }

    // ========================== SPOOL INTERACTIONS ==========================

    /**
     * @dev check that regular flush and reallocation are synced
     */
    function _checkPendingSync() internal view {
        if (index.sync < index.flush || reallocationIndex.sync < reallocationIndex.flush) revert PendingSync();
    }

    /**
     * @dev check the caller if it is not estimation transaction
     */
    function _checkOperator() internal view {
        if (tx.origin != address(0)) _checkRole(ROLE_DO_HARD_WORKER, msg.sender);
    }

    /**
     * @dev flush deposits and redeems accumulated on MetaVault.
     */
    function flush() external {
        _checkNotPaused();
        _checkOperator();
        _checkPendingSync();
        if (needReallocation) revert NeedReallocation();

        address[] memory vaults = _smartVaults.list;
        if (vaults.length > 0) {
            uint128 flushIndex = index.flush;
            // we process withdrawal first to ensure all SVTs are collected
            bool withdrawalHadEffect = _flushWithdrawal(vaults, flushIndex);
            bool depositHadEffect = _flushDeposit(vaults, flushIndex);
            if (withdrawalHadEffect || depositHadEffect) {
                index.flush++;
            }
        }
    }

    /**
     * @dev Deposits into all managed smart vaults based on allocation.
     * On deposits MetaVault receives deposit nfts.
     * @param vaults to flush
     * @return hadEffect bool indicating whether flush had some effect
     */
    function _flushDeposit(address[] memory vaults, uint128 flushIndex) internal returns (bool hadEffect) {
        uint256 assets = flushToDepositedAssets[flushIndex];
        if (assets > 0) {
            for (uint256 i; i < vaults.length; i++) {
                uint256 amount = assets * smartVaultToAllocation[vaults[i]] / 100_00;
                if (amount > 0) {
                    smartVaultToDepositNftId[vaults[i]] = _spoolDeposit(vaults[i], amount);
                    smartVaultToManagerFlushIndex[vaults[i]] = smartVaultManager.getLatestFlushIndex(vaults[i]);
                    hadEffect = true;
                }
            }
            emit FlushDeposit(index.flush, assets);
        }
    }

    /**
     * @dev Redeem all shares from last non-initiated unfulfilled withdrawal index.
     * On redeems MetaVault burns deposit nfts for SVTs and burns SVTs for redeem on Spool.
     * @param vaults to flush
     * @return hadEffect bool indicating whether flush had some effect
     * reverts if not all deposit nfts are claimed/claimable => DHW is needed
     */
    function _flushWithdrawal(address[] memory vaults, uint128 flushIndex) internal returns (bool hadEffect) {
        uint256 shares = flushToRedeemedShares[flushIndex];
        if (shares > 0) {
            uint256 _totalSupply = totalSupply() + shares;
            for (uint256 i; i < vaults.length; i++) {
                uint256 SVTToRedeem = ISmartVault(vaults[i]).balanceOf(address(this)) * shares / _totalSupply;
                if (SVTToRedeem > 0) {
                    flushToSmartVaultToWithdrawalNftId[flushIndex][vaults[i]] = smartVaultManager.redeem(
                        RedeemBag({
                            smartVault: vaults[i],
                            shares: SVTToRedeem,
                            nftIds: new uint256[](0),
                            nftAmounts: new uint256[](0)
                        }),
                        address(this),
                        false
                    );
                    smartVaultToManagerFlushIndex[vaults[i]] = smartVaultManager.getLatestFlushIndex(vaults[i]);
                    hadEffect = true;
                }
            }
            emit FlushWithdrawal(flushIndex, shares);
        }
    }

    /**
     * @dev sync MetaVault deposits and withdrawals
     */
    function sync() external {
        _checkNotPaused();
        _checkOperator();
        address[] memory vaults = _smartVaults.list;
        Index memory index_ = index;
        if (vaults.length > 0 && index_.sync < index_.flush) {
            bool depositHadEffect = _syncDeposit(vaults, index_.sync);
            bool withdrawalHadEffect = _syncWithdrawal(vaults, index_.sync);
            if (depositHadEffect || withdrawalHadEffect) {
                index.sync++;
            }
        }
    }

    /**
     * @dev Claims all SVTs by burning deposit nfts
     * @param vaults to sync
     * @return hadEffect bool indicating whether sync had some effect
     * reverts if not all deposit nfts are claimed/claimable => DHW is needed
     */
    function _syncDeposit(address[] memory vaults, uint128 syncIndex) internal returns (bool hadEffect) {
        uint256 depositedAssets = flushToDepositedAssets[syncIndex];
        if (depositedAssets > 0) {
            for (uint256 i; i < vaults.length; i++) {
                uint256[] memory depositNfts = new uint256[](1);
                depositNfts[0] = smartVaultToDepositNftId[vaults[i]];
                if (depositNfts[0] > 0) {
                    uint256[] memory nftAmounts = new uint256[](1);
                    nftAmounts[0] = ISmartVault(vaults[i]).balanceOfFractional(address(this), depositNfts[0]);
                    // make sure there is actual balance for given nft id
                    if (nftAmounts[0] == 0) revert NoDepositNft(depositNfts[0]);
                    smartVaultManager.claimSmartVaultTokens(vaults[i], depositNfts, nftAmounts);
                    delete smartVaultToDepositNftId[vaults[i]];
                    hadEffect = true;
                }
            }
            if (hadEffect) {
                (uint256 totalBalance,) = getBalances(vaults);
                uint256 totalSupply_ = totalSupply();
                uint256 toMint = totalSupply_ == 0
                    ? depositedAssets
                    : (totalSupply_ * depositedAssets) / (totalBalance - depositedAssets);
                flushToMintedShares[syncIndex] = toMint;
                _mint(address(this), toMint);
                emit SyncDeposit(syncIndex, toMint);
            }
        }
    }

    /**
     * @dev Claim all withdrawals by burning withdrawal nfts
     * @param vaults to sync
     * @return hadEffect bool indicating whether sync had some effect
     * reverts if not all withdrawal nfts are claimable => DHW is needed
     */
    function _syncWithdrawal(address[] memory vaults, uint128 syncIndex) internal returns (bool hadEffect) {
        if (flushToRedeemedShares[syncIndex] > 0) {
            /// aggregate withdrawn assets from all smart vaults
            uint256 withdrawnAssets;
            for (uint256 i; i < vaults.length; i++) {
                uint256 nftId = flushToSmartVaultToWithdrawalNftId[syncIndex][vaults[i]];
                if (nftId > 0) {
                    withdrawnAssets += _spoolClaimWithdrawal(vaults[i], nftId);
                    delete flushToSmartVaultToWithdrawalNftId[syncIndex][vaults[i]];
                    hadEffect = true;
                }
            }
            if (hadEffect) {
                /// we fulfill last unprocessed withdrawal index
                flushToWithdrawnAssets[syncIndex] = withdrawnAssets;
                emit SyncWithdrawal(syncIndex, withdrawnAssets);
            }
        }
    }

    /**
     * @dev getTotalBalance
     * @param vaults addresses
     * @return totalBalance of MetaVault and balances for each particular smart vault
     */
    function getBalances(address[] memory vaults) public returns (uint256 totalBalance, uint256[][] memory balances) {
        balances = spoolLens.getUserVaultAssetBalances(
            address(this), vaults, new uint256[][](vaults.length), new bool[](vaults.length)
        );
        for (uint256 i; i < balances.length; i++) {
            totalBalance += balances[i][0];
        }
        return (totalBalance, balances);
    }

    struct ReallocationVars {
        /// total amount of assets withdrawn during the reallocation
        uint256 withdrawnAssets;
        /// total equivalent of MetaVault shares for position change
        uint256 positionChangeTotal;
        /// amount of vaults to remove
        uint256 vaultsToRemoveCount;
        /// index for populating list of vaults for removal
        uint256 vaultToRemoveIndex;
        /// flag to check whether it is a estimation transaction to get svts amount
        bool isViewExecution;
    }

    /**
     * @dev only DoHardWorker can reallocate positions
     * if smartVaultToAllocation is zero all funds are withdrawn from this vault and it is removed from _smartVault.list
     * @param slippages for redeemFast
     */
    function reallocate(uint256[][][] calldata slippages) external {
        _checkNotPaused();
        _checkOperator();
        _checkPendingSync();
        ReallocationVars memory vars = ReallocationVars(0, 0, 0, 0, tx.origin == address(0));
        /// cache
        address[] memory vaults = _smartVaults.list;
        /// track required adjustment for vaults positions
        /// uint256 max means vault should be removed
        uint256[] memory positionToAdd = new uint256[](vaults.length);
        (uint256 totalBalance, uint256[][] memory balances) = getBalances(vaults);
        if (totalBalance > 0) {
            for (uint256 i; i < vaults.length; i++) {
                uint256 currentPosition = balances[i][0];
                uint256 desiredPosition = smartVaultToAllocation[vaults[i]] * totalBalance / 100_00;
                /// if more MetaVault shares should be deposited we save this data for later
                if (desiredPosition > currentPosition) {
                    uint256 positionDiff = desiredPosition - currentPosition;
                    positionToAdd[i] = positionDiff;
                    vars.positionChangeTotal += positionDiff;
                    // if amount of MetaVault shares should be reduced we perform redeemFast
                } else if (desiredPosition < currentPosition) {
                    uint256 positionDiff = currentPosition - desiredPosition;
                    /// previously all SVTs shares were claimed,
                    /// so we can calculate the proportion of SVTs to be withdrawn using MetaVault deposited shares ratio
                    uint256 svtsToRedeem =
                        positionDiff * ISmartVault(vaults[i]).balanceOf(address(this)) / currentPosition;
                    if (vars.isViewExecution) {
                        emit SvtToRedeem(vaults[i], svtsToRedeem);
                        continue;
                    }
                    vars.withdrawnAssets += smartVaultManager.redeemFast(
                        RedeemBag({
                            smartVault: vaults[i],
                            shares: svtsToRedeem,
                            nftIds: new uint256[](0),
                            nftAmounts: new uint256[](0)
                        }),
                        slippages[i]
                    )[0];
                    // means we need to remove vault
                    if (desiredPosition == 0) {
                        positionToAdd[i] = type(uint256).max;
                        vars.vaultsToRemoveCount++;
                    }
                }
            }
            if (vars.isViewExecution) {
                return;
            }

            /// now we will perform deposits and vaults removal
            if (vars.withdrawnAssets > 0) {
                address[] memory vaultsToRemove = new address[](vars.vaultsToRemoveCount);
                for (uint256 i; i < vaults.length; i++) {
                    if (positionToAdd[i] == type(uint256).max) {
                        vaultsToRemove[vars.vaultToRemoveIndex] = vaults[i];
                        vars.vaultToRemoveIndex++;
                        /// only if there are "MetaVault shares to deposit"
                    } else if (positionToAdd[i] > 0) {
                        /// calculate amount of assets based on MetaVault shares ratio
                        uint256 amount = positionToAdd[i] * vars.withdrawnAssets / vars.positionChangeTotal;
                        smartVaultToDepositNftIdFromReallocation[vaults[i]] = _spoolDeposit(vaults[i], amount);
                        smartVaultToManagerFlushIndex[vaults[i]] = smartVaultManager.getLatestFlushIndex(vaults[i]);
                    }
                }
                emit Reallocate(reallocationIndex.flush);
                reallocationIndex.flush++;
                /// remove smart vault from managed list on reallocation
                if (vaultsToRemove.length > 0) {
                    _smartVaults.removeList(vaultsToRemove);
                    emit SmartVaultsChange(_smartVaults.list);
                }
            }
        }
        needReallocation = false;
    }

    /**
     * @dev Finalize reallocation of MetaVault
     * revert - DHW should be run
     */
    function reallocateSync() external {
        _checkNotPaused();
        _checkOperator();
        if (reallocationIndex.flush == reallocationIndex.sync) return;
        bool hadEffect;
        /// cache
        address[] memory vaults = _smartVaults.list;
        for (uint256 i; i < vaults.length; i++) {
            uint256[] memory depositNftIds = new uint256[](1);
            depositNftIds[0] = smartVaultToDepositNftIdFromReallocation[vaults[i]];
            if (depositNftIds[0] > 0) {
                uint256[] memory nftAmounts = new uint256[](1);
                nftAmounts[0] = ISmartVault(vaults[i]).balanceOfFractional(address(this), depositNftIds[0]);
                smartVaultManager.claimSmartVaultTokens(vaults[i], depositNftIds, nftAmounts);
                hadEffect = true;
                delete smartVaultToDepositNftIdFromReallocation[vaults[i]];
            }
        }
        if (hadEffect) {
            emit ReallocateSync(reallocationIndex.sync);
            reallocationIndex.sync++;
        }
    }

    /**
     * @dev deposit into spool
     * @param vault address
     * @param amount to deposit
     * @return nftId of deposit
     */
    function _spoolDeposit(address vault, uint256 amount) internal returns (uint256 nftId) {
        uint256[] memory assets = new uint256[](1);
        assets[0] = amount;
        nftId = smartVaultManager.deposit(
            DepositBag({
                smartVault: vault,
                assets: assets,
                receiver: address(this),
                doFlush: false,
                referral: address(0)
            })
        );
    }

    /**
     * @dev claim withdrawal from Spool
     * @param vault address
     * @param nftId of withdrawal
     * @return amount of assets withdrawn
     */
    function _spoolClaimWithdrawal(address vault, uint256 nftId) internal returns (uint256) {
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = nftId;
        uint256[] memory nftAmounts = new uint256[](1);
        nftAmounts[0] = ISmartVault(vault).balanceOfFractional(address(this), nftIds[0]);
        if (nftAmounts[0] == 0) revert NothingToFulfill(nftIds[0]);
        (uint256[] memory withdrawn,) = smartVaultManager.claimWithdrawal(vault, nftIds, nftAmounts, address(this));
        return withdrawn[0];
    }

    // ========================== ERC-20 OVERRIDES ==========================

    /**
     * @dev MetVault shares decimals are matched to underlying asset
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// ========================== IERC-1155 RECEIVER ==========================

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external view returns (bytes4) {
        _checkNotPaused();
        /// bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))
        return 0xf23a6e61;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        view
        returns (bytes4)
    {
        _checkNotPaused();
        /// bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))
        return 0xbc197c81;
    }

    /// @dev permitAsset(), permitDai(), permitUniswap() can be batched with mint() using multicall enabling 1 tx UX
    /// ========================== PERMIT ASSET ==========================

    /// @dev if asset supports EIP712
    function permitAsset(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        _checkNotPaused();
        IERC20PermitUpgradeable(asset).permit(msg.sender, address(this), amount, deadline, v, r, s);
    }

    /// @dev if asset is DAI
    function permitDai(uint256 nonce, uint256 deadline, bool allowed, uint8 v, bytes32 r, bytes32 s) external {
        _checkNotPaused();
        IDAI(asset).permit(msg.sender, address(this), nonce, deadline, allowed, v, r, s);
    }

    /// @dev if permit is not supported for asset, Permit2 contract from Uniswap can be used - https://github.com/Uniswap/permit2
    function permitUniswap(
        PermitTransferFrom calldata permitTransferFrom,
        SignatureTransferDetails calldata signatureTransferDetails,
        bytes calldata signature
    ) external {
        _checkNotPaused();
        IPermit2(PERMIT2_ADDRESS).permitTransferFrom(
            permitTransferFrom, signatureTransferDetails, msg.sender, signature
        );
    }
}
