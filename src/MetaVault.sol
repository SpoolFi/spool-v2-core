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
 * It has an owner, which is responsible for calling Spool Core V2 specific methods:
 * deposit, redeem, redeemFast, claimSmartVaultTokens and claimWithdrawal.
 * In this way MetaVault owner can manage funds from users in trustless manner.
 * MetaVault supports only one ERC-20 asset.
 * Users can deposit funds and in return they get MetaVault shares.
 * To redeem users are required to burn they MetaVault shares, while creating redeem request,
 * which is processed in asynchronous manner.
 * While there are some pending redeem requests, deposits into Spool protocol are prohibited.
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
    event Mint(address indexed user, uint256 amount);
    event RedeemRequest(address indexed user, uint256 indexed withdrawalCycle, uint256 shares);
    event Withdraw(address indexed user, uint256 indexed withdrawalCycle, uint256 amount);

    // ========================== ERRORS ==========================
    error PendingDeposits();
    error PendingWithdrawals();
    error NothingToClaim(uint256 nftId);
    error NothingToWithdraw();
    error NothingToFulfill(uint256 nftId);
    error NftTransferForbidden();
    error TokenNotSupported();
    error WrongAllocation();
    error ArgumentLengthMismatch();
    error InvalidVaultManagementFee();
    error InvalidVaultDepositFee();
    error InvalidVaultAsset();
    error NonZeroAllocation();

    /**
     * @dev user is not allowed to withdraw asset until his redeem request is not fulfilled
     */
    error RedeemRequestNotFulfilled();

    // ========================== IMMUTABLES ==========================

    /**
     * @dev SmartVaultManager contract. Gateway to Spool protocol
     */
    ISmartVaultManager public immutable smartVaultManager;
    /**
     * @dev AssetGroupRegistry contract
     */
    IAssetGroupRegistry public immutable assetGroupRegistry;
    /**
     * @dev Underlying asset used for investments
     */
    IERC20MetadataUpgradeable public immutable asset;
    /**
     * @dev decimals of shares to match those in asset
     */
    uint8 private immutable _decimals;

    // ========================== STATE ==========================

    ListMap.Address internal _smartVaults;

    // in base points
    mapping(address => uint256) public smartVaultToAllocation;

    mapping(address => uint256) public smartVaultToDepositedShares;

    // TODO: rename. Should reflect the fact that those are shares of users used in spool
    uint256 public depositedSharesTotal;

    mapping(address => ListMap.Uint256) internal _smartVaultToDepositNftIds;
    mapping(address => ListMap.Uint256) internal _smartVaultToWithdrawalNftIds;

    /**
     * @dev all assets available for management by MetaVault.
     * asset.balanceOf(address(this)) can be greater than availableAssets, since funds for withdrawals are excluded.
     */
    uint256 public availableAssets;
    /**
     * @dev current withdrawal cycle. Used to process batch of pending redeem requests.
     */
    uint256 public currentWithdrawalIndex;
    /**
     * @dev last withdrawal cycle, where all redeem requests were fulfilled
     */
    uint256 public lastFulfilledWithdrawalIndex;
    // TODO: pack all together
    /**
     * @dev total amount of shares redeemed by users in particular withdrawal cycle
     */
    mapping(uint256 => uint256) public withdrawalIndexToRedeemedShares;
    mapping(uint256 => bool) public withdrawalIndexToInitiated;
    mapping(uint256 => uint256) public withdrawalIndexToWithdrawnAssets;

    mapping(uint256 => mapping(address => uint256)) public withdrawalIndexToSmartVaultToWithdrawalNftId;
    /**
     * @dev amount of shares user redeemed in specific withdrawal cycle
     */
    mapping(address => mapping(uint256 => uint256)) public userToWithdrawalIndexToRedeemedShares;

    // ========================== CONSTRUCTOR ==========================

    constructor(
        ISmartVaultManager smartVaultManager_,
        IERC20MetadataUpgradeable asset_,
        ISpoolAccessControl spoolAccessControl_,
        IAssetGroupRegistry assetGroupRegistry_
    ) SpoolAccessControllable(spoolAccessControl_) {
        smartVaultManager = smartVaultManager_;
        asset = asset_;
        _decimals = uint8(asset.decimals());
        assetGroupRegistry = assetGroupRegistry_;
    }

    // ========================== INITIALIZER ==========================

    function initialize(string memory name_, string memory symbol_) external initializer {
        __Ownable2Step_init();
        __Multicall_init();
        __ERC20_init(name_, symbol_);
        asset.approve(address(smartVaultManager), type(uint256).max);
        currentWithdrawalIndex = 1;
    }

    // ==================== SMART VAULTS MANAGEMENT ====================

    function getSmartVaults() external view returns (address[] memory) {
        return _smartVaults.list;
    }

    function smartVaultSupported(address vault) external view returns (bool) {
        return _smartVaults.includes[vault];
    }

    function smartVaultIsValid(address vault) external view returns (bool) {
        return _validateSmartVault(vault);
    }

    function addSmartVaults(address[] calldata vaults, uint256[] calldata allocations) external onlyOwner {
        for (uint256 i; i < vaults.length; i++) {
            _validateSmartVault(vaults[i]);
        }
        _smartVaults.addList(vaults);
        _setSmartVaultAllocations(allocations);
    }

    function removeSmartVaults(address[] calldata vaults) external onlyOwner {
        /// vault can be removed from managed list only when
        // there are no pending deposits / withdrawals and its allocation was set to zero
        for (uint256 i; i < vaults.length; i++) {
            if (_smartVaultToDepositNftIds[vaults[i]].list.length > 0) revert PendingDeposits();
            if (_smartVaultToWithdrawalNftIds[vaults[i]].list.length > 0) revert PendingWithdrawals();
            if (smartVaultToAllocation[vaults[i]] > 0) revert NonZeroAllocation();
        }
        _smartVaults.removeList(vaults);
    }

    function _validateSmartVault(address vault) internal view returns (bool) {
        SmartVaultFees memory fees = smartVaultManager.getSmartVaultFees(vault);
        if (fees.managementFeePct > 0) revert InvalidVaultManagementFee();
        if (fees.depositFeePct > 0) revert InvalidVaultDepositFee();
        address[] memory vaultAssets = assetGroupRegistry.listAssetGroup(smartVaultManager.assetGroupId(vault));
        if (vaultAssets.length != 1 || vaultAssets[0] != address(asset)) revert InvalidVaultAsset();
        return true;
    }

    function getSmartVaultDepositNftIds(address smartVault) external view returns (uint256[] memory) {
        return _smartVaultToDepositNftIds[smartVault].list;
    }

    function getSmartVaultWithdrawalNftIds(address smartVault) external view returns (uint256[] memory) {
        return _smartVaultToWithdrawalNftIds[smartVault].list;
    }

    function setSmartVaultAllocations(uint256[] calldata allocations) external onlyOwner {
        _setSmartVaultAllocations(allocations);
    }

    function _setSmartVaultAllocations(uint256[] calldata allocations) internal {
        if (allocations.length != _smartVaults.list.length) revert ArgumentLengthMismatch();
        uint256 sum;
        for (uint256 i; i < allocations.length; i++) {
            sum += allocations[i];
            smartVaultToAllocation[_smartVaults.list[i]] = allocations[i];
        }
        if (sum != 100_00) revert WrongAllocation();
    }

    // ========================== USER FACING ==========================

    /**
     * @dev deposit asset into MetaVault
     * @param amount of asset
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
        /// accumulate redeems for all users for current withdrawal cycle
        withdrawalIndexToRedeemedShares[index] += shares;
        /// accumulate redeems for particular user for current withdrawal cycle
        userToWithdrawalIndexToRedeemedShares[msg.sender][index] += shares;
        emit RedeemRequest(msg.sender, index, shares);
    }

    /**
     * @dev user can withdraw assets once his request with specific withdrawal index is fulfilled
     * @param index of withdrawal cycle
     */
    function withdraw(uint256 index) external returns (uint256 amount) {
        /// user can withdraw funds only for fulfilled withdrawal cycle
        if (lastFulfilledWithdrawalIndex < index) revert RedeemRequestNotFulfilled();
        /// amount of funds user get from specified withdrawal cycle
        amount = userToWithdrawalIndexToRedeemedShares[msg.sender][index] * withdrawalIndexToWithdrawnAssets[index]
            / withdrawalIndexToRedeemedShares[index];
        if (amount == 0) revert NothingToWithdraw();
        /// delete entry for user to disable repeated withdrawal
        delete userToWithdrawalIndexToRedeemedShares[msg.sender][index];
        asset.safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, index, amount);
    }

    // ========================== SPOOL INTERACTIONS ==========================

    function flush() external {
        _redeem();
        _deposit();
    }

    function flushFast(uint256[][][] calldata slippages) external onlyRole(ROLE_DO_HARD_WORKER, msg.sender) {
        _redeemFast(slippages);
        _deposit();
    }

    function sync() external {
        // claim SVTs
        address[] memory vaults = _smartVaults.list;
        for (uint256 i; i < vaults.length; i++) {
            _spoolClaimSmartVaultTokens(vaults[i]);
        }
        // finalize withdrawal
        while (lastFulfilledWithdrawalIndex < currentWithdrawalIndex - 1) {
            uint256 index = lastFulfilledWithdrawalIndex + 1;
            /// aggregate withdrawn assets from all smart vaults
            uint256 withdrawnAssets;
            for (uint256 i; i < vaults.length; i++) {
                uint256 nftId = withdrawalIndexToSmartVaultToWithdrawalNftId[index][vaults[i]];
                if (nftId > 0) {
                    /// aggregate withdrawn assets from all smart vaults
                    withdrawnAssets += _spoolClaimWithdrawal(vaults[i], nftId);
                    _smartVaultToWithdrawalNftIds[vaults[i]].remove(nftId);
                    withdrawalIndexToSmartVaultToWithdrawalNftId[index][vaults[i]] = 0;
                }
            }
            /// we fulfill last unprocessed withdrawal cycle
            withdrawalIndexToWithdrawnAssets[index] = withdrawnAssets;
            lastFulfilledWithdrawalIndex = index;
        }
    }

    function reallocate(uint256[][][] calldata slippages) external onlyRole(ROLE_DO_HARD_WORKER, msg.sender) {
        // total amount of assets withdrawn during the reallocation
        uint256 withdrawnAssets;
        // total equivalent of MetaVault shares for deposits
        uint256 sharesToDepositTotal;
        // cache
        address[] memory vaults = _smartVaults.list;
        // track required deposits for vaults
        uint256[] memory sharesToDeposit = new uint256[](vaults.length);
        for (uint256 i; i < vaults.length; i++) {
            // claim all SVTs first
            _spoolClaimSmartVaultTokens(vaults[i]);

            uint256 currentSharesDeposited = smartVaultToDepositedShares[vaults[i]];
            // calculate the amount of MetaVault shares which should be allocated to that vault
            uint256 desiredSharesDeposited = smartVaultToAllocation[vaults[i]] * depositedSharesTotal / 100_00;
            // if more MetaVault shares should be deposited we save this data for later
            if (desiredSharesDeposited > currentSharesDeposited) {
                uint256 shareDif = desiredSharesDeposited - currentSharesDeposited;
                sharesToDeposit[i] = shareDif;
                sharesToDepositTotal += shareDif;
                // if amount of MetaVault shares should be reduced we perform redeemFast
            } else if (desiredSharesDeposited < currentSharesDeposited) {
                uint256 shareDif = currentSharesDeposited - desiredSharesDeposited;
                // previously all SVTs shares were claimed, so we can calculate the proportion of SVTs to be withdrawn
                // using MetaVault deposited shares ratio
                uint256 svtsToRedeem = shareDif * ISmartVault(vaults[i]).balanceOf(address(this)) / depositedSharesTotal;
                smartVaultToDepositedShares[vaults[i]] -= shareDif;
                withdrawnAssets += _spoolRedeemFast(vaults[i], svtsToRedeem, slippages[i]);
            }
        }

        // now we will perform deposits
        {
            // due to rounding errors newTotalShares can differ from depositedSharesTotal
            uint256 newTotalShares;
            for (uint256 i; i < vaults.length; i++) {
                // only if there are "MetaVault shares to deposit"
                if (sharesToDeposit[i] > 0) {
                    // calculate amount of assets based on MetaVault shares ratio
                    uint256 amount = sharesToDeposit[i] * withdrawnAssets / sharesToDepositTotal;
                    smartVaultToDepositedShares[vaults[i]] += sharesToDeposit[i];
                    _spoolDeposit(vaults[i], amount);
                }
                newTotalShares += smartVaultToDepositedShares[vaults[i]];
            }
            // we want to keep depositedSharesTotal and sum of smartVaultToDepositedShares in sync
            if (newTotalShares < depositedSharesTotal) {
                // assign the dust to first smart vault
                smartVaultToDepositedShares[vaults[0]] += depositedSharesTotal - newTotalShares;
            } else if (newTotalShares > depositedSharesTotal) {
                smartVaultToDepositedShares[vaults[0]] -= newTotalShares - depositedSharesTotal;
            }
        }
    }

    function _deposit() internal {
        if (availableAssets > 0) {
            uint256 totalDeposited;
            address[] memory vaults = _smartVaults.list;
            for (uint256 i; i < vaults.length; i++) {
                uint256 amountToDeposit;
                // handle dust so that available assets would go to 0
                if (i == vaults.length - 1) {
                    amountToDeposit = availableAssets - totalDeposited;
                } else {
                    amountToDeposit = availableAssets * smartVaultToAllocation[vaults[i]] / 100_00;
                }
                totalDeposited += amountToDeposit;
                smartVaultToDepositedShares[vaults[i]] += amountToDeposit;
                _spoolDeposit(vaults[i], amountToDeposit);
            }
            availableAssets = 0;
            depositedSharesTotal += totalDeposited;
        }
    }

    /**
     * @dev redeem all shares from last unfulfilled withdrawal cycle
     */
    function _redeem() internal {
        if (depositedSharesTotal > 0) {
            for (uint256 index = lastFulfilledWithdrawalIndex + 1; index <= currentWithdrawalIndex; index++) {
                uint256 shares = withdrawalIndexToRedeemedShares[index];
                if (shares == 0) return;
                if (!withdrawalIndexToInitiated[index]) {
                    address[] memory smartVaults = _smartVaults.list;
                    for (uint256 i; i < smartVaults.length; i++) {
                        // claim all SVTs first
                        _spoolClaimSmartVaultTokens(smartVaults[i]);
                        uint256 SVTBalance = ISmartVault(smartVaults[i]).balanceOf(address(this));
                        uint256 SVTToRedeem = SVTBalance * shares / depositedSharesTotal;
                        withdrawalIndexToSmartVaultToWithdrawalNftId[index][smartVaults[i]] =
                            _spoolRedeem(smartVaults[i], SVTToRedeem);
                    }
                    depositedSharesTotal -= shares;
                    currentWithdrawalIndex++;
                    withdrawalIndexToInitiated[index] = true;
                }
            }
        }
    }

    function _redeemFast(uint256[][][] calldata slippages) internal {
        while (true) {
            uint256 index = lastFulfilledWithdrawalIndex + 1;
            if (index > currentWithdrawalIndex) return;
            uint256 shares = withdrawalIndexToRedeemedShares[index];
            if (shares > 0 && !withdrawalIndexToInitiated[index]) {
                /// aggregate withdrawn assets from all smart vaults
                uint256 withdrawnAssets;
                address[] memory smartVaults = _smartVaults.list;
                for (uint256 i; i < smartVaults.length; i++) {
                    // claim all SVTs first
                    _spoolClaimSmartVaultTokens(smartVaults[i]);
                    uint256 SVTBalance = ISmartVault(smartVaults[i]).balanceOf(address(this));
                    // due to rounding error users can receive slightly less
                    uint256 SVTToRedeem = SVTBalance * shares / depositedSharesTotal;
                    withdrawnAssets += _spoolRedeemFast(smartVaults[i], SVTToRedeem, slippages[i]);
                }
                depositedSharesTotal -= shares;
                lastFulfilledWithdrawalIndex++;
                withdrawalIndexToWithdrawnAssets[lastFulfilledWithdrawalIndex] = withdrawnAssets;
                currentWithdrawalIndex++;
                return;
            }
        }
    }

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

    function _spoolRedeem(address smartVault, uint256 shares) internal returns (uint256 nftId) {
        RedeemBag memory bag =
            RedeemBag({smartVault: smartVault, shares: shares, nftIds: new uint256[](0), nftAmounts: new uint256[](0)});
        nftId = smartVaultManager.redeem(bag, address(this), false);
    }

    function _spoolRedeemFast(address smartVault, uint256 shares, uint256[][] calldata slippages)
        internal
        returns (uint256 amount)
    {
        RedeemBag memory bag =
            RedeemBag({smartVault: smartVault, shares: shares, nftIds: new uint256[](0), nftAmounts: new uint256[](0)});
        amount = smartVaultManager.redeemFast(bag, slippages)[0];
    }

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

    function onERC1155Received(address, address from, uint256 id, uint256, bytes calldata)
        external
        validateToken(from)
        returns (bytes4)
    {
        _handleReceive(id);
        /// bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))
        return 0xf23a6e61;
    }

    function onERC1155BatchReceived(address, address from, uint256[] calldata ids, uint256[] calldata, bytes calldata)
        external
        validateToken(from)
        returns (bytes4)
    {
        for (uint256 i; i < ids.length; i++) {
            _handleReceive(ids[i]);
        }
        /// bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))
        return 0xbc197c81;
    }

    modifier validateToken(address from) {
        if (!_smartVaults.includes[msg.sender]) revert TokenNotSupported();
        if (from != address(0)) revert NftTransferForbidden();
        _;
    }

    function _handleReceive(uint256 id) internal {
        if (id > MAXIMAL_DEPOSIT_ID) {
            _smartVaultToWithdrawalNftIds[msg.sender].add(id);
        } else {
            _smartVaultToDepositNftIds[msg.sender].add(id);
        }
    }
}
