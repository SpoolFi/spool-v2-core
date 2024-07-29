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
import "./interfaces/IAssetGroupRegistry.sol";
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
     * @dev Only SmartVaults with zero management fee are supported
     */
    error InvalidVaultManagementFee();
    /**
     * @dev Only SmartVaults with zero deposit fee are supported
     */
    error InvalidVaultDepositFee();
    /**
     * @dev Only SmartVaults with the same underlying assets are supported
     */
    error InvalidVaultAsset();
    /**
     * @dev To remove managed smart vault its allocation should be set to zero and all SVTs should be burned
     */
    error NonZeroAllocation();
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

    // ========================== IMMUTABLES ==========================

    /**
     * @dev Maximum amount of smart vaults MetaVault can manage
     */
    uint256 public constant MAX_SMART_VAULT_AMOUNT = 8;
    /**
     * @dev SmartVaultManager contract. Gateway to Spool protocol
     */
    ISmartVaultManager public immutable smartVaultManager;
    /**
     * @dev AssetGroupRegistry contract
     */
    IAssetGroupRegistry public immutable assetGroupRegistry;
    /**
     * @dev SpoolLens contract
     */
    ISpoolLens public immutable spoolLens;

    // ========================== STATE ==========================

    /**
     * @dev Underlying asset used for investments
     */
    IERC20MetadataUpgradeable public asset;
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

    // ========================== CONSTRUCTOR ==========================

    constructor(
        ISmartVaultManager smartVaultManager_,
        ISpoolAccessControl spoolAccessControl_,
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolLens spoolLens_
    ) SpoolAccessControllable(spoolAccessControl_) {
        smartVaultManager = smartVaultManager_;
        assetGroupRegistry = assetGroupRegistry_;
        spoolLens = spoolLens_;
    }

    // ========================== INITIALIZER ==========================

    function initialize(
        address asset_,
        string memory name_,
        string memory symbol_,
        address[] calldata vaults,
        uint256[] calldata allocations
    ) external initializer {
        __Ownable2Step_init();
        __Multicall_init();
        __ERC20_init(name_, symbol_);
        asset = IERC20MetadataUpgradeable(asset_);
        _decimals = uint8(asset.decimals());
        _addSmartVaults(vaults, allocations);
        asset.approve(address(smartVaultManager), type(uint256).max);
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
     * @dev is smart vault valid to be managed by MetaVault
     * @return true or reverts
     */
    function smartVaultIsValid(address vault) external view returns (bool) {
        return _validateSmartVault(vault);
    }

    /**
     * @dev Owner of MetaVault can add new smart vaults for management
     * @param vaults list to add
     * @param allocations for all smart vaults
     */
    function addSmartVaults(address[] calldata vaults, uint256[] calldata allocations) external onlyOwner {
        _checkNotPaused();
        _checkPendingSync();
        _addSmartVaults(vaults, allocations);
    }

    /**
     * @param vaults list to add
     * @param allocations for all smart vaults
     */
    function _addSmartVaults(address[] calldata vaults, uint256[] calldata allocations) internal {
        if (vaults.length > 0) {
            /// if there is pending sync adding smart vaults is prohibited
            if (_smartVaults.list.length + vaults.length > MAX_SMART_VAULT_AMOUNT) revert MaxSmartVaultAmount();
            for (uint256 i; i < vaults.length; i++) {
                _validateSmartVault(vaults[i]);
            }
            _smartVaults.addList(vaults);
            emit SmartVaultsChange(_smartVaults.list);
            _setSmartVaultAllocations(allocations);
        }
    }

    /**
     * @dev Anybody can remove smart vault from managed list if its allocation is zero
     * @param vaults list to remove
     */
    function removeSmartVaults(address[] calldata vaults) external {
        _checkNotPaused();
        if (vaults.length > 0) {
            /// vault can be removed from managed list only when
            // its allocation and position are zero
            for (uint256 i; i < vaults.length; i++) {
                if (smartVaultToAllocation[vaults[i]] > 0 || ISmartVault(vaults[i]).balanceOf(address(this)) > 0) {
                    revert NonZeroAllocation();
                }
            }
            _smartVaults.removeList(vaults);
            emit SmartVaultsChange(_smartVaults.list);
        }
    }

    /**
     * @dev only owner of MetaVault can change the allocations for managed smart vaults
     * @param allocations to set
     */
    function setSmartVaultAllocations(uint256[] calldata allocations) external onlyOwner {
        _checkNotPaused();
        _setSmartVaultAllocations(allocations);
    }

    /**
     * @dev Check if given smart vault can be managed by MetaVault
     * @param vault to validate
     */
    function _validateSmartVault(address vault) internal view returns (bool) {
        SmartVaultFees memory fees = smartVaultManager.getSmartVaultFees(vault);
        /// management and deposit fees should be zero
        if (fees.managementFeePct > 0) revert InvalidVaultManagementFee();
        if (fees.depositFeePct > 0) revert InvalidVaultDepositFee();
        address[] memory vaultAssets = assetGroupRegistry.listAssetGroup(smartVaultManager.assetGroupId(vault));
        /// assetGroup should match the underlying asset of MetaVault
        if (vaultAssets.length != 1 || vaultAssets[0] != address(asset)) revert InvalidVaultAsset();
        return true;
    }

    /**
     * @dev set allocations for managed smart vaults
     * @param allocations to set
     */
    function _setSmartVaultAllocations(uint256[] calldata allocations) internal {
        address[] memory vaults = _smartVaults.list;
        if (allocations.length != vaults.length) revert ArgumentLengthMismatch();
        uint256 sum;
        for (uint256 i; i < vaults.length; i++) {
            sum += allocations[i];
            smartVaultToAllocation[vaults[i]] = allocations[i];
        }
        if (sum != 100_00) revert WrongAllocation();
        emit AllocationChange(allocations);
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
        asset.safeTransferFrom(msg.sender, address(this), amount);
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
        asset.safeTransfer(msg.sender, amount);
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
     * @dev anybody can flush deposits and redeems accumulated on MetaVault.
     * @return hadEffect bool indicating whether flush had some effect / reverts if not all deposit nfts are claimed/claimable
     */
    function flush() external returns (bool hadEffect) {
        _checkNotPaused();
        _checkOperator();
        _checkPendingSync();
        address[] memory vaults = _smartVaults.list;
        if (vaults.length > 0) {
            uint128 flushIndex = index.flush;
            // we process withdrawal first to ensure all SVTs are collected
            bool withdrawalIsNeeded = _flushWithdrawal(vaults, flushIndex);
            bool depositIsNeeded = _flushDeposit(vaults, flushIndex);
            hadEffect = withdrawalIsNeeded || depositIsNeeded;
            if (hadEffect) {
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
                smartVaultToDepositNftId[vaults[i]] = _spoolDeposit(vaults[i], amount);
            }
            hadEffect = true;
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
            }
            hadEffect = true;
            emit FlushWithdrawal(flushIndex, shares);
        }
    }

    /**
     * @dev anybody can sync MetaVault deposits and withdrawals
     * @return hadEffect bool indicating whether sync had some effect
     * reverts if not all deposit nfts are claimed/claimable or not all withdrawal nfts are claimed/claimable => DHW is needed
     */
    function sync() external returns (bool hadEffect) {
        _checkNotPaused();
        _checkOperator();
        address[] memory vaults = _smartVaults.list;
        if (vaults.length > 0) {
            bool depositIsNeeded = _syncDeposit(vaults);
            bool withdrawalIsNeeded = _syncWithdrawal(vaults);
            hadEffect = withdrawalIsNeeded || depositIsNeeded;
            if (hadEffect) {
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
    function _syncDeposit(address[] memory vaults) internal returns (bool hadEffect) {
        uint128 syncIndex = index.sync;
        uint256 depositedAssets = flushToDepositedAssets[syncIndex];
        if (depositedAssets > 0) {
            for (uint256 i; i < vaults.length; i++) {
                uint256[] memory depositNfts = new uint256[](1);
                depositNfts[0] = smartVaultToDepositNftId[vaults[i]];
                uint256[] memory nftAmounts = new uint256[](1);
                nftAmounts[0] = ISmartVault(vaults[i]).balanceOfFractional(address(this), depositNfts[0]);
                // make sure there is actual balance for given nft id
                if (nftAmounts[0] == 0) revert NoDepositNft(depositNfts[0]);
                smartVaultManager.claimSmartVaultTokens(vaults[i], depositNfts, nftAmounts);
                delete smartVaultToDepositNftId[vaults[i]];
            }
            (uint256 totalBalance,) = getBalances(vaults);
            uint256 totalSupply_ = totalSupply();
            uint256 toMint = totalSupply_ == 0
                ? depositedAssets
                : (totalSupply_ * depositedAssets) / (totalBalance - depositedAssets);
            flushToMintedShares[syncIndex] = toMint;
            _mint(address(this), toMint);
            hadEffect = true;
            emit SyncDeposit(syncIndex, toMint);
        }
    }

    /**
     * @dev Claim all withdrawals by burning withdrawal nfts
     * @param vaults to sync
     * @return hadEffect bool indicating whether sync had some effect
     * reverts if not all withdrawal nfts are claimable => DHW is needed
     */
    function _syncWithdrawal(address[] memory vaults) internal returns (bool hadEffect) {
        uint128 flushIndex = index.sync;
        if (flushToRedeemedShares[flushIndex] > 0) {
            /// aggregate withdrawn assets from all smart vaults
            uint256 withdrawnAssets;
            for (uint256 i; i < vaults.length; i++) {
                uint256 nftId = flushToSmartVaultToWithdrawalNftId[flushIndex][vaults[i]];
                withdrawnAssets += _spoolClaimWithdrawal(vaults[i], nftId);
                delete flushToSmartVaultToWithdrawalNftId[flushIndex][vaults[i]];
            }
            /// we fulfill last unprocessed withdrawal index
            flushToWithdrawnAssets[flushIndex] = withdrawnAssets;
            hadEffect = true;
            emit SyncWithdrawal(flushIndex, withdrawnAssets);
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
        bool isViewExecution;
    }

    /**
     * @dev only DoHardWorker can reallocate positions
     * @param slippages for redeemFast
     */
    function reallocate(uint256[][][] calldata slippages) external {
        _checkNotPaused();
        _checkOperator();
        _checkPendingSync();
        ReallocationVars memory vars = ReallocationVars(0, 0, tx.origin == address(0));
        /// cache
        address[] memory vaults = _smartVaults.list;
        /// track required adjustment for vaults positions
        uint256[] memory positionToAdd = new uint256[](vaults.length);
        (uint256 totalBalance, uint256[][] memory balances) = getBalances(vaults);
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
                uint256 svtsToRedeem = positionDiff * ISmartVault(vaults[i]).balanceOf(address(this)) / currentPosition;
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
            }
        }
        if (vars.isViewExecution) {
            return;
        }

        /// now we will perform deposits
        if (vars.withdrawnAssets > 0) {
            for (uint256 i; i < vaults.length; i++) {
                /// only if there are "MetaVault shares to deposit"
                if (positionToAdd[i] > 0) {
                    /// calculate amount of assets based on MetaVault shares ratio
                    uint256 amount = positionToAdd[i] * vars.withdrawnAssets / vars.positionChangeTotal;
                    smartVaultToDepositNftIdFromReallocation[vaults[i]] = _spoolDeposit(vaults[i], amount);
                }
            }
            emit Reallocate(reallocationIndex.flush);
            reallocationIndex.flush++;
        }
    }

    /**
     * @dev Finalize reallocation of MetaVault
     * @return hadEffect
     * false - no pending reallocation.
     * true - there was reallocation, which was successfully processed by DHW
     * revert - DHW should be run
     */
    function reallocateSync() external returns (bool hadEffect) {
        _checkNotPaused();
        _checkOperator();
        if (reallocationIndex.flush == reallocationIndex.sync) return hadEffect;
        /// cache
        address[] memory vaults = _smartVaults.list;
        for (uint256 i; i < vaults.length; i++) {
            uint256[] memory depositNftIds = new uint256[](1);
            depositNftIds[0] = smartVaultToDepositNftIdFromReallocation[vaults[i]];
            uint256[] memory nftAmounts = new uint256[](1);
            nftAmounts[0] = ISmartVault(vaults[i]).balanceOfFractional(address(this), depositNftIds[0]);
            smartVaultManager.claimSmartVaultTokens(vaults[i], depositNftIds, nftAmounts);
            hadEffect = true;
            delete smartVaultToDepositNftIdFromReallocation[vaults[i]];
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
        IERC20PermitUpgradeable(address(asset)).permit(msg.sender, address(this), amount, deadline, v, r, s);
    }

    /// @dev if asset is DAI
    function permitDai(uint256 nonce, uint256 deadline, bool allowed, uint8 v, bytes32 r, bytes32 s) external {
        _checkNotPaused();
        IDAI(address(asset)).permit(msg.sender, address(this), nonce, deadline, allowed, v, r, s);
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
