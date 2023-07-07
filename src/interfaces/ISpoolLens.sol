// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

interface ISpoolLens {
    /**
     * @notice Retrieves a Smart Vault Token Balance for user. Including the predicted balance from all current D-NFTs
     * currently in holding.
     */
    function getUserSVTBalance(address smartVaultAddress, address userAddress, uint256[] calldata nftIds)
        external
        view
        returns (uint256 currentBalance);

    function getUserSVTsfromNFTs(address smartVaultAddress, address userAddress, uint256[] calldata nftIds)
        external
        view
        returns (uint256[] memory nftSvts);

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
