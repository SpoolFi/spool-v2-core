// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../interfaces/IAssetGroupRegistry.sol";
import "../interfaces/IDepositManager.sol";
import "../interfaces/ISmartVaultManager.sol";

struct SimulateSyncWithBurnParams {
    address smartVault;
    address userAddress;
    IAssetGroupRegistry assetGroupRegistry;
    IDepositManager depositManager;
}

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
    function simulateSyncWithBurn(
        uint256[] calldata nftIds,
        SimulateSyncWithBurnParams memory params,
        mapping(address => FlushIndex) storage flushIndexes_,
        mapping(address => uint256) storage smartVaultAssetGroups_,
        mapping(address => uint256) storage lastDhwTimestampSynced_,
        mapping(address => address[]) storage smartVaultStrategies_,
        mapping(address => mapping(uint256 => uint16a16)) storage dhwIndexes_,
        mapping(address => SmartVaultFees) storage smartVaultFees_
    ) external view returns (uint256 newBalance) {
        // Burn any NFTs that have already been synced
        FlushIndex memory flushIndex = flushIndexes_[params.smartVault];
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
            params.assetGroupRegistry.listAssetGroup(smartVaultAssetGroups_[params.smartVault]);

        newBalance += _simulateNFTBurn(nftIds, simulateNftBurnParams);

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
            simulateDepositParams.bag = [flushIndex.toSync, lastDhwTimestampSynced_[params.smartVault]];
            simulateDepositParams.strategies = smartVaultStrategies_[params.smartVault];
            simulateDepositParams.assetGroup = simulateNftBurnParams.tokens;
            simulateDepositParams.dhwIndexes = dhwIndexes_[params.smartVault][flushIndex.toSync];
            simulateDepositParams.dhwIndexesOld =
                _getPreviousDhwIndexes(params.smartVault, flushIndex.toSync, dhwIndexes_);
            simulateDepositParams.fees = smartVaultFees_[params.smartVault];

            DepositSyncResult memory syncResult = params.depositManager.syncDepositsSimulate(simulateDepositParams);

            simulateNftBurnParams.mintedSvts = syncResult.mintedSVTs;
        }

        // Burn any NFTs that would be synced as part of this flush cycle
        simulateNftBurnParams.onlyCurrentFlushIndex = true;

        newBalance += _simulateNFTBurn(nftIds, simulateNftBurnParams);
    }

    function _simulateNFTBurn(uint256[] calldata nftIds, SimulateNftBurnParams memory params)
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

    function _getPreviousDhwIndexes(
        address smartVault,
        uint256 flushIndex,
        mapping(address => mapping(uint256 => uint16a16)) storage dhwIndexes_
    ) private view returns (uint16a16) {
        return flushIndex == 0 ? uint16a16.wrap(0) : dhwIndexes_[smartVault][flushIndex - 1];
    }
}
