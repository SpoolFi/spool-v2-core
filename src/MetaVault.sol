/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC1155/utils/ERC1155ReceiverUpgradeable.sol";
import "@openzeppelin-upgradeable/utils/MulticallUpgradeable.sol";

import "./managers/SmartVaultManager.sol";
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
/// TODO: implement delegates? Owner would be able to assign delegates who will be allowed to call deposit, redeem, redeemFast, claimSmartVaultTokens and claimWithdrawal
/// Why does it matter? Delegate could be a hot wallet of some backend service to perform those operations.
/// Doesn't look like there is a risk of loosing funds even in case this how wallet will be compromised
contract MetaVault is Ownable2StepUpgradeable, ERC20Upgradeable, ERC1155ReceiverUpgradeable, MulticallUpgradeable {
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
    using ListMap for ListMap.Address;
    using ListMap for ListMap.Uint256;

    // ========================== EVENTS ==========================
    event Deposit(address indexed user, uint256 amount);
    event RedeemRequest(address indexed user, uint256 indexed withdrawalCycle, uint256 shares);
    event Withdraw(address indexed user, uint256 indexed withdrawalCycle, uint256 amount);

    // ========================== ERRORS ==========================
    error PendingDeposits();
    error PendingWithdrawals();
    error UnsupportedSmartVault();
    error NothingToClaim(uint256 nftId);
    error NothingToWithdraw();
    error NothingToFulfill(uint256 nftId);
    error NftTransferForbidden();
    error TokenNotSupported();

    /**
     * @dev deposit into Spool is prohibited if there are pending redeem requests to fulfill
     */
    error PendingRedeemRequests();
    /**
     * @dev user is not allowed to withdraw asset until his redeem request is not fulfilled
     */
    error RedeemRequestNotFulfilled();
    /**
     * @dev lastWithdrawalIndexed cannot be greater than currentWithdrawalIndex
     */
    error LastWithdrawalIndexOutbound();

    // ========================== IMMUTABLES ==========================

    /**
     * @dev SmartVaultManager contract. Gateway to Spool protocol
     */
    SmartVaultManager public immutable smartVaultManager;
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
    /**
     * @dev total amount of shares redeemed by users in particular withdrawal cycle
     */
    mapping(uint256 => uint256) public withdrawalIndexToRedeemedShares;
    mapping(uint256 => uint256) public withdrawalIndexToWithdrawnAssets;

    mapping(uint256 => mapping(address => uint256)) public withdrawalIndexToSmartVaultToWithdrawalNftId;
    /**
     * @dev amount of shares user redeemed in specific withdrawal cycle
     */
    mapping(address => mapping(uint256 => uint256)) public userToWithdrawalIndexToRedeemedShares;

    // ========================== CONSTRUCTOR ==========================

    constructor(address smartVaultManager_, address asset_) {
        smartVaultManager = SmartVaultManager(smartVaultManager_);
        asset = IERC20MetadataUpgradeable(asset_);
        _decimals = uint8(asset.decimals());
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

    function smartVaultIsValid(address vault) external pure returns (bool) {
        return _validateSmartVault(vault);
    }

    function addSmartVaults(address[] calldata vaults) external onlyOwner {
        for (uint256 i; i < vaults.length; i++) {
            _validateSmartVault(vaults[i]);
        }
        _smartVaults.addList(vaults);
    }

    function removeSmartVaults(address[] calldata vaults) external onlyOwner {
        /// vault can be removed from managed list only when there are no pending deposits and withdrawals
        for (uint256 i; i < vaults.length; i++) {
            if (_smartVaultToDepositNftIds[vaults[i]].list.length > 0) revert PendingDeposits();
            if (_smartVaultToWithdrawalNftIds[vaults[i]].list.length > 0) revert PendingWithdrawals();
        }
        _smartVaults.removeList(vaults);
    }

    function _validateSmartVault(address) internal pure returns (bool) {
        // TODO: add validation of smart vaults
        // only performance fee + matching underlying asset
        return true;
    }

    function getSmartVaultDepositNftIds(address smartVault) external view returns (uint256[] memory) {
        return _smartVaultToDepositNftIds[smartVault].list;
    }

    function getSmartVaultWithdrawalNftIds(address smartVault) external view returns (uint256[] memory) {
        return _smartVaultToWithdrawalNftIds[smartVault].list;
    }

    // ========================== USER FACING ==========================

    /**
     * @dev deposit asset into MetaVault
     * @param amount of asset
     */
    function deposit(uint256 amount) external {
        /// MetaVault has now more funds to manage
        availableAssets += amount;
        _mint(msg.sender, amount);
        asset.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, amount);
    }

    /**
     * @dev create a redeem request to get assets back
     * @param shares of MetaVault to burn
     */
    function redeemRequest(uint256 shares) external {
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

    // ========================== WITHDRAWAL MANAGEMENT ==========================

    /**
     * @dev redeem all shares from last unfulfilled withdrawal cycle
     */
    function initiateWithdrawal() external onlyOwner {
        uint256 index = lastFulfilledWithdrawalIndex + 1;
        uint256 shares = withdrawalIndexToRedeemedShares[index];
        address[] memory smartVaults = _smartVaults.list;
        for (uint256 i; i < smartVaults.length; i++) {
            // all deposits should be DHWed and SVTs are claimed
            if (_smartVaultToDepositNftIds[smartVaults[i]].list.length > 0) revert PendingDeposits();
            uint256 SVTBalance = ISmartVault(smartVaults[i]).balanceOf(address(this));
            // due to rounding error users can receive slightly less
            uint256 SVTToRedeem = SVTBalance * shares / depositedSharesTotal;
            RedeemBag memory bag = RedeemBag({
                smartVault: smartVaults[i],
                shares: SVTToRedeem,
                nftIds: new uint256[](0),
                nftAmounts: new uint256[](0)
            });
            withdrawalIndexToSmartVaultToWithdrawalNftId[index][smartVaults[i]] =
                smartVaultManager.redeem(bag, address(this), false);
        }
        depositedSharesTotal -= shares;
        currentWithdrawalIndex++;
    }

    /**
     * @dev fulfill redeem requests for last unfulfilled withdrawal cycle
     */
    // TODO: can anybody call this?
    function finalizeWithdrawal() external {
        /// we fulfill last unprocessed withdrawal cycle
        lastFulfilledWithdrawalIndex++;
        uint256 index = lastFulfilledWithdrawalIndex;
        /// it is not allowed for lastFulfilledWithdrawalIndex to exceed currentWithdrawalIndex and in this way skip deposit block
        if (index > currentWithdrawalIndex) revert LastWithdrawalIndexOutbound();
        address[] memory vaults = _smartVaults.list;
        /// aggregate withdrawn assets from all smart vaults
        uint256 withdrawnAssets;
        for (uint256 i; i < vaults.length; i++) {
            uint256[] memory nftIds = new uint256[](1);
            nftIds[0] = withdrawalIndexToSmartVaultToWithdrawalNftId[index][vaults[i]];
            uint256[] memory nftAmounts = new uint256[](1);
            nftAmounts[0] = ISmartVault(vaults[i]).balanceOfFractional(address(this), nftIds[0]);
            if (nftAmounts[0] == 0) revert NothingToFulfill(nftIds[0]);
            (uint256[] memory withdrawn,) =
                smartVaultManager.claimWithdrawal(vaults[i], nftIds, nftAmounts, address(this));
            /// aggregate withdrawn assets from all smart vaults
            withdrawnAssets += withdrawn[0];
            _smartVaultToWithdrawalNftIds[vaults[i]].remove(nftIds[0]);
        }
        withdrawalIndexToWithdrawnAssets[index] = withdrawnAssets;
    }

    // ========================== SPOOL INTERACTIONS ==========================

    function spoolDeposit(address vault, uint256 amount, bool doFlush) external onlyOwner returns (uint256 nftId) {
        /// deposits are only possible for managed smart vaults
        if (!_smartVaults.includes[vault]) revert UnsupportedSmartVault();
        if (
            /// if more than one withdrawal cycle is not fulfilled
            lastFulfilledWithdrawalIndex + 1 < currentWithdrawalIndex
            /// or there is only one unfulfilled withdrawal cycle
            /// and there are some funds requested in it
            || (
                lastFulfilledWithdrawalIndex + 1 == currentWithdrawalIndex
                    && withdrawalIndexToRedeemedShares[currentWithdrawalIndex] > 0
                // we should not block deposit if not enough assets were already deposited
                && withdrawalIndexToRedeemedShares[currentWithdrawalIndex] < depositedSharesTotal
            )
        ) {
            /// we block any deposit to push SmartVault owner to fulfill requested redeems
            revert PendingRedeemRequests();
        }

        availableAssets -= amount;

        uint256[] memory assets = new uint256[](1);
        assets[0] = amount;
        DepositBag memory bag = DepositBag({
            smartVault: vault,
            assets: assets,
            receiver: address(this),
            doFlush: doFlush,
            referral: address(0)
        });

        nftId = smartVaultManager.deposit(bag);

        depositedSharesTotal += amount;
    }

    function spoolClaimSmartVaultTokens(address vault, uint256[] calldata nftIds) external returns (uint256 amount) {
        // will revert if some nftId is missing
        _smartVaultToDepositNftIds[vault].removeList(nftIds);

        uint256[] memory nftAmounts = new uint256[](nftIds.length);

        for (uint256 i; i < nftIds.length; i++) {
            nftAmounts[i] = ISmartVault(vault).balanceOfFractional(address(this), nftIds[i]);
            // make sure there is actual balance for given nft id
            if (nftAmounts[i] == 0) revert NothingToClaim(nftIds[i]);
        }

        amount = smartVaultManager.claimSmartVaultTokens(vault, nftIds, nftAmounts);
    }

    //
    function spoolRedeem(RedeemBag calldata bag, bool doFlush) external onlyOwner returns (uint256) {
        // TODO: make sure balance of nftId is max and after redeem is nothing left
        return smartVaultManager.redeem(bag, address(this), doFlush);
    }

    function spoolRedeemFast(RedeemBag calldata bag, uint256[][] calldata withdrawalSlippages)
        external
        onlyOwner
        returns (uint256)
    {
        // TODO: make sure balance of nftId is max and after redeem is nothing left
        uint256 withdrawnAssets = smartVaultManager.redeemFast(bag, withdrawalSlippages)[0];
        availableAssets += withdrawnAssets;
        if (bag.nftIds.length > 0) {
            _smartVaultToDepositNftIds[bag.smartVault].removeList(bag.nftIds);
        }
        return withdrawnAssets;
    }

    function spoolClaimWithdrawal(address smartVault, uint256[] calldata nftIds, uint256[] calldata nftAmounts)
        external
        onlyOwner
        returns (uint256)
    {
        // TODO: make sure balance of nftId is max and after redeem is nothing left
        _smartVaultToWithdrawalNftIds[smartVault].removeList(nftIds);
        (uint256[] memory withdrawn,) = smartVaultManager.claimWithdrawal(smartVault, nftIds, nftAmounts, address(this));
        uint256 withdrawnAssets = withdrawn[0];
        availableAssets += withdrawnAssets;
        return withdrawnAssets;
    }

    // ========================== ERC-20 OVERRIDES ==========================

    /// TODO: override transfer? We had a discussion to simplify points calculations => prohibit shares transfer

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
