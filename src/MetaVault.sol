// SPDX-License-Identifier: BUSL-1.1
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
import "./interfaces/IMetaVault.sol";

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
    IMetaVault,
    Ownable2StepUpgradeable,
    ERC20Upgradeable,
    ERC1155ReceiverUpgradeable,
    MulticallUpgradeable,
    SpoolAccessControllable
{
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
    using ListMap for ListMap.Address;

    // ========================== IMMUTABLES ==========================

    /// @inheritdoc IMetaVault
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

    /// @inheritdoc IMetaVault
    address public asset;
    /**
     * @dev decimals of shares to match those in asset
     */
    uint8 private _decimals;

    /**
     * @dev list of managed SmartVaults
     */
    ListMap.Address internal _smartVaults;

    /// @inheritdoc IMetaVault
    mapping(address => uint256) public smartVaultToDepositNftId;

    /// @inheritdoc IMetaVault
    mapping(address => uint256) public smartVaultToDepositNftIdFromReallocation;

    /// @inheritdoc IMetaVault
    mapping(address => uint256) public smartVaultToAllocation;

    /// @inheritdoc IMetaVault
    mapping(address => uint256) public smartVaultToManagerFlushIndex;

    // @inheritdoc IMetaVault
    uint256 public maxReallocationSlippage;

    /**
     * @dev both start with zero.
     * if sync == flush it means whole cycle is completed
     * if flush > sync - there is pending sync
     */
    struct Index {
        uint128 flush;
        uint128 sync;
    }

    /// @inheritdoc IMetaVault
    Index public index;

    /// @inheritdoc IMetaVault
    Index public reallocationIndex;

    /// @inheritdoc IMetaVault
    mapping(uint128 => uint256) public flushToDepositedAssets;

    /// @inheritdoc IMetaVault
    mapping(uint128 => uint256) public flushToMintedShares;

    /// @inheritdoc IMetaVault
    mapping(uint128 => uint256) public flushToRedeemedShares;

    /// @inheritdoc IMetaVault
    mapping(uint128 => uint256) public flushToWithdrawnAssets;

    /// @inheritdoc IMetaVault
    mapping(uint128 => mapping(address => uint256)) public flushToSmartVaultToWithdrawalNftId;

    /// @inheritdoc IMetaVault
    mapping(address => mapping(uint128 => uint256)) public userToFlushToDepositedAssets;

    /// @inheritdoc IMetaVault
    mapping(address => mapping(uint128 => uint256)) public userToFlushToRedeemedShares;

    /// @inheritdoc IMetaVault
    mapping(bytes4 => bool) public selectorToPaused;

    /// @inheritdoc IMetaVault
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
        // 1% by default
        maxReallocationSlippage = 1_00;
    }

    // ==================== PAUSING ====================

    /// @inheritdoc IMetaVault
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

    /// @inheritdoc IMetaVault
    function getSmartVaults() external view returns (address[] memory) {
        return _smartVaults.list;
    }

    /// @inheritdoc IMetaVault
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
            // if there is pending sync adding smart vaults is prohibited
            if (_smartVaults.list.length + vaults.length > MAX_SMART_VAULT_AMOUNT) revert MaxSmartVaultAmount();
            metaVaultGuard.validateSmartVaults(asset, vaults);
            _smartVaults.addList(vaults);
            emit SmartVaultsChange(_smartVaults.list);
            _setSmartVaultAllocations(allocations, initialization);
        }
    }

    /// @inheritdoc IMetaVault
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
            emit NeedReallocationState(true);
        }
    }

    function setMaxReallocationSlippage(uint256 value) external onlyOwner {
        if (value > 100_00) revert MaxReallocationSlippage();
        maxReallocationSlippage = value;
        emit MaxReallocationSlippageChange(value);
    }

    // ========================== USER FACING ==========================

    /// @inheritdoc IMetaVault
    function deposit(uint256 amount) external {
        _deposit(amount, msg.sender);
    }

    /// @inheritdoc IMetaVault
    function deposit(uint256 amount, address receiver) external {
        _deposit(amount, receiver);
    }

    function _deposit(uint256 amount, address receiver) internal {
        _checkNotPaused();
        uint128 flushIndex = index.flush;
        // MetaVault has now more funds to manage
        flushToDepositedAssets[flushIndex] += amount;
        userToFlushToDepositedAssets[receiver][flushIndex] += amount;
        IERC20MetadataUpgradeable(asset).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(receiver, flushIndex, amount);
    }

    /// @inheritdoc IMetaVault
    function claim(uint128 flushIndex) external returns (uint256 shares) {
        _checkNotPaused();
        shares = claimable(msg.sender, flushIndex);
        delete userToFlushToDepositedAssets[msg.sender][flushIndex];
        _transfer(address(this), msg.sender, shares);
        emit Claim(msg.sender, flushIndex, shares);
    }

    /// @inheritdoc IMetaVault
    function claimable(address user, uint128 flushIndex) public view returns (uint256) {
        uint256 assets = userToFlushToDepositedAssets[user][flushIndex];
        if (flushIndex >= index.sync || assets == 0) revert NothingToClaim();
        return flushToMintedShares[flushIndex] * assets / flushToDepositedAssets[flushIndex];
    }

    /// @inheritdoc IMetaVault
    function redeem(uint256 shares) external {
        _checkNotPaused();
        _burn(msg.sender, shares);
        uint128 flushIndex = index.flush;
        // accumulate redeems for all users for current flush index
        flushToRedeemedShares[flushIndex] += shares;
        // accumulate redeems for particular user for current flush index
        userToFlushToRedeemedShares[msg.sender][flushIndex] += shares;
        emit Redeem(msg.sender, flushIndex, shares);
    }

    /// @inheritdoc IMetaVault
    function withdraw(uint128 flushIndex) external returns (uint256 amount) {
        _checkNotPaused();
        amount = withdrawable(msg.sender, flushIndex);
        // delete entry for user to disable repeated withdrawal
        delete userToFlushToRedeemedShares[msg.sender][flushIndex];
        IERC20MetadataUpgradeable(asset).safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, flushIndex, amount);
    }

    /// @inheritdoc IMetaVault
    function withdrawable(address user, uint128 flushIndex) public view returns (uint256) {
        uint256 shares = userToFlushToRedeemedShares[user][flushIndex];
        // user can withdraw funds only for synced flush
        if (flushIndex >= index.sync || shares == 0) revert NothingToWithdraw();
        // amount of funds user get from specified withdrawal index
        return shares * flushToWithdrawnAssets[flushIndex] / flushToRedeemedShares[flushIndex];
    }

    // ========================== SPOOL INTERACTIONS ==========================

    /**
     * @dev check that regular flush and reallocation are synced
     */
    function _checkPendingSync() internal view {
        if (index.sync < index.flush || reallocationIndex.sync < reallocationIndex.flush) revert PendingSync();
    }

    /**
     * @dev check that the caller is operator of MetaVaults
     */
    function _checkOperator() internal view {
        if (tx.origin != address(0)) _checkRole(ROLE_META_VAULT_OPERATOR, msg.sender);
    }

    /// @inheritdoc IMetaVault
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
            if (hadEffect) {
                emit FlushDeposit(index.flush, assets);
            }
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
            if (hadEffect) {
                emit FlushWithdrawal(flushIndex, shares);
            }
        }
    }

    /// @inheritdoc IMetaVault
    function sync() external {
        _checkNotPaused();
        _checkOperator();
        address[] memory vaults = _smartVaults.list;
        Index memory index_ = index;
        if (vaults.length > 0 && index_.sync < index_.flush) {
            (bool depositHadEffect, uint256 totalBalance) = _syncDeposit(vaults, index_.sync);
            bool withdrawalHadEffect = _syncWithdrawal(vaults, index_.sync);
            if (depositHadEffect || withdrawalHadEffect) {
                index.sync++;
                emit SharePrice(totalBalance, totalSupply());
            }
        }
    }

    /**
     * @dev Claims all SVTs by burning deposit nfts
     * @param vaults to sync
     * @return hadEffect bool indicating whether sync had some effect
     * reverts if not all deposit nfts are claimed/claimable => DHW is needed
     */
    function _syncDeposit(address[] memory vaults, uint128 syncIndex)
        internal
        returns (bool hadEffect, uint256 totalBalance)
    {
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
        }
        (totalBalance,) = _getBalances(vaults);
        if (hadEffect) {
            uint256 totalSupply_ = totalSupply();
            uint256 toMint = totalSupply_ == 0
                ? depositedAssets
                : (totalSupply_ * depositedAssets) / (totalBalance - depositedAssets);
            flushToMintedShares[syncIndex] = toMint;
            _mint(address(this), toMint);
            emit SyncDeposit(syncIndex, toMint);
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
            // aggregate withdrawn assets from all smart vaults
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
                // we fulfill last unprocessed withdrawal index
                flushToWithdrawnAssets[syncIndex] = withdrawnAssets;
                emit SyncWithdrawal(syncIndex, withdrawnAssets);
            }
        }
    }

    /// @inheritdoc IMetaVault
    function getBalances() external returns (uint256 totalBalance, uint256[] memory balances) {
        return _getBalances(_smartVaults.list);
    }

    function _getBalances(address[] memory vaults) internal returns (uint256 totalBalance, uint256[] memory balances) {
        uint256[][] memory balances_ = spoolLens.getUserVaultAssetBalances(
            address(this), vaults, new uint256[][](vaults.length), new bool[](vaults.length)
        );
        balances = new uint256[](balances_.length);
        for (uint256 i; i < balances_.length; i++) {
            totalBalance += balances_[i][0];
            balances[i] = balances_[i][0];
        }
        return (totalBalance, balances);
    }

    struct ReallocationVars {
        // total amount of assets withdrawn during the reallocation
        uint256 withdrawnAssets;
        // total position change
        uint256 positionChangeTotal;
        // amount of vaults to remove
        uint256 vaultsToRemoveCount;
        // index for populating list of vaults for removal
        uint256 vaultToRemoveIndex;
        // flag to check whether it is a estimation transaction to get svts amount
        bool isViewExecution;
    }

    /// @inheritdoc IMetaVault
    function reallocate(uint256[][][] calldata slippages) external {
        _checkNotPaused();
        _checkOperator();
        _checkPendingSync();
        ReallocationVars memory vars = ReallocationVars(0, 0, 0, 0, tx.origin == address(0));
        // cache
        address[] memory vaults = _smartVaults.list;
        // track required adjustment for vaults positions
        // uint256 max means vault should be removed
        uint256[] memory positionToAdd = new uint256[](vaults.length);
        (uint256 totalBalance, uint256[] memory balances) = _getBalances(vaults);
        if (totalBalance > 0) {
            for (uint256 i; i < vaults.length; i++) {
                uint256 currentPosition = balances[i];
                uint256 desiredPosition = smartVaultToAllocation[vaults[i]] * totalBalance / 100_00;
                // if more MetaVault shares should be deposited we save this data for later
                if (desiredPosition > currentPosition) {
                    uint256 positionDiff = desiredPosition - currentPosition;
                    positionToAdd[i] = positionDiff;
                    vars.positionChangeTotal += positionDiff;
                    // if amount of MetaVault shares should be reduced we perform redeemFast
                } else if (desiredPosition < currentPosition) {
                    uint256 positionDiff = currentPosition - desiredPosition;
                    // previously all SVTs shares were claimed,
                    // so we can calculate the proportion of SVTs to be withdrawn using MetaVault deposited shares ratio
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

            // now we will perform deposits and vaults removal
            if (vars.withdrawnAssets > 0) {
                // check that we have not lost more money then specified by MetaVault owner
                {
                    (uint256 newTotalBalance,) = _getBalances(vaults);
                    uint256 shouldBeBalance = newTotalBalance + vars.withdrawnAssets;
                    uint256 maxAllowedChange = totalBalance * maxReallocationSlippage / 100_00;
                    if (totalBalance > shouldBeBalance && totalBalance - shouldBeBalance > maxAllowedChange) {
                        revert MaxReallocationSlippage();
                    }
                }
                address[] memory vaultsToRemove = new address[](vars.vaultsToRemoveCount);
                for (uint256 i; i < vaults.length; i++) {
                    if (positionToAdd[i] == type(uint256).max) {
                        // collect vaults for removal
                        vaultsToRemove[vars.vaultToRemoveIndex] = vaults[i];
                        vars.vaultToRemoveIndex++;
                    } else if (positionToAdd[i] > 0) {
                        // only if there are "MetaVault shares to deposit"
                        // calculate amount of assets based on MetaVault shares ratio
                        uint256 amount = positionToAdd[i] * vars.withdrawnAssets / vars.positionChangeTotal;
                        smartVaultToDepositNftIdFromReallocation[vaults[i]] = _spoolDeposit(vaults[i], amount);
                        smartVaultToManagerFlushIndex[vaults[i]] = smartVaultManager.getLatestFlushIndex(vaults[i]);
                    }
                }
                emit Reallocate(reallocationIndex.flush);
                reallocationIndex.flush++;
                // remove smart vault from managed list on reallocation
                if (vaultsToRemove.length > 0) {
                    _smartVaults.removeList(vaultsToRemove);
                    emit SmartVaultsChange(_smartVaults.list);
                }
            }
        }
        needReallocation = false;
        emit NeedReallocationState(false);
    }

    /// @inheritdoc IMetaVault
    function reallocateSync() external {
        _checkNotPaused();
        _checkOperator();
        if (reallocationIndex.flush == reallocationIndex.sync) return;
        bool hadEffect;
        // cache
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
     * @notice MetVault shares decimals are matched to underlying asset
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    // ========================== IERC-1155 RECEIVER ==========================

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external view returns (bytes4) {
        _checkNotPaused();
        // bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))
        return 0xf23a6e61;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        view
        returns (bytes4)
    {
        _checkNotPaused();
        // bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))
        return 0xbc197c81;
    }

    // @dev permitAsset(), permitDai() can be batched with deposit(), swapAndDeposit() using multicall enabling 1 tx UX
    // ========================== PERMIT ASSET ==========================

    /// @inheritdoc IMetaVault
    function permitAsset(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        _checkNotPaused();
        IERC20PermitUpgradeable(asset).permit(msg.sender, address(this), amount, deadline, v, r, s);
    }

    /// @inheritdoc IMetaVault
    function permitDai(uint256 nonce, uint256 deadline, bool allowed, uint8 v, bytes32 r, bytes32 s) external {
        _checkNotPaused();
        IDAI(asset).permit(msg.sender, address(this), nonce, deadline, allowed, v, r, s);
    }
}
