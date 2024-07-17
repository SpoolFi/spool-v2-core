/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC1155/utils/ERC1155ReceiverUpgradeable.sol";
import "@openzeppelin-upgradeable/utils/MulticallUpgradeable.sol";

import "./managers/SmartVaultManager.sol";
import "./managers/AssetGroupRegistry.sol";
import "./access/SpoolAccessControllable.sol";
import "./libraries/ListMap.sol";

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
    using ListMap for ListMap.Uint256;

    // ========================== EVENTS ==========================

    /**
     * @dev User minted MetaVault shares in exchange for asset
     */
    event Mint(address indexed user, uint256 shares);
    /**
     * @dev User redeemed MetaVault shares to get assets back
     */
    event RedeemRequest(address indexed user, uint256 indexed withdrawalIndex, uint256 shares);
    /**
     * @dev User has withdrawn his assets
     */
    event Withdraw(address indexed user, uint256 indexed withdrawalIndex, uint256 assets, uint256 shares);
    /**
     * @dev flushDeposit has run
     */
    event FlushDeposit(uint256 assets);
    /**
     * @dev flushWithdrawal has run
     */
    event FlushWithdrawal(uint256 indexed withdrawalIndex, uint256 shares);
    /**
     * @dev syncWithdrawal has run
     */
    event SyncWithdrawal(uint256 indexed withdrawalIndex, uint256 assets);
    /**
     * @dev flushWithdrawalFast has run
     */
    event FlushWithdrawalFast(uint256 indexed withdrawalIndex, uint256 assets, uint256 shares);
    /**
     * @dev SmartVaults have been changed
     */
    event SmartVaultsChange(address[] previous, address[] current);
    /**
     * @dev Allocations have been changed
     */
    event AllocationChange(uint256[] previous, uint256[] current);

    // ========================== ERRORS ==========================

    /**
     * @dev There are no SVTs to claim for nft id
     */
    error NothingToClaim(uint256 nftId);
    /**
     * @dev User has nothing to withdraw
     */
    error NothingToWithdraw();
    /**
     * @dev There are no withdrawal nfts
     */
    error NothingToFulfill(uint256 nftId);
    /**
     * @dev Transfer of deposit and withdrawal nfts to MetaVault are forbidden
     */
    error NftTransferForbidden();
    /**
     * @dev MetaVault supports only ERC-1155 token of currently managed vaults
     */
    error TokenNotSupported();
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
     * @dev To remove managed smart vault its allocation should be set to zero first
     */
    error NonZeroAllocation();
    /**
     * @dev To remove managed smart vault its position should be zero
     */
    error NonZeroPosition();
    /**
     * @dev user is not allowed to withdraw asset before his redeem request is fulfilled
     */
    error RedeemRequestNotFulfilled();
    /**
     * @dev Maximum smart vault amount is exceeded
     */
    error MaxSmartVaultAmount();
    /**
     * @dev Withdrawal is prohibited if there are pending deposits
     */
    error PendingDeposit();

    // ========================== IMMUTABLES ==========================

    /**
     * @dev Maximum amount of smart vaults MetaVault can manage
     */
    // TODO: we need to verify that this amount is optimal (business + technical)
    uint256 public constant MAX_SMART_VAULT_AMOUNT = 8;
    /**
     * @dev SmartVaultManager contract. Gateway to Spool protocol
     */
    ISmartVaultManager public immutable smartVaultManager;
    /**
     * @dev AssetGroupRegistry contract
     */
    IAssetGroupRegistry public immutable assetGroupRegistry;

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
     * @dev list of deposit nfts for particular smart vault
     */
    mapping(address => ListMap.Uint256) internal _smartVaultToDepositNftIds;
    /**
     * @dev allocation is in base points
     */
    mapping(address => uint256) public smartVaultToAllocation;
    /**
     * @dev how many MetaVault shares are allocated to particular smart vault
     */
    mapping(address => uint256) public smartVaultToPosition;
    /**
     * @dev total amount of MetaVault shares allocated to all managed smart vaults
     */
    uint256 public positionTotal;
    /**
     * @dev all assets available for management by MetaVault.
     * asset.balanceOf(address(this)) can be greater than availableAssets, since funds for withdrawals are excluded.
     */
    uint256 public availableAssets;
    /**
     * @dev current withdrawal index. Used to process batch of pending redeem requests.
     */
    uint256 public currentWithdrawalIndex;
    /**
     * @dev last withdrawal index, where all redeem requests were fulfilled
     */
    uint256 public lastFulfilledWithdrawalIndex;
    /**
     * @dev total amount of shares redeemed by users in particular withdrawal index
     */
    mapping(uint256 => uint256) public withdrawalIndexToRedeemedShares;
    /**
     * @dev total amount of assets received by MetaVault in particular withdrawal index
     */
    mapping(uint256 => uint256) public withdrawalIndexToWithdrawnAssets;
    /**
     * @dev indicates that withdrawal for particular index has been initiated
     */
    mapping(uint256 => bool) public withdrawalIndexIsInitiated;
    /**
     * @dev withdrawal nft id associated with particular smart vault for specific withdrawal index
     */
    mapping(uint256 => mapping(address => uint256)) public withdrawalIndexToSmartVaultToWithdrawalNftId;
    /**
     * @dev amount of shares user redeemed in specific withdrawal index
     */
    mapping(address => mapping(uint256 => uint256)) public userToWithdrawalIndexToRedeemedShares;

    // ========================== CONSTRUCTOR ==========================

    constructor(
        ISmartVaultManager smartVaultManager_,
        ISpoolAccessControl spoolAccessControl_,
        IAssetGroupRegistry assetGroupRegistry_
    ) SpoolAccessControllable(spoolAccessControl_) {
        smartVaultManager = smartVaultManager_;
        assetGroupRegistry = assetGroupRegistry_;
    }

    // ========================== INITIALIZER ==========================

    function initialize(address asset_, string memory name_, string memory symbol_) external initializer {
        __Ownable2Step_init();
        __Multicall_init();
        __ERC20_init(name_, symbol_);
        asset = IERC20MetadataUpgradeable(asset_);
        _decimals = uint8(asset.decimals());
        asset.approve(address(smartVaultManager), type(uint256).max);
        currentWithdrawalIndex = 1;
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
     * @dev is smart vault managed by MetaVault
     * @return true or false
     */
    function smartVaultSupported(address vault) external view returns (bool) {
        return _smartVaults.includes[vault];
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
        address[] memory previousVaults = _smartVaults.list;
        if (previousVaults.length + vaults.length > MAX_SMART_VAULT_AMOUNT) revert MaxSmartVaultAmount();
        for (uint256 i; i < vaults.length; i++) {
            _validateSmartVault(vaults[i]);
        }
        _smartVaults.addList(vaults);
        emit SmartVaultsChange(previousVaults, _smartVaults.list);
        _setSmartVaultAllocations(allocations);
    }

    /**
     * @dev Anybody can remove smart vault from managed list if its allocation is zero
     * @param vaults list to remove
     */
    function removeSmartVaults(address[] calldata vaults) external {
        /// vault can be removed from managed list only when
        // its allocation and position are zero
        for (uint256 i; i < vaults.length; i++) {
            if (smartVaultToAllocation[vaults[i]] > 0) revert NonZeroAllocation();
            if (smartVaultToPosition[vaults[i]] > 0) revert NonZeroPosition();
        }
        address[] memory previousVaults = _smartVaults.list;
        _smartVaults.removeList(vaults);
        emit SmartVaultsChange(previousVaults, _smartVaults.list);
    }

    /**
     * @dev get the array of deposit nfts which should be exchanged for SVTs
     * @param smartVault address
     */
    function getSmartVaultDepositNftIds(address smartVault) external view returns (uint256[] memory) {
        return _smartVaultToDepositNftIds[smartVault].list;
    }

    /**
     * @dev only owner of MetaVault can change the allocations for managed smart vaults
     * @param allocations to set
     */
    function setSmartVaultAllocations(uint256[] calldata allocations) external onlyOwner {
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
        uint256[] memory previousAllocation = new uint256[](vaults.length);
        uint256[] memory currentAllocation = new uint256[](vaults.length);
        for (uint256 i; i < vaults.length; i++) {
            sum += allocations[i];
            previousAllocation[i] = smartVaultToAllocation[vaults[i]];
            currentAllocation[i] = allocations[i];
            smartVaultToAllocation[vaults[i]] = allocations[i];
        }
        if (sum != 100_00) revert WrongAllocation();
        emit AllocationChange(previousAllocation, currentAllocation);
    }

    // ========================== USER FACING ==========================

    /**
     * @dev deposit asset into MetaVault
     * @param amount of assets
     */
    function mint(uint256 amount) external {
        /// MetaVault has now more funds to manage
        availableAssets += amount;
        _mint(msg.sender, amount);
        asset.safeTransferFrom(msg.sender, address(this), amount);
        emit Mint(msg.sender, amount);
    }

    /**
     * @dev create a redeem request to get assets back
     * @param shares of MetaVault to burn
     */
    function redeem(uint256 shares) external {
        _burn(msg.sender, shares);
        uint256 index = currentWithdrawalIndex;
        /// accumulate redeems for all users for current withdrawal index
        withdrawalIndexToRedeemedShares[index] += shares;
        /// accumulate redeems for particular user for current withdrawal index
        userToWithdrawalIndexToRedeemedShares[msg.sender][index] += shares;
        emit RedeemRequest(msg.sender, index, shares);
    }

    /**
     * @dev user can withdraw assets once his request with specific withdrawal index is fulfilled
     * @param index of withdrawal index
     */
    function withdraw(uint256 index) external returns (uint256 amount) {
        /// user can withdraw funds only for fulfilled withdrawal index
        if (lastFulfilledWithdrawalIndex < index) revert RedeemRequestNotFulfilled();
        /// amount of funds user get from specified withdrawal index
        uint256 shares = withdrawalIndexToRedeemedShares[index];
        amount =
            userToWithdrawalIndexToRedeemedShares[msg.sender][index] * withdrawalIndexToWithdrawnAssets[index] / shares;
        if (amount == 0) revert NothingToWithdraw();
        /// delete entry for user to disable repeated withdrawal
        delete userToWithdrawalIndexToRedeemedShares[msg.sender][index];
        asset.safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, index, amount, shares);
    }

    // ========================== SPOOL INTERACTIONS ==========================

    /**
     * @dev anybody can flush deposits accumulated on MetaVault.
     * Deposits into all managed smart vaults based on allocation.
     * On deposits MetaVault receives deposit nfts.
     */
    function flushDeposit() external {
        /// if there are assets available for deposits
        uint256 assets = availableAssets;
        if (assets > 0) {
            uint256 deposited;
            address[] memory vaults = _smartVaults.list;
            for (uint256 i; i < vaults.length; i++) {
                uint256 amount;
                /// handle dust so that available assets would go to 0
                if (i == vaults.length - 1) {
                    amount = assets - deposited;
                } else {
                    amount = assets * smartVaultToAllocation[vaults[i]] / 100_00;
                }
                deposited += amount;
                smartVaultToPosition[vaults[i]] += amount;
                uint256 nftId = _spoolDeposit(vaults[i], amount);
                _smartVaultToDepositNftIds[vaults[i]].add(nftId);
            }
            positionTotal += assets;
            availableAssets = 0;
            emit FlushDeposit(assets);
        }
    }

    /**
     * @dev anybody can flush redeems  accumulated on MetaVault
     * Redeem all shares from last non-initiated unfulfilled withdrawal index.
     * On redeems MetaVault burns deposit nfts for SVTs and burns SVTs for redeem on Spool.
     */
    function flushWithdrawal() external {
        if (availableAssets > 0) revert PendingDeposit();
        /// if there are open positions
        if (positionTotal > 0) {
            for (uint256 index = lastFulfilledWithdrawalIndex + 1; index <= currentWithdrawalIndex; index++) {
                uint256 shares = withdrawalIndexToRedeemedShares[index];
                /// for this withdrawal index nothing has been redeemed so return immediately
                if (shares == 0) return;
                /// if assets for the withdrawal index were not yet requested
                if (!withdrawalIndexIsInitiated[index]) {
                    uint256 closedPosition;
                    address[] memory vaults = _smartVaults.list;
                    for (uint256 i; i < vaults.length; i++) {
                        /// claim all SVTs first
                        _spoolClaimSmartVaultTokens(vaults[i]);
                        uint256 SVTBalance = ISmartVault(vaults[i]).balanceOf(address(this));
                        uint256 SVTToRedeem = SVTBalance * shares / positionTotal;
                        uint256 positionChange;
                        /// handle dust
                        if (i == vaults.length - 1) {
                            positionChange = shares - closedPosition;
                        } else {
                            positionChange = smartVaultToPosition[vaults[i]] * shares / positionTotal;
                        }
                        closedPosition += positionChange;
                        smartVaultToPosition[vaults[i]] -= positionChange;
                        withdrawalIndexToSmartVaultToWithdrawalNftId[index][vaults[i]] =
                            _spoolRedeem(vaults[i], SVTToRedeem);
                    }
                    positionTotal -= shares;
                    currentWithdrawalIndex++;
                    withdrawalIndexIsInitiated[index] = true;
                    emit FlushWithdrawal(index, shares);
                    return;
                }
            }
        }
    }

    /**
     * @dev only DoHardWorker is allowed to flush fast.
     * Redeem fast all shares from last non-initiated unfulfilled withdrawal index.
     * @param slippages data for redeemFast
     */
    function flushWithdrawalFast(uint256[][][] calldata slippages) external onlyRole(ROLE_DO_HARD_WORKER, msg.sender) {
        if (availableAssets > 0) revert PendingDeposit();
        /// if there are open positions
        if (positionTotal > 0) {
            for (uint256 index = lastFulfilledWithdrawalIndex + 1; index <= currentWithdrawalIndex; index++) {
                uint256 shares = withdrawalIndexToRedeemedShares[index];
                /// for this withdrawal index nothing has been redeemed so return immediately
                if (shares == 0) return;
                /// if assets for the withdrawal index were not yet requested
                if (!withdrawalIndexIsInitiated[index]) {
                    /// aggregate withdrawn assets from all smart vaults
                    uint256 withdrawnAssets;
                    uint256 closedPosition;
                    address[] memory vaults = _smartVaults.list;
                    for (uint256 i; i < vaults.length; i++) {
                        /// claim all SVTs first
                        _spoolClaimSmartVaultTokens(vaults[i]);
                        uint256 SVTBalance = ISmartVault(vaults[i]).balanceOf(address(this));
                        uint256 SVTToRedeem = SVTBalance * shares / positionTotal;
                        withdrawnAssets += _spoolRedeemFast(vaults[i], SVTToRedeem, slippages[i]);
                        uint256 positionChange;
                        /// handle dust
                        if (i == vaults.length - 1) {
                            positionChange = shares - closedPosition;
                        } else {
                            positionChange = smartVaultToPosition[vaults[i]] * shares / positionTotal;
                        }
                        closedPosition += positionChange;
                        smartVaultToPosition[vaults[i]] -= positionChange;
                    }
                    positionTotal -= shares;
                    lastFulfilledWithdrawalIndex++;
                    currentWithdrawalIndex++;
                    withdrawalIndexToWithdrawnAssets[lastFulfilledWithdrawalIndex] = withdrawnAssets;
                    emit FlushWithdrawalFast(index, withdrawnAssets, shares);
                    return;
                }
            }
        }
    }

    /**
     * @dev anybody can sync MetaVault deposits
     */
    function syncDeposit() external {
        address[] memory vaults = _smartVaults.list;
        for (uint256 i; i < vaults.length; i++) {
            _spoolClaimSmartVaultTokens(vaults[i]);
        }
        // TODO: do we need event here? _spoolClaimSmartVaultTokens called in other places to ensure that deposits are finalized
        // so there is probably no need to call this separately? Or we should still emit here? But then how to handle the case when this function is omitted?
    }

    /**
     * @dev anybody can sync MetaVault withdrawal
     */
    function syncWithdrawal() external {
        address[] memory vaults = _smartVaults.list;
        while (lastFulfilledWithdrawalIndex < currentWithdrawalIndex - 1) {
            uint256 index = lastFulfilledWithdrawalIndex + 1;
            /// aggregate withdrawn assets from all smart vaults
            uint256 withdrawnAssets;
            for (uint256 i; i < vaults.length; i++) {
                uint256 nftId = withdrawalIndexToSmartVaultToWithdrawalNftId[index][vaults[i]];
                // no withdrawal nft means withdrawal is not initiated yet
                if (nftId == 0) return;
                /// aggregate withdrawn assets from all smart vaults
                withdrawnAssets += _spoolClaimWithdrawal(vaults[i], nftId);
                delete withdrawalIndexToSmartVaultToWithdrawalNftId[index][vaults[i]];
            }
            /// we fulfill last unprocessed withdrawal index
            withdrawalIndexToWithdrawnAssets[index] = withdrawnAssets;
            lastFulfilledWithdrawalIndex = index;
            emit SyncWithdrawal(index, withdrawnAssets);
        }
    }

    /**
     * @dev only DoHardWorker can reallocate posotions
     * @param slippages for redeemFast
     */
    function reallocate(uint256[][][] calldata slippages) external onlyRole(ROLE_DO_HARD_WORKER, msg.sender) {
        /// cache
        address[] memory vaults = _smartVaults.list;
        /// total amount of assets withdrawn during the reallocation
        uint256 withdrawnAssets;
        /// total equivalent of MetaVault shares for position change
        uint256 positionChangeTotal;
        /// track required adjustment for vaults positions
        uint256[] memory positionToAdd = new uint256[](vaults.length);
        for (uint256 i; i < vaults.length; i++) {
            /// claim all SVTs first
            _spoolClaimSmartVaultTokens(vaults[i]);

            uint256 currentPosition = smartVaultToPosition[vaults[i]];
            /// calculate the amount of MetaVault shares which should be allocated to that vault
            uint256 desiredPosition = smartVaultToAllocation[vaults[i]] * positionTotal / 100_00;
            /// if more MetaVault shares should be deposited we save this data for later
            if (desiredPosition > currentPosition) {
                uint256 positionDif = desiredPosition - currentPosition;
                positionToAdd[i] = positionDif;
                positionChangeTotal += positionDif;
                // if amount of MetaVault shares should be reduced we perform redeemFast
            } else if (desiredPosition < currentPosition) {
                uint256 positionDif = currentPosition - desiredPosition;
                /// previously all SVTs shares were claimed,
                /// so we can calculate the proportion of SVTs to be withdrawn using MetaVault deposited shares ratio
                uint256 svtsToRedeem = positionDif * ISmartVault(vaults[i]).balanceOf(address(this)) / positionTotal;
                smartVaultToPosition[vaults[i]] -= positionDif;
                withdrawnAssets += _spoolRedeemFast(vaults[i], svtsToRedeem, slippages[i]);
            }
        }

        /// now we will perform deposits
        /// due to rounding errors newPositionTotal can differ from positionTotal
        uint256 newPositionTotal;
        for (uint256 i; i < vaults.length; i++) {
            /// only if there are "MetaVault shares to deposit"
            if (positionToAdd[i] > 0) {
                smartVaultToPosition[vaults[i]] += positionToAdd[i];
                /// calculate amount of assets based on MetaVault shares ratio
                uint256 amount = positionToAdd[i] * withdrawnAssets / positionChangeTotal;
                _spoolDeposit(vaults[i], amount);
            }
            newPositionTotal += smartVaultToPosition[vaults[i]];
        }
        /// we want to keep positionTotal and sum of smartVaultToPosition in sync
        if (newPositionTotal < positionTotal) {
            // assign the dust to first smart vault
            smartVaultToPosition[vaults[0]] += positionTotal - newPositionTotal;
        } else if (newPositionTotal > positionTotal) {
            smartVaultToPosition[vaults[0]] -= newPositionTotal - positionTotal;
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
        DepositBag memory bag = DepositBag({
            smartVault: vault,
            assets: assets,
            receiver: address(this),
            doFlush: false,
            referral: address(0)
        });
        nftId = smartVaultManager.deposit(bag);
    }

    /**
     * @dev claim smart vault tokens (SVTs)
     * will revert if balance is zero or deposit was not processed by DHW
     * it is intentional to ensure that in all places it is used deposits of MetaVault are finalized first
     * @param vault address
     */
    function _spoolClaimSmartVaultTokens(address vault) internal {
        uint256[] memory depositNftIds = _smartVaultToDepositNftIds[vault].list;
        if (depositNftIds.length > 0) {
            uint256[] memory nftAmounts = new uint256[](depositNftIds.length);
            for (uint256 i; i < depositNftIds.length; i++) {
                nftAmounts[i] = ISmartVault(vault).balanceOfFractional(address(this), depositNftIds[i]);
                // make sure there is actual balance for given nft id
                if (nftAmounts[i] == 0) revert NothingToClaim(depositNftIds[i]);
            }
            _smartVaultToDepositNftIds[vault].clean();
            smartVaultManager.claimSmartVaultTokens(vault, depositNftIds, nftAmounts);
        }
    }

    /**
     * @dev redeem from Spool
     * @param vault address
     * @param shares amount
     * @return nftId for redeem
     */
    function _spoolRedeem(address vault, uint256 shares) internal returns (uint256 nftId) {
        RedeemBag memory bag =
            RedeemBag({smartVault: vault, shares: shares, nftIds: new uint256[](0), nftAmounts: new uint256[](0)});
        nftId = smartVaultManager.redeem(bag, address(this), false);
    }

    /**
     * @dev redeem fast from Spool
     * @param vault address
     * @param shares amount
     * @param slippages for redeemFast
     * @return amount of assets withdrawn
     */
    function _spoolRedeemFast(address vault, uint256 shares, uint256[][] calldata slippages)
        internal
        returns (uint256 amount)
    {
        RedeemBag memory bag =
            RedeemBag({smartVault: vault, shares: shares, nftIds: new uint256[](0), nftAmounts: new uint256[](0)});
        amount = smartVaultManager.redeemFast(bag, slippages)[0];
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

    function onERC1155Received(address, address from, uint256, uint256, bytes calldata)
        external
        view
        validateToken(from)
        returns (bytes4)
    {
        /// bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))
        return 0xf23a6e61;
    }

    function onERC1155BatchReceived(address, address from, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        view
        validateToken(from)
        returns (bytes4)
    {
        /// bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))
        return 0xbc197c81;
    }

    /**
     * @dev only ERC1155 tokens directly minted from managed smart vaults are accepted
     */
    modifier validateToken(address from) {
        if (!_smartVaults.includes[msg.sender]) revert TokenNotSupported();
        if (from != address(0)) revert NftTransferForbidden();
        _;
    }
}
