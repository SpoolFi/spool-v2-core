// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../interfaces/IAssetGroupRegistry.sol";
import "../interfaces/IDepositManager.sol";
import "../interfaces/ISmartVaultManager.sol";

/**
 * @notice Parameters for simulateSyncWithBurn function.
 * @custom:member smartVault Smart vault to sync.
 * @custom:member userAddress User burning their NFTs.
 * @custom:member assetGroupRegistry Asset group registry contract.
 * @custom:member depositManager Deposit manager contract.
 */
struct SimulateSyncWithBurnParams {
    address smartVault;
    address userAddress;
    IAssetGroupRegistry assetGroupRegistry;
    IDepositManager depositManager;
}

/**
 * @notice Parameters for _simulateNftBurn function.
 * @custom:member smartVault Smart vault.
 * @custom:member mintedSvts Amount of SVTs minted during the sync.
 * @custom:member flushIndex Current flush index of the smart vault.
 * @custom:member onlyCurrentFlushIndex Flag to burn only NFTs for the current flush index.
 * @custom:member depositManager Deposit manager contract.
 * @custom:member metadata Metadata of the NFTs.
 * @custom:member nftBalances Balances of the NFTs.
 * @custom:member tokens Asset group tokens.
 */
struct SimulateNftBurnParams {
    address smartVault;
    uint256 mintedSvts;
    FlushIndex flushIndex;
    bool onlyCurrentFlushIndex;
    IDepositManager depositManager;
    bytes[] metadata;
    uint256[] nftBalances;
    address[] tokens;
}

library SmartVaultManagerLib {
    /**
     * Simulate sync when burning dNFTs and return their svts value.
     * @param nftIds IDs of the NFTs to burn.
     * @param params Parameters for syncing and burning.
     * @param flushIndexes Current flush indexes for smart vaults.
     * @param smartVaultAssetGroups Asset groups for smart vaults.
     * @param lastDhwTimestampSynced Timestamps of the last DHW synced by smart vaults.
     * @param smartVaultStrategies Strategies for smart vaults.
     * @param dhwIndexes DHW indexes for smart vaults.
     * @param smartVaultFees Fees for smart vaults.
     * @return newBalance Amount of SVTs user would get by burning NFTs.
     */
    function simulateSyncWithBurn(
        uint256[] calldata nftIds,
        SimulateSyncWithBurnParams memory params,
        mapping(address => FlushIndex) storage flushIndexes,
        mapping(address => uint256) storage smartVaultAssetGroups,
        mapping(address => uint256) storage lastDhwTimestampSynced,
        mapping(address => address[]) storage smartVaultStrategies,
        mapping(address => mapping(uint256 => uint16a16)) storage dhwIndexes,
        mapping(address => SmartVaultFees) storage smartVaultFees
    ) external view returns (uint256 newBalance) {
        // Burn any NFTs that have already been synced
        FlushIndex memory flushIndex = flushIndexes[params.smartVault];
        SimulateNftBurnParams memory simulateNftBurnParams;
        simulateNftBurnParams.smartVault = params.smartVault;
        // simulateNftBurnParams.mintedSvts = 0;  <- default value
        simulateNftBurnParams.flushIndex = flushIndex;
        // simulateNftBurnParams.onlyCurrentFlushIndex = false;  <- default value
        simulateNftBurnParams.depositManager = params.depositManager;
        simulateNftBurnParams.metadata = ISmartVault(params.smartVault).getMetadata(nftIds);
        simulateNftBurnParams.nftBalances =
            ISmartVault(params.smartVault).balanceOfFractionalBatch(params.userAddress, nftIds);
        simulateNftBurnParams.tokens =
            params.assetGroupRegistry.listAssetGroup(smartVaultAssetGroups[params.smartVault]);

        newBalance += _simulateNftBurn(nftIds, simulateNftBurnParams);

        // Check if we need/can sync latest flush index
        if (
            flushIndex.toSync == flushIndex.current
                || !ISmartVaultManager(address(this)).areAllDhwRunsCompleted(params.smartVault, flushIndex.toSync)
        ) {
            return newBalance;
        }

        // Simulate deposit sync (DHW)
        {
            SimulateDepositParams memory simulateDepositParams;
            simulateDepositParams.smartVault = params.smartVault;
            simulateDepositParams.bag = [flushIndex.toSync, lastDhwTimestampSynced[params.smartVault]];
            simulateDepositParams.strategies = smartVaultStrategies[params.smartVault];
            simulateDepositParams.assetGroup = simulateNftBurnParams.tokens;
            simulateDepositParams.dhwIndexes = dhwIndexes[params.smartVault][flushIndex.toSync];
            simulateDepositParams.dhwIndexesOld =
                _getPreviousDhwIndexes(params.smartVault, flushIndex.toSync, dhwIndexes);
            simulateDepositParams.fees = smartVaultFees[params.smartVault];

            DepositSyncResult memory syncResult = params.depositManager.syncDepositsSimulate(simulateDepositParams);

            simulateNftBurnParams.mintedSvts = syncResult.mintedSVTs;
        }

        // Burn any NFTs that would be synced as part of this flush cycle
        simulateNftBurnParams.onlyCurrentFlushIndex = true;

        newBalance += _simulateNftBurn(nftIds, simulateNftBurnParams);
    }

    /**
     * @dev Simulates burning of NFTs.
     * @param nftIds IDs of NFTs to burn.
     * @param params Parameters for burning.
     * @return svts Amount of SVTs user would get by burning NFTs.
     */
    function _simulateNftBurn(uint256[] calldata nftIds, SimulateNftBurnParams memory params)
        private
        view
        returns (uint256 svts)
    {
        for (uint256 i; i < nftIds.length; ++i) {
            // Skip W-NFTs
            if (nftIds[i] > MAXIMAL_DEPOSIT_ID) continue;

            // Skip D-NFTs with 0 balance
            if (params.nftBalances[i] == 0) continue;

            DepositMetadata memory data = abi.decode(params.metadata[i], (DepositMetadata));

            // we're burning NFTs that have already been synced previously
            if (!params.onlyCurrentFlushIndex && data.flushIndex >= params.flushIndex.toSync) continue;

            // we're burning NFTs for current synced flushIndex
            if (params.onlyCurrentFlushIndex && data.flushIndex != params.flushIndex.toSync) continue;

            svts += params.depositManager.getClaimedVaultTokensPreview(
                params.smartVault, data, params.nftBalances[i], params.mintedSvts, params.tokens
            );
        }
    }

    /**
     * @dev Gets previous DHW indexes for a smart vault.
     * @param smartVault Smart vault.
     * @param flushIndex Current flush index of the smart vault.
     * @param dhwIndexes DHW indexes for smart vaults.
     */
    function _getPreviousDhwIndexes(
        address smartVault,
        uint256 flushIndex,
        mapping(address => mapping(uint256 => uint16a16)) storage dhwIndexes
    ) private view returns (uint16a16) {
        return flushIndex == 0 ? uint16a16.wrap(0) : dhwIndexes[smartVault][flushIndex - 1];
    }
}
