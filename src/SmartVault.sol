// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/utils/Strings.sol";
import "@openzeppelin-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "./interfaces/IGuardManager.sol";
import "./interfaces/ISmartVault.sol";
import "./interfaces/CommonErrors.sol";
import "./interfaces/RequestType.sol";
import "./access/SpoolAccessControllable.sol";
import "./libraries/ArrayMapping.sol";

contract SmartVault is ERC20PermitUpgradeable, ERC1155Upgradeable, SpoolAccessControllable, ISmartVault {
    using SafeERC20 for IERC20;
    using ArrayMappingUint256 for mapping(uint256 => uint256);

    /* ========== CONSTANTS ========== */

    /// @notice Guard manager
    IGuardManager internal immutable _guardManager;

    /// @notice Asset group ID
    uint256 public assetGroupId;

    /// @notice Vault name
    string internal _vaultName;

    /* ========== STATE VARIABLES ========== */

    /// @notice Deposit metadata registry
    mapping(uint256 => DepositMetadata) private _depositMetadata;

    /// @notice Withdrawal metadata registry
    mapping(uint256 => WithdrawalMetadata) private _withdrawalMetadata;

    /// @notice Deposit NFT ID
    uint256 internal _lastDepositId;

    /// @notice Withdrawal NFT ID
    uint256 internal _lastWithdrawalId;

    /* ========== CONSTRUCTOR ========== */

    constructor(ISpoolAccessControl accessControl_, IGuardManager guardManager_)
        SpoolAccessControllable(accessControl_)
    {
        if (address(guardManager_) == address(0)) revert ConfigurationAddressZero();

        _guardManager = guardManager_;

        _disableInitializers();
    }

    function initialize(
        string calldata vaultName_,
        string calldata svtSymbol,
        string calldata baseURI_,
        uint256 assetGroupId_
    ) public initializer {
        if (bytes(vaultName_).length == 0) revert InvalidConfiguration();

        __ERC1155_init(baseURI_);
        __ERC20_init(vaultName_, svtSymbol);

        _vaultName = vaultName_;
        assetGroupId = assetGroupId_;

        _lastDepositId = 0;
        _lastWithdrawalId = MAXIMAL_DEPOSIT_ID;
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @dev Returns the URI for token type `id`.
     * Base functionality is used to hold the base URI string.
     * We override and append the token ID.
     */
    function uri(uint256 tokenId)
        public
        view
        override(ERC1155Upgradeable, IERC1155MetadataURIUpgradeable)
        returns (string memory)
    {
        return string(abi.encodePacked(super.uri(0), Strings.toString(tokenId), ".json"));
    }

    /**
     * @dev See {IERC1155-balanceOf}.
     * Returns 1 if user has any balance, 0 otherwise.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id)
        public
        view
        override(ERC1155Upgradeable, IERC1155Upgradeable)
        returns (uint256)
    {
        return super.balanceOf(account, id) >= 1 ? 1 : 0;
    }

    function balanceOfFractional(address account, uint256 id) public view returns (uint256) {
        return super.balanceOf(account, id);
    }

    /**
     * @notice Returns user's NFT balance
     * @dev 1 if user has any balance, 0 otherwise.
     */
    function balanceOfBatch(address[] memory accounts, uint256[] memory ids)
        public
        view
        override(ERC1155Upgradeable, IERC1155Upgradeable)
        returns (uint256[] memory)
    {
        require(accounts.length == ids.length, "ERC1155: accounts and ids length mismatch");
        uint256[] memory batchBalances = new uint256[](accounts.length);

        for (uint256 i; i < accounts.length; ++i) {
            batchBalances[i] = balanceOf(accounts[i], ids[i]);
        }

        return batchBalances;
    }

    function balanceOfFractionalBatch(address account, uint256[] calldata ids) public view returns (uint256[] memory) {
        uint256[] memory batchBalances = new uint256[](ids.length);

        for (uint256 i; i < ids.length; ++i) {
            batchBalances[i] = balanceOfFractional(account, ids[i]);
        }

        return batchBalances;
    }

    function vaultName() external view returns (string memory) {
        return _vaultName;
    }

    function getMetadata(uint256[] calldata nftIds) public view returns (bytes[] memory) {
        bytes[] memory metadata = new bytes[](nftIds.length);

        for (uint256 i; i < nftIds.length; ++i) {
            metadata[i] = nftIds[i] > MAXIMAL_DEPOSIT_ID
                ? abi.encode(_withdrawalMetadata[nftIds[i]])
                : abi.encode(_depositMetadata[nftIds[i]]);
        }

        return metadata;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Set a new base URI for ERC1155 metadata and emits an event.
     * @param uri_ new base URI value
     */
    function setBaseURI(string memory uri_) external onlyAdminOrVaultAdmin(address(this), msg.sender) {
        _setURI(uri_);
        emit BaseURIChanged(uri_);
    }

    function mintVaultShares(address receiver, uint256 vaultShares)
        external
        virtual
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
    {
        _mint(receiver, vaultShares);
    }

    function burnVaultShares(
        address owner,
        uint256 vaultShares,
        address[] calldata strategies,
        uint256[] calldata shares
    ) external onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender) {
        // burn withdrawn vault shares
        _burn(owner, vaultShares);

        for (uint256 i; i < strategies.length; ++i) {
            if (shares[i] > 0) {
                IERC20(strategies[i]).safeTransfer(strategies[i], shares[i]);
            }
        }
    }

    function burnNFTs(address owner, uint256[] calldata nftIds, uint256[] calldata nftAmounts)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (bytes[] memory)
    {
        _burnBatch(owner, nftIds, nftAmounts);
        return getMetadata(nftIds);
    }

    function claimShares(address claimer, uint256 amount) external onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender) {
        _transfer(address(this), claimer, amount);
    }

    function mintDepositNFT(address receiver, DepositMetadata calldata metadata)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint256)
    {
        if (_lastDepositId >= MAXIMAL_DEPOSIT_ID) {
            revert DepositIdOverflow();
        }
        _lastDepositId++;
        _depositMetadata[_lastDepositId] = metadata;
        _mint(receiver, _lastDepositId, NFT_MINTED_SHARES, "");

        return _lastDepositId;
    }

    function mintWithdrawalNFT(address receiver, WithdrawalMetadata memory metadata)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint256 receipt)
    {
        if (_lastWithdrawalId >= MAXIMAL_WITHDRAWAL_ID) {
            revert WithdrawalIdOverflow();
        }
        _lastWithdrawalId++;
        _withdrawalMetadata[_lastWithdrawalId] = metadata;
        _mint(receiver, _lastWithdrawalId, NFT_MINTED_SHARES, "");

        return _lastWithdrawalId;
    }

    function transferFromSpender(address from, address to, uint256 amount)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (bool)
    {
        _transfer(from, to, amount);
        return true;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal view override {
        _requireNotPaused();

        // mint / burn / redeem
        if (from == address(0) || to == address(0) || to == address(this)) return;
        if (from == to) revert SenderEqualsRecipient();

        uint256[] memory assets = new uint256[](1);
        assets[0] = amount;

        RequestContext memory context = RequestContext({
            receiver: to,
            executor: msg.sender,
            owner: from,
            requestType: RequestType.TransferSVTs,
            assets: assets,
            tokens: new address[](0)
        });
        _guardManager.runGuards(address(this), context);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory
    ) internal view override {
        _requireNotPaused();

        // skip transfer checks when minting and burning
        // they have their own checks made
        if (from == address(0) || to == address(0)) return;
        if (from == to) revert SenderEqualsRecipient();

        // check that only full NFT can be transferred
        for (uint256 i; i < ids.length; ++i) {
            if (amounts[i] != NFT_MINTED_SHARES) {
                revert InvalidNftTransferAmount(amounts[i]);
            }
        }

        // NOTE:
        // - here we are passing ids into the request context instead of amounts
        // - here we passing empty array as tokens
        RequestContext memory context = RequestContext({
            receiver: to,
            executor: operator,
            owner: from,
            requestType: RequestType.TransferNFT,
            assets: ids,
            tokens: new address[](0)
        });
        _guardManager.runGuards(address(this), context);
    }
}
