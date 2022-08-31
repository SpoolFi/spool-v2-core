// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IVault.sol";


interface ISmartVault is IVault {

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice TODO
     * @return name Name of the vault
     */
    function name() external view returns (string memory name);

    /**
     * @notice Returns the address of the current owner.
     */
    function owner() public view virtual returns (address owner);

    /**
     * @notice TODO
     * @return riskTolerance
     */
    function riskTolerance() external view returns (int memory riskTolerance);

    /**
     * @notice TODO
     * @return riskProviderAddress
     */
    function riskProvider() external view returns (address memory riskProviderAddress);

    /**
     * @notice TODO
     * @return strategyAddresses
     */
    function strategies() external view returns (address[] memory strategyAddresses);

    /**
     * @notice TODO
     * @return allocations
     */
    function allocations() external view returns (uint256[] memory allocations);

    /**
     * @notice TODO
     * @return isTransferable
     */
    function isShareTokenTransferable() external view returns (bool isTransferable);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice TODO
     * @param nftIds
     * @return shares
     */
    function burnDepositNFTs(uint256[] calldata nftIds) external returns (uint256 shares);

    /**
     * @notice TODO
     * @param nftIds
     * @return assets
     */
    function burnWithdrawalNFTs(uint256[] calldata nftIds) external returns (uint256[] memory assets);

    /**
     * @notice TODO
     * @param assets
     * @param receiver
     * @param slippages
     * @return depositNFTId
     */
    function depositFast(uint256[] calldata assets, address receiver, uint256[][] calldata slippages) external returns (uint256 depositNFTId);

    /**
     * @notice TODO
     * @param shares
     * @param receiver
     * @param owner
     * @param slippages
     * @return assets
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256[][] slippages
    ) external returns (uint256[] memory assets);

    /**
     * @notice TODO
     * @param newOwner
     */
    function transferOwnership(address newOwner) external;
}
