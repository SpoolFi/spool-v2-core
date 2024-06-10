/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC1155/utils/ERC1155ReceiverUpgradeable.sol";
import "@openzeppelin-upgradeable/utils/MulticallUpgradeable.sol";

import "./managers/SmartVaultManager.sol";

/**
 * @dev MetaVault is a contract which facilitates investment in various SmartVaults.
 * It has an owner, which is responsible for calling Spool Core V2 specific methods:
 * deposit, redeem, redeemFast, claimSmartVaultTokens and claimWithdrawal.
 * In this way MetaVault owner can manage funds from users in trustless manner.
 * MetaVault supports only one ERC-20 asset.
 * Users can deposit funds and in return they get MetaVault shares.
 * To redeem users are required to burn they MetaVault shares, while creating redeem request,
 * which is processed in asynchronous manner.
 * Redeem requests can always be matched with availableAssets in smart contract and become withdrawable.
 * While there are some pending redeem requests, deposits into Spool protocol are prohibited.
 */
/// TODO: implement delegates? Owner would be able to assign delegates who will be allowed to call deposit, redeem, redeemFast, claimSmartVaultTokens and claimWithdrawal
/// Why does it matter? Delegate could be a hot wallet of some backend service to perform those operations.
/// Doesn't look like there is a risk of loosing funds even in case this how wallet will be compromised
contract MetaVault is Ownable2StepUpgradeable, ERC20Upgradeable, ERC1155ReceiverUpgradeable, MulticallUpgradeable {
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;

    // ========================== EVENTS ==========================
    event Deposit(address indexed user, uint256 amount);
    event RedeemRequest(address indexed user, uint256 indexed withdrawalCycle, uint256 shares);
    event Withdraw(address indexed user, uint256 indexed withdrawalCycle, uint256 amount);

    // ========================== ERRORS ==========================
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

    /**
     * @dev all assets available for management by MetaVault.
     * MetVault asset balance can be greater than availableAssets, since funds for withdrawals
     * are not included into it.
     */
    uint256 public availableAssets;
    /**
     * @dev current withdrawal cycle. Used to process batch of pending redeem requests of users
     */
    uint256 public currentWithdrawalIndex;
    /**
     * @dev last withdrawal cycle, where all redeem requests were fulfilled for users with corresponding withdrawal index
     */
    uint256 public lastFulfilledWithdrawalIndex;
    /**
     * @dev total amount of assets requested by all users for particular withdrawal index
     */
    mapping(uint256 => uint256) public withdrawalIndexToRequestedAmount;
    /**
     * @dev amount of assets user requested in specific withdrawal cycle
     */
    mapping(address => mapping(uint256 => uint256)) public userToWithdrawalIndexToRequestedAmount;

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
        currentWithdrawalIndex = 1;
        asset.safeApprove(address(smartVaultManager), type(uint256).max);
    }

    // ========================== USER FACING ==========================

    /// TODO: assume for now that price is constant
    /// Remove this completely or implement some kind of pricing?
    /// In case of none yield-bearing MetaVault it does make sense only in case of real loss
    /// otherwise 1:1 is perfectly fine
    function convertToAssets(uint256 amount) public pure returns (uint256) {
        return amount;
    }

    function convertToShares(uint256 amount) public pure returns (uint256) {
        return amount;
    }

    /**
     * @dev deposit asset into MetaVault
     * @param amount of asset
     * @return shares minted to user
     */
    function deposit(uint256 amount) external returns (uint256 shares) {
        /// MetaVault has now more funds to manage
        availableAssets += amount;
        shares = convertToShares(amount);
        _mint(msg.sender, shares);
        asset.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, amount);
    }

    /**
     * @dev create a redeem request to get assets back
     * @param shares of MetaVault to burn
     */
    function redeemRequest(uint256 shares) external {
        _burn(msg.sender, shares);
        /// TODO: always subtract 1 wei from assets to return?
        /// would allow to avoid inconsistency on withdrawal and pumpAssets() might be omitted completely
        uint256 assetsToWithdraw = convertToAssets(shares);
        /// accumulate redeems for all users for current withdrawal cycle
        withdrawalIndexToRequestedAmount[currentWithdrawalIndex] += assetsToWithdraw;
        /// accumulate redeems for particular user for current withdrawal cycle
        userToWithdrawalIndexToRequestedAmount[msg.sender][currentWithdrawalIndex] += assetsToWithdraw;
        emit RedeemRequest(msg.sender, currentWithdrawalIndex, shares);
    }

    /**
     * @dev user can withdraw assets once his request with specific withdrawal index is fulfilled
     * @param index of withdrawal cycle
     */
    function withdraw(uint256 index) external returns (uint256 amount) {
        /// user can withdraw funds only for fulfilled withdrawal cycle
        if (lastFulfilledWithdrawalIndex < index) revert RedeemRequestNotFulfilled();
        /// amount of funds user get from specified withdrawal cycle
        amount = userToWithdrawalIndexToRequestedAmount[msg.sender][index];
        /// delete entry for user to disable repeated withdrawal
        delete userToWithdrawalIndexToRequestedAmount[msg.sender][index];
        asset.safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, index, amount);
    }

    // ========================== WITHDRAWAL MANAGEMENT ==========================

    /**
     * @dev owner of SmartVault fulfills all redeem requests for last unfulfilled withdrawal cycle
     * Aggregated amount for all requests will be excluded from availableAssets
     */
    function fulfillWithdraw() external onlyOwner {
        /// we fulfill last unprocessed withdrawal cycle
        lastFulfilledWithdrawalIndex++;
        /// it is not allowed for lastFulfilledWithdrawalIndex to exceed currentWithdrawalIndex
        /// and in this way avoid deposit block
        if (lastFulfilledWithdrawalIndex > currentWithdrawalIndex) revert LastWithdrawalIndexOutbound();
        /// automatically increment currentWithdrawalIndex
        if (lastFulfilledWithdrawalIndex == currentWithdrawalIndex) {
            incrementWithdrawalIndex();
        }
        /// Aggregated amount for all requests will be excluded from availableAssets
        availableAssets -= withdrawalIndexToRequestedAmount[lastFulfilledWithdrawalIndex];
    }

    /**
     * @dev owner of SmartVault should call this before processing the batch of redeem requests.
     * Otherwise it could lead to situation, where users will wait indefinite amount of time, if new redeem requests are created
     */
    function incrementWithdrawalIndex() public onlyOwner {
        currentWithdrawalIndex++;
    }

    /// TODO: could implement something like that to fix small inconsistencies
    /// If we use 1:1 pricing strategy and expect really small discrepancies in amount of underlying asset
    /// which will be get back by burning SVTs, it might be appropriate to use this tiny hack
    function pumpAssets(uint256 amount) external onlyOwner {
        availableAssets += amount;
        asset.safeTransferFrom(msg.sender, address(this), amount);
    }

    // ========================== SPOOL INTERACTIONS ==========================

    /// TODO: Somehow validate that SmartVault is not yield bearing? - all yield goes to Spool and SmartVault owner.
    /// Probably, there is no need for this. Because even if some yield goes to MetaVault it wouldn't matter.
    /// MetaVault should not be yield-bearing for user.
    function spoolDeposit(address smartVault, uint256 amount, bool doFlush) external onlyOwner returns (uint256) {
        if (
            /// if more than one withdrawal cycle is not fulfilled
            lastFulfilledWithdrawalIndex + 1 < currentWithdrawalIndex
            /// or there is only one unfulfilled withdrawal cycle
            /// and there are some funds requested in it
            || (
                lastFulfilledWithdrawalIndex + 1 == currentWithdrawalIndex
                    && withdrawalIndexToRequestedAmount[currentWithdrawalIndex] > 0
            )
        ) {
            /// we block any deposit to push SmartVault owner to fulfill requested redeems
            revert PendingRedeemRequests();
        }
        availableAssets -= amount;

        uint256[] memory assets = new uint256[](1);
        assets[0] = amount;
        DepositBag memory bag = DepositBag({
            smartVault: smartVault,
            assets: assets,
            receiver: address(this),
            doFlush: doFlush,
            referral: address(0)
        });

        return smartVaultManager.deposit(bag);
    }

    function claimSmartVaultTokens(address smartVault, uint256[] calldata nftIds, uint256[] calldata nftAmounts)
        external
        onlyOwner
        returns (uint256)
    {
        return smartVaultManager.claimSmartVaultTokens(smartVault, nftIds, nftAmounts);
    }

    function spoolRedeem(RedeemBag calldata bag, bool doFlush) external onlyOwner returns (uint256) {
        return smartVaultManager.redeem(bag, address(this), doFlush);
    }

    function spoolRedeemFast(RedeemBag calldata bag, uint256[][] calldata withdrawalSlippages)
        external
        onlyOwner
        returns (uint256)
    {
        uint256 withdrawnAssets = smartVaultManager.redeemFast(bag, withdrawalSlippages)[0];
        availableAssets += withdrawnAssets;
        return withdrawnAssets;
    }

    function spoolClaimWithdrawal(address smartVault, uint256[] calldata nftIds, uint256[] calldata nftAmounts)
        external
        onlyOwner
        returns (uint256)
    {
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

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        /// bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))
        return 0xf23a6e61;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        /// bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))
        return 0xbc197c81;
    }
}
