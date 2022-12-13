// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "./interfaces/CommonErrors.sol";
import "./interfaces/ISmartVault.sol";
import "./interfaces/RequestType.sol";
import "./access/SpoolAccessControl.sol";
import "./interfaces/IGuardManager.sol";

contract SmartVault is ERC20Upgradeable, ERC1155Upgradeable, SpoolAccessControllable, ISmartVault {
    using SafeERC20 for IERC20;

    /* ========== CONSTANTS ========== */

    // @notice Maximal value of deposit NFT ID.
    uint256 private constant MAXIMAL_DEPOSIT_ID = 2 ** 255 - 1;

    // @notice Maximal value of withdrawal NFT ID.
    uint256 private constant MAXIMAL_WITHDRAWAL_ID = 2 ** 256 - 1;

    // @notice Guard manager
    IGuardManager internal immutable _guardManager;

    // @notice Asset group ID
    uint256 public assetGroupId;

    // @notice Vault name
    string internal _vaultName;

    /* ========== STATE VARIABLES ========== */

    // @notice Mapping from token ID => owner address
    mapping(uint256 => address) private _nftOwners;

    // @notice Mapping from user to all of his current D-NFT IDs
    mapping(address => uint256[]) private _usersDepositNFTIds;

    // @notice Deposit metadata registry
    mapping(uint256 => DepositMetadata) private _depositMetadata;

    // @notice Withdrawal metadata registry
    mapping(uint256 => WithdrawalMetadata) private _withdrawalMetadata;

    // @notice Deposit NFT ID
    uint256 private _lastDepositId;

    // @notice Withdrawal NFT ID
    uint256 private _lastWithdrawalId;

    /* ========== CONSTRUCTOR ========== */

    constructor(ISpoolAccessControl accessControl_, IGuardManager guardManager_)
        SpoolAccessControllable(accessControl_)
    {
        _guardManager = guardManager_;

        _disableInitializers();
    }

    function initialize(string memory vaultName_, uint256 assetGroupId_) external initializer {
        __ERC1155_init("");
        __ERC20_init("", "");

        _vaultName = vaultName_;
        assetGroupId = assetGroupId_;

        _lastDepositId = 0;
        _lastWithdrawalId = 2 ** 255;
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */
    /**
     * @return depositNTFIds A list of Deposit NFT IDs
     */
    function getUserDepositNFTIDs(address userAddress) external view returns (uint256[] memory depositNTFIds) {
        return _usersDepositNFTIds[userAddress];
    }

    function vaultName() external view returns (string memory) {
        return _vaultName;
    }

    function getDepositMetadata(uint256 depositNftId) external view returns (DepositMetadata memory) {
        return _depositMetadata[depositNftId];
    }

    function getWithdrawalMetadata(uint256 withdrawalNftId) external view returns (WithdrawalMetadata memory) {
        return _withdrawalMetadata[withdrawalNftId];
    }

    // TODO: implement or remove
    function totalAssets() external pure returns (uint256[] memory) {
        revert("0");
    }

    // TODO: implement or remove
    function convertToAssets(uint256) external pure returns (uint256[] memory) {
        revert("0");
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function mint(address receiver, uint256 vaultShares) external onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender) {
        _mint(receiver, vaultShares);
    }

    function burn(address owner, uint256 vaultShares, address[] memory strategies, uint256[] memory shares)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
    {
        // burn withdrawn vault shares
        _burn(owner, vaultShares);

        for (uint256 i = 0; i < strategies.length; i++) {
            IERC20(strategies[i]).safeTransfer(strategies[i], shares[i]);
        }
    }

    function burnNFT(address owner, uint256 nftId, RequestType type_)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
    {
        // check validity and ownership of the NFT
        if (type_ == RequestType.Deposit && nftId > MAXIMAL_DEPOSIT_ID) {
            revert InvalidDepositNftId(nftId);
        }
        if (type_ == RequestType.Withdrawal && nftId <= MAXIMAL_DEPOSIT_ID) {
            revert InvalidWithdrawalNftId(nftId);
        }
        if (balanceOf(owner, nftId) != 1) {
            revert InvalidNftBalance(balanceOf(owner, nftId));
        }

        _burn(owner, nftId, 1);
    }

    function claimShares(address claimer, uint256 amount) external onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender) {
        _transfer(address(this), claimer, amount);
    }

    function mintDepositNFT(address receiver, DepositMetadata memory metadata)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint256)
    {
        if (_lastDepositId >= MAXIMAL_DEPOSIT_ID - 1) {
            revert DepositIdOverflow();
        }
        _lastDepositId++;
        _depositMetadata[_lastDepositId] = metadata;
        _mint(receiver, _lastDepositId, 1, "");

        return _lastDepositId;
    }

    function mintWithdrawalNFT(address receiver, WithdrawalMetadata memory metadata)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (uint256 receipt)
    {
        if (_lastWithdrawalId >= MAXIMAL_WITHDRAWAL_ID - 1) {
            revert WithdrawalIdOverflow();
        }
        _lastWithdrawalId++;
        _withdrawalMetadata[_lastWithdrawalId] = metadata;
        _mint(receiver, _lastWithdrawalId, 1, "");

        return _lastWithdrawalId;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal view override {
        // mint / burn
        if (from == address(0) || to == address(0)) {
            return;
        }

        uint256[] memory assets = new uint256[](1);
        assets[0] = amount;

        RequestContext memory context =
            RequestContext(to, msg.sender, from, RequestType.TransferSVTs, assets, new address[](0));
        _guardManager.runGuards(address(this), context);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory,
        bytes memory
    ) internal view override {
        // mint
        if (from == address(0)) {
            return;
        }

        RequestContext memory context =
            RequestContext(to, operator, from, RequestType.TransferNFT, ids, new address[](0));
        _guardManager.runGuards(address(this), context);
    }

    function _afterTokenTransfer(
        address,
        address,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory
    ) internal override {
        for (uint256 i = 0; i < ids.length; i++) {
            require(amounts[i] == 1, "SmartVault::_afterTokenTransfer: Invalid NFT amount");
            _nftOwners[ids[i]] = to;

            _usersDepositNFTIds[to].push(ids[i]); // TODO: Check what happens on the NFT burn (and transfer).
        }
    }
}
