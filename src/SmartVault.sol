// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "./interfaces/ISmartVault.sol";
import "./interfaces/IGuardManager.sol";
import "./interfaces/IRiskManager.sol";
import "./interfaces/IStrategyRegistry.sol";
import "./interfaces/IAction.sol";

contract SmartVault is ERC1155Upgradeable, ERC20Upgradeable, ISmartVault {
    using SafeERC20 for ERC20;

    /* ========== STATE VARIABLES ========== */

    // @notice Guard manager
    IGuardManager internal immutable guardManager;

    // @notice Action manager
    IActionManager internal immutable actionManager;

    // @notice Strategy manager
    IStrategyRegistry internal immutable StrategyRegistry;

    // @notice Risk manager
    IRiskManager internal immutable riskManager;

    // @notice Asset group address array
    address[] internal _assetGroup;

    // @notice Vault name
    string internal _vaultName;

    // @notice Mapping from token ID => owner address
    mapping(uint256 => address) private _nftOwners;

    // @notice Deposit metadata registry
    mapping(uint256 => DepositMetadata) private _depositMetadata;

    // @notice Withdrawal metadata registry
    mapping(uint256 => WithdrawalMetadata) private _withdrawalMetadata;

    // @notice Deposit NFT ID
    uint256 private _maxDepositID = 0;

    // @notice Withdrawal NFT ID
    uint256 private _maxWithdrawalID = 2 ** 256 / 2;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Initializes variables
     * @param vaultName_ TODO
     * @param assets_ TODO
     * @param guardManager_ TODO
     * @param actionManager_ TODO
     * @param StrategyRegistry_ TODO
     * @param riskManager_ TODO
     */
    constructor(
        string memory vaultName_,
        address[] memory assets_,
        IGuardManager guardManager_,
        IActionManager actionManager_,
        IStrategyRegistry StrategyRegistry_,
        IRiskManager riskManager_
    ) {
        _vaultName = vaultName_;
        _assetGroup = assets_;
        guardManager = guardManager_;
        actionManager = actionManager_;
        StrategyRegistry = StrategyRegistry_;
        riskManager = riskManager_;
    }

    function initialize() external initializer {
        __ERC1155_init("");
        __ERC20_init("", "");
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @return name Name of the vault
     */
    function vaultName() external view returns (string memory) {
        return _vaultName;
    }

    /**
     * @notice TODO
     * @return isTransferable TODO
     */
    function isShareTokenTransferable() external view returns (bool) {
        revert("0");
    }

    /**
     * @dev Returns the maximum amount of the underlying asset that can be deposited into the Vault for the receiver,
     * through a deposit call.
     * @param receiver TODO
     *
     * - MUST return a limited value if receiver is subject to some deposit limit.
     * - MUST return 2 ** 256 - 1 if there is no limit on the maximum amount of assets that may be deposited.
     * - MUST NOT revert.
     */
    function maxDeposit(address receiver) external view returns (uint256[] memory) {
        revert("0");
    }

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their deposit at the current block, given
     * current on-chain conditions.
     * @param assets TODO
     *
     * - MUST return as close to and no more than the exact amount of Vault shares that would be minted in a deposit
     *   call in the same transaction. I.e. deposit should return the same or more shares as previewDeposit if called
     *   in the same transaction.
     * - MUST NOT account for deposit limits like those returned from maxDeposit and should always act as though the
     *   deposit would be accepted, regardless if the user has enough tokens approved, etc.
     * - MUST be inclusive of deposit fees. Integrators should be aware of the existence of deposit fees.
     * - MUST NOT revert.
     *
     * NOTE: any unfavorable discrepancy between convertToShares and previewDeposit SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by depositing.
     */
    function previewDeposit(uint256[] calldata assets) external view returns (uint256) {
        revert("0");
    }

    /**
     * @dev Returns the maximum amount of the Vault shares that can be minted for the receiver, through a mint call.
     * @param receiver TODO
     * - MUST return a limited value if receiver is subject to some mint limit.
     * - MUST return 2 ** 256 - 1 if there is no limit on the maximum amount of shares that may be minted.
     * - MUST NOT revert.
     */
    function maxMint(address receiver) external view returns (uint256) {
        revert("0");
    }

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their mint at the current block, given
     * @param shares TODO
     * current on-chain conditions.
     *
     * - MUST return as close to and no fewer than the exact amount of assets that would be deposited in a mint call
     *   in the same transaction. I.e. mint should return the same or fewer assets as previewMint if called in the
     *   same transaction.
     * - MUST NOT account for mint limits like those returned from maxMint and should always act as though the mint
     *   would be accepted, regardless if the user has enough tokens approved, etc.
     * - MUST be inclusive of deposit fees. Integrators should be aware of the existence of deposit fees.
     * - MUST NOT revert.
     *
     * NOTE: any unfavorable discrepancy between convertToAssets and previewMint SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by minting.
     */
    function previewMint(uint256 shares) external view returns (uint256[] memory) {
        revert("0");
    }

    /**
     * @dev Returns the maximum amount of the underlying asset that can be withdrawn from the owner balance in the
     * Vault, through a withdraw call.
     *
     * - MUST return a limited value if owner is subject to some withdrawal limit or timelock.
     * - MUST NOT revert.
     */
    function maxWithdraw(address owner) external view returns (uint256[] memory) {
        revert("0");
    }

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their withdrawal at the current block,
     * given current on-chain conditions.
     * @param assets TODO
     *
     * - MUST return as close to and no fewer than the exact amount of Vault shares that would be burned in a withdraw
     *   call in the same transaction. I.e. withdraw should return the same or fewer shares as previewWithdraw if
     *   called
     *   in the same transaction.
     * - MUST NOT account for withdrawal limits like those returned from maxWithdraw and should always act as though
     *   the withdrawal would be accepted, regardless if the user has enough shares, etc.
     * - MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
     * - MUST NOT revert.
     *
     * NOTE: any unfavorable discrepancy between convertToShares and previewWithdraw SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by depositing.
     */
    function previewWithdraw(uint256[] calldata assets) external view returns (uint256) {
        revert("0");
    }

    /**
     * @dev Returns the maximum amount of Vault shares that can be redeemed from the owner balance in the Vault,
     * through a redeem call.
     * @param owner TODO
     *
     * - MUST return a limited value if owner is subject to some withdrawal limit or timelock.
     * - MUST return balanceOf(owner) if owner is not subject to any withdrawal limit or timelock.
     * - MUST NOT revert.
     */
    function maxRedeem(address owner) external view returns (uint256) {
        revert("0");
    }

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their redeemption at the current block,
     * given current on-chain conditions.
     * @param shares TODO
     *
     * - MUST return as close to and no more than the exact amount of assets that would be withdrawn in a redeem call
     *   in the same transaction. I.e. redeem should return the same or more assets as previewRedeem if called in the
     *   same transaction.
     * - MUST NOT account for redemption limits like those returned from maxRedeem and should always act as though the
     *   redemption would be accepted, regardless if the user has enough shares, etc.
     * - MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
     * - MUST NOT revert.
     *
     * NOTE: any unfavorable discrepancy between convertToAssets and previewRedeem SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by redeeming.
     */
    function previewRedeem(uint256 shares) external view returns (uint256) {
        revert("0");
    }

    /**
     * @dev Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
     *
     * - MUST be an ERC-20 token contract.
     * - MUST NOT revert.
     */
    function asset() external view returns (address[] memory) {
        return _assetGroup;
    }

    /**
     * @dev Returns the total amount of the underlying asset that is “managed” by Vault.
     *
     * - SHOULD include any compounding that occurs from yield.
     * - MUST be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT revert.
     */
    function totalAssets() external view returns (uint256[] memory) {
        revert("0");
    }

    /**
     * @dev Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an ideal
     * scenario where all the conditions are met.
     * @param assets TODO
     *
     * - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
     * - MUST NOT revert.
     *
     * NOTE: This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the
     * “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and
     * from.
     */
    function convertToShares(uint256[] calldata assets) external view returns (uint256) {
        revert("0");
    }

    /**
     * @dev Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
     * scenario where all the conditions are met.
     * @param shares TODO
     *
     * - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
     * - MUST NOT revert.
     *
     * NOTE: This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the
     * “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and
     * from.
     */
    function convertToAssets(uint256 shares) external view returns (uint256[] memory) {
        revert("0");
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Burns exactly shares from owner and sends assets of underlying tokens to receiver.
     * @param shares TODO
     * @param receiver TODO
     * @param owner TODO
     * - MUST emit the Withdraw event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
     *   redeem execution, and are accounted for during redeem.
     * - MUST revert if all of shares cannot be redeemed (due to withdrawal limit being reached, slippage, the owner
     *   not having enough shares, etc).
     *
     * NOTE: some implementations will require pre-requesting to the Vault before a withdrawal may be performed.
     * Those methods should be performed separately.
     */
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256) {
        revert("0");
    }

    /**
     * @notice TODO
     * @param nftIds TODO
     * @return shares TODO
     */
    function burnDepositNFTs(uint256[] calldata nftIds) external returns (uint256) {
        revert("0");
    }

    /**
     * @notice TODO
     * @param nftIds TODO
     * @return assets TODO
     */
    function burnWithdrawalNFTs(uint256[] calldata nftIds) external returns (uint256[] memory) {
        revert("0");
    }

    /**
     * @notice TODO
     * @param depositor TODO
     * @param assets TODO
     * @param receiver TODO
     */
    function depositFor(uint256[] calldata assets, address receiver, address depositor) external returns (uint256) {
        _runGuards(depositor, receiver, assets, _assetGroup, RequestType.Deposit);
        _runActions(depositor, receiver, assets, _assetGroup, RequestType.Deposit);
        _mintDepositNFT(receiver, assets, _assetGroup);
        _depositAssets(depositor, receiver, assets, _assetGroup);
        return _maxDepositID;
    }

    /**
     * @notice TODO
     * @param assets TODO
     * @param receiver TODO
     * @param slippages TODO
     * @return receipt TODO
     */
    function depositFast(uint256[] calldata assets, address receiver, uint256[][] calldata slippages)
        external
        returns (uint256)
    {
        _runGuards(msg.sender, receiver, assets, _assetGroup, RequestType.Deposit);
        // TODO: pass slippages
        _runActions(msg.sender, receiver, assets, _assetGroup, RequestType.Deposit);
        _mintDepositNFT(receiver, assets, _assetGroup);
        _depositAssets(msg.sender, receiver, assets, _assetGroup);

        return _maxDepositID;
    }

    /**
     * @notice Used to withdraw underlying asset.
     * @param assets TODO
     * @param tokens TODO
     * @param receiver TODO
     * @param owner TODO
     * @return returnedAssets TODO
     */
    function withdrawFast(
        uint256[] calldata assets,
        address[] calldata tokens,
        address receiver,
        uint256[][] calldata, /*slippages*/
        address owner
    ) external returns (uint256[] memory) {
        _runGuards(owner, receiver, assets, tokens, RequestType.Withdrawal);
        // TODO: pass slippages
        _runActions(owner, receiver, assets, tokens, RequestType.Withdrawal);
        _mintWithdrawalNFT(receiver, assets, tokens);
        return _withdrawAssets(owner, receiver, assets, tokens);
    }

    /**
     * @dev Mints exactly shares Vault shares to receiver by depositing amount of underlying tokens.
     * @param shares TODO
     * @param receiver TODO
     *
     * - MUST emit the Deposit event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the mint
     *   execution, and are accounted for during mint.
     * - MUST revert if all of shares cannot be minted (due to deposit limit being reached, slippage, the user not
     *   approving enough underlying tokens to the Vault contract, etc).
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault’s underlying asset token.
     */
    function mint(uint256 shares, address receiver) external returns (uint256[] memory) {
        revert("0");
    }

    /**
     * @dev Burns shares from owner and sends exactly assets of underlying tokens to receiver.
     * @param assets TODO
     * @param tokens TODO
     * @param receiver TODO
     * @param owner TODO
     *
     * - MUST emit the Withdraw event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
     *   withdraw execution, and are accounted for during withdraw.
     * - MUST revert if all of assets cannot be withdrawn (due to withdrawal limit being reached, slippage, the owner
     *   not having enough shares, etc).
     *
     * Note that some implementations will require pre-requesting to the Vault before a withdrawal may be performed.
     * Those methods should be performed separately.
     */
    function withdraw(uint256[] calldata assets, address[] calldata tokens, address receiver, address owner)
        external
        returns (uint256)
    {
        _runGuards(owner, receiver, assets, tokens, RequestType.Withdrawal);
        _runActions(owner, receiver, assets, tokens, RequestType.Withdrawal);
        _mintWithdrawalNFT(receiver, assets, tokens);
        _withdrawAssets(owner, receiver, assets, tokens);

        return _maxWithdrawalID;
    }

    /**
     * @dev Mints shares Vault shares to receiver by depositing exactly amount of underlying tokens.
     * @param assets TODO
     *
     * - MUST emit the Deposit event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
     *   deposit execution, and are accounted for during deposit.
     * - MUST revert if all of assets cannot be deposited (due to deposit limit being reached, slippage, the user not
     *   approving enough underlying tokens to the Vault contract, etc).
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault’s underlying asset token.
     */
    function deposit(uint256[] calldata assets, address receiver) external returns (uint256) {
        _runGuards(msg.sender, receiver, assets, _assetGroup, RequestType.Deposit);
        _runActions(msg.sender, receiver, assets, _assetGroup, RequestType.Deposit);
        _mintDepositNFT(receiver, assets, _assetGroup);
        _depositAssets(msg.sender, receiver, assets, _assetGroup);

        return _maxDepositID;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _mintWithdrawalNFT(address receiver, uint256[] memory assets, address[] memory /*tokens*/ )
        internal
        returns (uint256)
    {
        require(_maxWithdrawalID < 2 ** uint256(256), "SmartVault::_burnWithdrawalNTF::Withdrawal ID overflow.");

        _maxWithdrawalID++;
        uint256[] memory latestIndexes = StrategyRegistry.getLatestIndexes(address(this));

        WithdrawalMetadata memory data = WithdrawalMetadata(assets, block.timestamp, latestIndexes);
        _withdrawalMetadata[_maxWithdrawalID] = data;
        _mint(receiver, _maxWithdrawalID, 1, "");

        return _maxWithdrawalID;
    }

    function _mintDepositNFT(address receiver, uint256[] memory assets, address[] memory /*tokens*/ )
        internal
        returns (uint256)
    {
        _maxDepositID++;
        require(_maxDepositID < 2 ** 256 / 2, "SmartVault::deposit::Deposit ID overflow.");

        uint256[] memory latestIndexes = StrategyRegistry.getLatestIndexes(address(this));
        DepositMetadata memory data = DepositMetadata(assets, block.timestamp, latestIndexes);
        _mint(receiver, _maxDepositID, 1, "");
        _depositMetadata[_maxDepositID] = data;

        return _maxDepositID;
    }

    function _afterTokenTransfer(
        address,
        address,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory
    ) internal virtual override {
        for (uint256 i; i < ids.length; i++) {
            require(amounts[i] == 1, "SmartVault::_afterTokenTransfer: Invalid NFT amount");
            _nftOwners[ids[i]] = to;
        }
    }

    function _runGuards(
        address executor,
        address receiver,
        uint256[] memory assets,
        address[] memory tokens,
        RequestType requestType
    ) internal view {
        RequestContext memory context = RequestContext(receiver, executor, requestType, assets, tokens);
        guardManager.runGuards(address(this), context);
    }

    function _runActions(
        address executor,
        address recipient,
        uint256[] memory assets,
        address[] memory tokens,
        RequestType requestType
    ) internal {
        ActionContext memory context = ActionContext(recipient, executor, requestType, tokens, assets);

        actionManager.runActions(address(this), context);
    }

    function _depositAssets(address initiator, address, /* receiver */ uint256[] memory assets, address[] memory tokens)
        internal
    {
        require(assets.length == tokens.length, "SmartVault::depositFor::invalid assets length");

        for (uint256 i = 0; i < assets.length; i++) {
            // write to a registry
            // - for DHW: how much, which strat, which index
            // - for vault: which vault, which strat, which index
            ERC20(tokens[i]).safeTransferFrom(initiator, address(StrategyRegistry), assets[i]);
        }

        // uint256[] memory allocations = riskManager.allocations(address(this));
        // StrategyRegistry.addStrategyDeposits(address(this), allocations, assets, tokens);
    }

    function _withdrawAssets(address from, address to, uint256[] memory assets, address[] memory tokens)
        internal
        returns (uint256[] memory)
    {
        return new uint256[](1);
    }

    /* ========== MODIFIERS ========== */

    modifier runGuards(
        address executor,
        address receiver,
        uint256[] memory assets,
        address[] memory tokens,
        RequestType requestType
    ) {
        _runGuards(executor, receiver, assets, tokens, requestType);
        _;
    }
}
