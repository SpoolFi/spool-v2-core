// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "forge-std/console.sol";
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
import "./interfaces/ISmartVaultManager.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/CommonErrors.sol";
import "./interfaces/IMasterWallet.sol";

contract SmartVault is ERC1155Upgradeable, ERC20Upgradeable, ISmartVault {
    using SafeERC20 for ERC20;

    /* ========== STATE VARIABLES ========== */

    // @notice Guard manager
    IGuardManager internal immutable guardManager;

    // @notice Action manager
    IActionManager internal immutable actionManager;

    // @notice Strategy manager
    IStrategyRegistry internal immutable strategyRegistry;

    // @notice Smart Vault manager
    ISmartVaultManager internal immutable smartVaultManager;

    // @notice Master Wallet
    IMasterWallet immutable masterWallet;

    // @notice Asset group address array
    // TODO: Q: shouldn't this be an ID of asset group, with actual assets stored somewhere else?
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
    // @notice Maximal value of deposit NFT ID.
    uint256 private _maximalDepositId = 2 ** 255 - 1;

    // @notice Withdrawal NFT ID
    uint256 private _maxWithdrawalID = 2 ** 255;
    // @notice Maximal value of withdrawal NFT ID.
    uint256 private _maximalWithdrawalId = 2 ** 256 - 1;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Initializes variables
     * @param vaultName_ TODO
     * @param guardManager_ TODO
     * @param actionManager_ TODO
     * @param strategyRegistry_ TODO
     * @param smartVaultManager_ TODO
     */
    constructor(
        string memory vaultName_,
        IGuardManager guardManager_,
        IActionManager actionManager_,
        IStrategyRegistry strategyRegistry_,
        ISmartVaultManager smartVaultManager_,
        IMasterWallet masterWallet_
    ) {
        _vaultName = vaultName_;
        guardManager = guardManager_;
        actionManager = actionManager_;
        strategyRegistry = strategyRegistry_;
        smartVaultManager = smartVaultManager_;
        masterWallet = masterWallet_;
    }

    function initialize(address[] memory assets_) external initializer {
        _assetGroup = assets_;
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

    function getWithdrawalMetadata(uint256 withdrawalNftId) external view returns (WithdrawalMetadata memory) {
        return _withdrawalMetadata[withdrawalNftId];
    }

    /**
     * @dev Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
     *
     * - MUST be an ERC-20 token contract.
     * - MUST NOT revert.
     */
    function assets() external view returns (address[] memory) {
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
        return _redeemShares(shares, receiver, owner);
    }

    /**
     * @notice Used to withdraw underlying asset.
     * @param shares TODO
     * @param receiver TODO
     * @param owner TODO
     * @return returnedAssets TODO
     */
    function redeemFast(uint256 shares, address receiver, uint256[][] calldata, /*slippages*/ address owner)
        external
        returns (uint256[] memory)
    {
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
        uint256 flushIdx = _depositAssets(depositor, receiver, assets, _assetGroup);
        _mintDepositNFT(receiver, assets, _assetGroup, flushIdx);

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
        uint256 flushIdx = _depositAssets(msg.sender, receiver, assets, _assetGroup);
        _mintDepositNFT(receiver, assets, _assetGroup, flushIdx);

        return _maxDepositID;
    }

    function handleWithdrawalFlush(
        uint256 withdrawnVaultShares,
        uint256[] memory withdrawnStrategyShares,
        address[] memory strategies
    ) external onlySmartVaultManager {
        // burn withdrawn vault shares
        _burn(address(this), withdrawnVaultShares);

        // transfer withdrawn strategy shares back to strategies
        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy(strategies[i]).transfer(strategies[i], withdrawnStrategyShares[i]);
        }
    }

    function claimWithdrawal(uint256 withdrawalNftId, address receiver)
        external
        returns (uint256[] memory, address[] memory)
    {
        // check validity and ownership of the NFT
        if (withdrawalNftId <= _maxDepositID) {
            revert InvalidWithdrawalNftId(withdrawalNftId);
        }
        if (balanceOf(msg.sender, withdrawalNftId) != 1) {
            revert InvalidNftBalance(balanceOf(msg.sender, withdrawalNftId));
        }

        uint256[] memory withdrawnAssets = smartVaultManager.calculateWithdrawal(withdrawalNftId);

        _runActions(msg.sender, receiver, withdrawnAssets, _assetGroup, RequestType.Withdrawal);
        _burn(msg.sender, withdrawalNftId, 1);

        for (uint256 i = 0; i < _assetGroup.length; i++) {
            // TODO-Q: should this be done by an action, since there might be a swap?
            masterWallet.transfer(IERC20(_assetGroup[i]), receiver, withdrawnAssets[i]);
        }

        return (withdrawnAssets, _assetGroup);
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
        _runActions(msg.sender, receiver, assets, _assetGroup, RequestType.Deposit);
        _runGuards(msg.sender, receiver, assets, _assetGroup, RequestType.Deposit);
        uint256 flushIdx = _depositAssets(msg.sender, receiver, assets, _assetGroup);
        _mintDepositNFT(receiver, assets, _assetGroup, flushIdx);

        return _maxDepositID;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _mintDepositNFT(address receiver, uint256[] memory assets, address[] memory, /*tokens*/ uint256 flushIndex)
        internal
        returns (uint256)
    {
        _maxDepositID++;
        require(_maxDepositID < 2 ** 256 / 2, "SmartVault::deposit::Deposit ID overflow.");

        DepositMetadata memory data = DepositMetadata(assets, block.timestamp, flushIndex);
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
        returns (uint256)
    {
        require(assets.length == tokens.length, "SmartVault::depositFor::invalid assets length");

        for (uint256 i = 0; i < assets.length; i++) {
            ERC20(tokens[i]).safeTransferFrom(initiator, address(masterWallet), assets[i]);
        }

        return smartVaultManager.addDeposits(address(this), assets);
    }

    function _redeemShares(uint256 vaultShares, address receiver, address owner) internal returns (uint256) {
        if (balanceOf(msg.sender) < vaultShares) {
            revert InsufficientBalance(balanceOf(msg.sender), vaultShares);
        }

        // run guards
        uint256[] memory assets = new uint256[](1);
        assets[0] = vaultShares;
        address[] memory tokens = new address[](1);
        tokens[0] = address(this);
        _runGuards(msg.sender, receiver, assets, tokens, RequestType.Withdrawal);

        // add withdrawal to be flushed
        uint256 flushIndex = smartVaultManager.addWithdrawal(vaultShares);

        // transfer vault shares back to smart vault
        transfer(address(this), vaultShares);

        // mint withdrawal NFT
        if (_maxWithdrawalID >= _maximalWithdrawalId - 1) {
            revert WithdrawalIdOverflow();
        }
        _maxWithdrawalID++;
        _withdrawalMetadata[_maxWithdrawalID] = WithdrawalMetadata(vaultShares, flushIndex);
        _mint(msg.sender, _maxWithdrawalID, 1, "");

        return _maxWithdrawalID;
    }

    function _onlySmartVaultManager() internal view {
        if (msg.sender != address(smartVaultManager)) {
            revert NotSmartVaultManager(msg.sender);
        }
    }

    /* ========== MODIFIERS ========== */

    modifier onlySmartVaultManager() {
        _onlySmartVaultManager();
        _;
    }
}
