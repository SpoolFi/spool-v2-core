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
import "./libraries/ArrayMapping.sol";

contract SmartVault is ERC20Upgradeable, ERC1155Upgradeable, SpoolAccessControllable, ISmartVault {
    using SafeERC20 for IERC20;
    using ArrayMapping for mapping(uint256 => uint256);

    /* ========== CONSTANTS ========== */

    // @notice Guard manager
    IGuardManager internal immutable _guardManager;

    // @notice Asset group ID
    uint256 public assetGroupId;

    // @notice Vault name
    string internal _vaultName;

    /* ========== STATE VARIABLES ========== */

    // @notice Mapping from user to all of his current D-NFT IDs
    mapping(address => mapping(uint256 => uint256)) private _activeUserNFTIds;

    // @notice Number of active (not burned) NFTs per address
    mapping(address => uint256) private _activeUserNFTCount;

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
    function activeUserNFTIds(address userAddress) external view returns (uint256[] memory) {
        return _activeUserNFTIds[userAddress].toArray(_activeUserNFTCount[userAddress]);
    }

    function vaultName() external view returns (string memory) {
        return _vaultName;
    }

    /**
     * @notice Get encoded metadata for given NFT ids (both withdrawal and deposit)
     */
    function getMetadata(uint256[] calldata nftIds) public view returns (bytes[] memory) {
        bytes[] memory metadata = new bytes[](nftIds.length);

        for (uint256 i = 0; i < nftIds.length; i++) {
            metadata[i] = nftIds[i] >= MAXIMAL_DEPOSIT_ID
                ? abi.encode(_withdrawalMetadata[nftIds[i]])
                : abi.encode(_depositMetadata[nftIds[i]]);
        }

        return metadata;
    }

    // TODO: implement or remove
    function totalAssets() external pure returns (uint256[] memory) {
        revert("0");
    }

    // TODO: implement or remove
    function convertToAssets(uint256) external pure returns (uint256[] memory) {
        revert("0");
    }

    function balanceOfBatch(address account, uint256[] memory ids) public view returns (uint256[] memory) {
        uint256[] memory batchBalances = new uint256[](ids.length);

        for (uint256 i = 0; i < ids.length; ++i) {
            batchBalances[i] = balanceOf(account, ids[i]);
        }

        return batchBalances;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Mint ERC20 SVTs for given receiver address
     * @param receiver Address to mint to
     * @param vaultShares Amount of tokens to mint
     */
    function mint(address receiver, uint256 vaultShares) external onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender) {
        _mint(receiver, vaultShares);
    }

    /**
     * @notice Burn SVTs and release strategy shares back to strategies
     * @param owner Address for which to burn SVTs
     * @param vaultShares Amount of SVTs to burn
     * @param strategies Strategies to which release the shares to
     * @param shares Amount of strategy shares to release
     */
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

    /**
     * @notice Burn NFTs and return their metadata
     * @param owner Owner of NFTs
     * @param nftIds NFTs to burn
     * @param nftAmounts NFT shares to burn (partial burn)
     */
    function burnNFTs(address owner, uint256[] calldata nftIds, uint256[] calldata nftAmounts)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
        returns (bytes[] memory)
    {
        for (uint256 i = 0; i < nftIds.length; i++) {
            if (balanceOf(owner, nftIds[i]) < nftAmounts[i]) {
                revert InvalidNftBalance(balanceOf(owner, nftIds[i]));
            }
        }

        _burnBatch(owner, nftIds, nftAmounts);
        return getMetadata(nftIds);
    }

    /**
     * @notice Claim SVTs
     * @param claimer Address to receive SVTs
     * @param amount Amount of SVTs to receive
     */
    function claimShares(address claimer, uint256 amount) external onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender) {
        _transfer(address(this), claimer, amount);
    }

    /**
     * @notice Mint a new Deposit NFT
     * @dev Supply of minted NFT is NFT_MINTED_SHARES (for partial burning)
     * @param receiver Address that will receive the NFT
     * @param metadata Metadata to store for minted NFT
     */
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
        _mint(receiver, _lastDepositId, NFT_MINTED_SHARES, "");

        return _lastDepositId;
    }

    /**
     * @notice Mint a new Withdrawal NFT
     * @dev Supply of minted NFT is NFT_MINTED_SHARES (for partial burning)
     * @param receiver Address that will receive the NFT
     * @param metadata Metadata to store for minted NFT
     */
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
        _mint(receiver, _lastWithdrawalId, NFT_MINTED_SHARES, "");

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
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory
    ) internal override {
        // burn
        if (to == address(0)) {
            uint256 count = _activeUserNFTCount[from];
            for (uint256 i = 0; i < ids.length; i++) {
                for (uint256 j = 0; j < count; j++) {
                    if (_activeUserNFTIds[from][j] == ids[i]) {
                        _activeUserNFTIds[from][j] = _activeUserNFTIds[from][count - 1];
                        count--;
                        break;
                    }
                }
            }

            _activeUserNFTCount[from] = count;
            return;
        }

        // mint or transfer
        for (uint256 i = 0; i < ids.length; i++) {
            _activeUserNFTIds[to][_activeUserNFTCount[to]] = ids[i];
            _activeUserNFTCount[to]++;
        }
    }
}
