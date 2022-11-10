// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "./interfaces/CommonErrors.sol";
import "./interfaces/IAssetGroupRegistry.sol";
import "./interfaces/ISmartVaultManager.sol";
import "./interfaces/ISmartVault.sol";
import "./interfaces/RequestType.sol";

contract SmartVault is AccessControlUpgradeable, ERC20Upgradeable, ERC1155Upgradeable, ISmartVault {
    using SafeERC20 for ERC20;

    /* ========== STATE VARIABLES ========== */

    // @notice Smart Vault manager
    ISmartVaultManager internal immutable smartVaultManager;

    /**
     * @notice ID of the asset group used by the smart vault.
     */
    uint256 internal _assetGroupId;

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
     * @param smartVaultManager_ TODO
     */
    constructor(string memory vaultName_, ISmartVaultManager smartVaultManager_) {
        _vaultName = vaultName_;
        smartVaultManager = smartVaultManager_;
    }

    function initialize(uint256 assetGroupId_, IAssetGroupRegistry assetGroupRegistry_) external initializer {
        _assetGroupId = assetGroupId_;

        __ERC1155_init("");
        __ERC20_init("", "");

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        approve(address(smartVaultManager), uint256(2 ** 256 - 1));
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override (AccessControlUpgradeable, ERC1155Upgradeable, IERC165Upgradeable)
        returns (bool)
    {
        return interfaceId == type(IAccessControlUpgradeable).interfaceId
            || interfaceId == type(IERC1155Upgradeable).interfaceId
            || interfaceId == type(IERC1155MetadataURIUpgradeable).interfaceId
            || interfaceId == type(IERC165Upgradeable).interfaceId;
    }

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

    function getDepositMetadata(uint256 depositNftId) external view returns (DepositMetadata memory) {
        return _depositMetadata[depositNftId];
    }

    function getWithdrawalMetadata(uint256 withdrawalNftId) external view returns (WithdrawalMetadata memory) {
        return _withdrawalMetadata[withdrawalNftId];
    }

    function assetGroupId() external view returns (uint256) {
        return _assetGroupId;
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

    function mint(address receiver, uint256 vaultShares) external onlySmartVaultManager {
        _mint(receiver, vaultShares);
    }

    function burn(address owner, uint256 vaultShares) external onlySmartVaultManager {
        // burn withdrawn vault shares
        _burn(owner, vaultShares);
    }

    function burnNFT(address owner, uint256 nftID, RequestType type_) external onlySmartVaultManager {
        // check validity and ownership of the NFT
        if (type_ == RequestType.Deposit && nftID > _maximalDepositId) {
            revert InvalidDepositNftId(nftID);
        }
        if (type_ == RequestType.Withdrawal && nftID <= _maximalDepositId) {
            revert InvalidWithdrawalNftId(nftID);
        }
        if (balanceOf(owner, nftID) != 1) {
            revert InvalidNftBalance(balanceOf(owner, nftID));
        }

        _burn(owner, nftID, 1);
    }

    function claimShares(address claimer, uint256 amount) external onlySmartVaultManager {
        _transfer(address(this), claimer, amount);
    }

    function releaseStrategyShares(address[] memory strategies, uint256[] memory shares)
        external
        onlySmartVaultManager
    {
        for (uint256 i = 0; i < strategies.length; i++) {
            IERC20(strategies[i]).transfer(strategies[i], shares[i]);
        }
    }

    function mintDepositNFT(address receiver, DepositMetadata memory metadata)
        external
        onlySmartVaultManager
        returns (uint256)
    {
        if (_maxDepositID >= _maximalDepositId - 1) {
            revert DepositIdOverflow();
        }
        _maxDepositID++;
        _depositMetadata[_maxDepositID] = metadata;
        _mint(receiver, _maxDepositID, 1, "");

        return _maxDepositID;
    }

    function mintWithdrawalNFT(address receiver, WithdrawalMetadata memory metadata)
        external
        onlySmartVaultManager
        returns (uint256 receipt)
    {
        if (_maxWithdrawalID >= _maximalWithdrawalId - 1) {
            revert WithdrawalIdOverflow();
        }
        _maxWithdrawalID++;
        _withdrawalMetadata[_maxWithdrawalID] = metadata;
        _mint(receiver, _maxWithdrawalID, 1, "");

        return _maxWithdrawalID;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

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
