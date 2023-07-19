// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

interface ISpoolLens {
    /**
     * @notice Retrieves user balance of smart vault tokens.
     * @param smartVault Smart vault.
     * @param user User to check.
     * @param nftIds user's NFTs (only D-NFTs, system will ignore W-NFTs)
     * @return currentBalance SVT balance of user for smart vault.
     */
    function getUserSVTBalance(address smartVault, address user, uint256[] calldata nftIds)
        external
        view
        returns (uint256 currentBalance);

    function getUserSVTsfromNFTs(address smartVault, address user, uint256[] calldata nftIds)
        external
        view
        returns (uint256[] memory nftSvts);

    /**
     * @notice Retrieves total supply of SVTs.
     * Includes deposits that were processed by DHW, but still need SVTs to be minted.
     * @param smartVault Smart Vault address.
     * @return totalSupply Simulated total supply
     */
    function getSVTTotalSupply(address smartVault) external view returns (uint256);

    /**
     * @notice Calculate strategy allocations for a Smart Vault
     * @param strategies Array of strategies to calculate allocations for
     * @param riskProvider Address of the risk provider
     * @param allocationProvider Address of the allocation provider
     * @return allocations Array of allocations for each strategy
     */
    function getSmartVaultAllocations(address[] calldata strategies, address riskProvider, address allocationProvider)
        external
        view
        returns (uint256[][] memory allocations);
}
