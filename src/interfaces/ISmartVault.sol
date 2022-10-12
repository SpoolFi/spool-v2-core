// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "./IVault.sol";

struct DepositMetadata {
    uint256[] assets;
    uint256 initiated; // TODO: initiated / locked until / timelock ?
    uint256[] dhwIndexes;
}

struct WithdrawalMetadata {
    uint256[] assets;
    uint256 initiated;
    uint256[] dhwIndexes;
}

interface ISmartVault is IVault, IERC1155Upgradeable {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @return name Name of the vault
     */
    function vaultName() external view returns (string memory name);

    /**
     * @notice TODO
     * @return isTransferable
     */
    function isShareTokenTransferable() external view returns (bool isTransferable);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice TODO
     * @param nftIds TODO
     * @return shares TODO
     */
    function burnDepositNFTs(uint256[] calldata nftIds) external returns (uint256 shares);

    /**
     * @notice TODO
     * @param nftIds TODO
     * @return assets TODO
     */
    function burnWithdrawalNFTs(uint256[] calldata nftIds) external returns (uint256[] memory assets);

    /**
     * @notice TODO
     * @param assets TODO
     * @param receiver TODO
     * @param depositor TODO
     * @return depositNFTId TODO
     */
    function depositFor(uint256[] calldata assets, address receiver, address depositor)
        external
        returns (uint256 depositNFTId);

    /**
     * @notice TODO
     * @param assets TODO
     * @param receiver TODO
     * @param slippages TODO
     * @return receipt TODO
     */
    function depositFast(uint256[] calldata assets, address receiver, uint256[][] calldata slippages)
        external
        returns (uint256 receipt);

    /**
     * @notice Used to withdraw underlying asset.
     * @param assets TODO
     * @param tokens TODO
     * @param receiver TODO
     * @param owner TODO
     * @param slippages TODO
     * @param owner TODO
     * @return returnedAssets  TODO
     */
    function withdrawFast(
        uint256[] calldata assets,
        address[] calldata tokens,
        address receiver,
        uint256[][] calldata slippages,
        address owner
    ) external returns (uint256[] memory returnedAssets);
}
