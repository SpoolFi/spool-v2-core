// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "../interfaces/IAssetGroupRegistry.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "./ArrayMapping.sol";
import "./SpoolUtils.sol";

struct ReallocationBag {
    IAssetGroupRegistry assetGroupRegistry;
    IUsdPriceFeedManager priceFeedManager;
    IMasterWallet masterWallet;
    uint256 assetGroupId;
}

library ReallocationLib {
    using ArrayMapping for mapping(uint256 => uint256);
    using ArrayMapping for mapping(uint256 => address);

    function reallocate(
        address[] calldata smartVaults,
        address[] calldata strategies,
        ReallocationBag calldata reallocationBag,
        mapping(address => address[]) storage _smartVaultStrategies,
        mapping(address => mapping(uint256 => uint256)) storage _smartVaultAllocations
    ) public {
        // Calculate reallocations needed for smart vaults.
        uint256[][][] memory reallocations = new uint256[][][](smartVaults.length);
        for (uint256 i; i < smartVaults.length; ++i) {
            reallocations[i] =
                calculateReallocation(smartVaults[i], _smartVaultStrategies[smartVaults[i]], _smartVaultAllocations);
        }

        // Validate provided strategies and create a per smart vault strategy mapping.
        uint256[][] memory strategyMapping = mapStrategies(smartVaults, strategies, _smartVaultStrategies);

        // Build the strategy-to-strategy reallocation table.
        uint256[][][] memory reallocationTable =
            buildReallocationTable(strategyMapping, strategies.length, reallocations);

        // Do the actual reallocation with withdrawals from and deposits into the underlying protocols.
        doReallocation(strategies, reallocationBag, reallocationTable);

        // Smart vaults claim strategy shares.
        claimShares(smartVaults, strategies, strategyMapping, reallocationTable, reallocations);
    }

    function mapStrategies(
        address[] calldata smartVaults,
        address[] calldata strategies,
        mapping(address => address[]) storage _smartVaultStrategies
    ) private view returns (uint256[][] memory) {
        // We want to validate that the provided strategies represent a set of all the
        // strategies used by the smart vaults being reallocated. At the same time we
        // also build a mapping between strategies as listed on each smart vault and
        // the provided strategies.

        bool[] memory strategyMatched = new bool[](strategies.length);
        uint256[][] memory strategyMapping = new uint256[][](smartVaults.length);

        // Build a mapping for each smart vault and validate that all strategies are
        // present in the provided list.
        for (uint256 i; i < smartVaults.length; ++i) {
            // Get strategies for this smart vault.
            address[] storage smartVaultStrategies = _smartVaultStrategies[smartVaults[i]];
            uint256 smartVaultStrategiesLength = smartVaultStrategies.length;
            // Mapping from this smart vault's strategies to provided strategies.
            strategyMapping[i] = new uint256[](smartVaultStrategiesLength);

            // Loop over smart vault's strategies.
            for (uint256 j; j < smartVaultStrategiesLength; ++j) {
                address strategy = smartVaultStrategies[j];
                bool found = false;

                // Try to find the strategy in the provided list of strategies.
                for (uint256 k; k < strategies.length; ++k) {
                    if (strategies[k] == strategy) {
                        // Match found.
                        found = true;
                        strategyMatched[k] = true;
                        // Add entry to the strategy mapping.
                        strategyMapping[i][j] = k;

                        break;
                    }
                }

                if (!found) {
                    // If a smart vault's strategy was not found in the provided list
                    // of strategies, this means that the provided list is invalid.
                    revert InvalidStrategies();
                }
            }
        }

        // Validate that each strategy in the provided list was matched at least once.
        for (uint256 i; i < strategyMatched.length; ++i) {
            if (!strategyMatched[i]) {
                // If a strategy was not matched, this means that it is not used by any
                // smart vault and should not be included in the list.
                revert InvalidStrategies();
            }
        }

        return strategyMapping;
    }

    function calculateReallocation(
        address smartVault,
        address[] storage smartVaultStrategies,
        mapping(address => mapping(uint256 => uint256)) storage _smartVaultAllocations
    ) private returns (uint256[][] memory) {
        // Store length of strategies array not to read storage every time.
        uint256 smartVaultStrategiesLength = smartVaultStrategies.length;

        // Initialize array for this smart vault.
        uint256[][] memory reallocation = new uint256[][](2);
        reallocation[0] = new uint256[](smartVaultStrategiesLength); // values to redeem
        reallocation[1] = new uint256[](smartVaultStrategiesLength + 1); // values to deposit | total value to deposit

        // Get smart vaults total USD value.
        uint256 totalUsdValue = SpoolUtils.getVaultTotalUsdValue(smartVault, smartVaultStrategies);
        // TODO: will call strategy.totalUsdValue which is value from last DHW, is this OK?

        // Get sum total of target allocation.
        uint256 totalTargetAllocation;
        for (uint256 i; i < smartVaultStrategiesLength; ++i) {
            totalTargetAllocation += _smartVaultAllocations[smartVault][i];
        }

        // Compare target and current allocation.
        for (uint256 i; i < smartVaultStrategiesLength; ++i) {
            uint256 targetValue = _smartVaultAllocations[smartVault][i] * totalUsdValue / totalTargetAllocation;
            uint256 currentValue = SpoolUtils.getVaultStrategyUsdValue(smartVault, smartVaultStrategies[i]);

            if (targetValue > currentValue) {
                // This strategy needs deposit.
                reallocation[1][i] = targetValue - currentValue;
                reallocation[1][smartVaultStrategiesLength] += targetValue - currentValue;
            } else if (targetValue < currentValue) {
                // This Strategy needs withdrawal.

                // Relese strategy shares.
                uint256 sharesToRedeem = IStrategy(smartVaultStrategies[i]).balanceOf(smartVault)
                    * (currentValue - targetValue) / currentValue;
                IStrategy(smartVaultStrategies[i]).releaseShares(smartVault, sharesToRedeem);

                // Recalculate value to withdraw based on released shares.
                reallocation[0][i] = IStrategy(smartVaultStrategies[i]).totalUsdValue() * sharesToRedeem
                    / IStrategy(smartVaultStrategies[i]).totalSupply();
            }
        }

        return reallocation;
    }

    function buildReallocationTable(
        uint256[][] memory strategyMapping,
        uint256 numStrategies,
        uint256[][][] memory reallocations
    ) private pure returns (uint256[][][] memory) {
        // We want to build a reallocation table which specifies how to redistribute
        // funds from one strategy to another.

        // Reallocation table is numStrategies x numStrategies big.
        // A value of cell (i, j) V_ij specifies the value V that needs to be withdrawn
        // from strategy i and deposited into strategy j.
        uint256[][][] memory reallocationTable = new uint256[][][](numStrategies);
        for (uint256 i = 0; i < numStrategies; ++i) {
            reallocationTable[i] = new uint256[][](numStrategies);

            for (uint256 j = 0; j < numStrategies; ++j) {
                reallocationTable[i][j] = new uint256[](3);
            }
        }

        // Loop over smart vaults.
        for (uint256 i = 0; i < reallocations.length; ++i) {
            // Calculate witdrawals and deposits needed to allign with new allocation.
            uint256 strategiesLength = reallocations[i][0].length;

            // Find strategies that need withdrawal.
            for (uint256 j = 0; j < strategiesLength; ++j) {
                if (reallocations[i][0][j] == 0) {
                    continue;
                }

                uint256[] memory values = new uint256[](2);
                values[0] = reallocations[i][0][j];
                values[1] = reallocations[i][1][strategiesLength];

                // Find strategies that need deposit.
                for (uint256 k = 0; k < strategiesLength; ++k) {
                    if (reallocations[i][1][k] == 0) {
                        continue;
                    }

                    // Find value from j that should move to strategy k.
                    uint256 valueToDeposit = values[0] * reallocations[i][1][k] / values[1];
                    reallocationTable[strategyMapping[i][j]][strategyMapping[i][k]][0] += valueToDeposit;

                    values[0] -= valueToDeposit; // dust-less calculation.
                    values[1] -= reallocations[i][1][k];
                }
            }
        }

        return reallocationTable;
    }

    function doReallocation(
        address[] calldata strategies,
        ReallocationBag calldata reallocationBag,
        uint256[][][] memory reallocationTable
    ) private {
        // Get asset group and corresponding exchange rates.
        address[] memory assetGroup = reallocationBag.assetGroupRegistry.listAssetGroup(reallocationBag.assetGroupId);
        uint256[] memory exchangeRates = SpoolUtils.getExchangeRates(assetGroup, reallocationBag.priceFeedManager);

        // Will store how much assets each strategy has to deposit.
        uint256[][] memory toDeposit = new uint256[][](strategies.length);
        for (uint256 i = 0; i < strategies.length; ++i) {
            toDeposit[i] = new uint256[](assetGroup.length + 1); // amount of assets to deposit into strategy i || something to deposit
        }

        // Distribute matched shares and withdraw unamatched ones.
        for (uint256 i = 0; i < strategies.length; ++i) {
            // Calculate amount of shares to distribute and amount of shares to redeem.
            uint256 sharesToRedeem;
            uint256 totalUnmatchedWithdrawals;

            {
                uint256[] memory totals = new uint256[](2);
                // totals[0] -> total withdrawals
                // totals[1] -> total matched withdrawals

                for (uint256 j = 0; j < strategies.length; ++j) {
                    totals[0] += reallocationTable[i][j][0];

                    // Take smaller for matched withdrawals.
                    if (reallocationTable[i][j][0] > reallocationTable[j][i][0]) {
                        totals[1] += reallocationTable[j][i][0];
                    } else {
                        totals[1] += reallocationTable[i][j][0];
                    }
                }

                // Unmatched withdrawals are difference between total and matched withdrawals.
                totalUnmatchedWithdrawals = totals[0] - totals[1];

                if (totals[0] == 0) {
                    // There is nothing to withdraw from strategy i.
                    continue;
                }

                // Calculate amount of shares to redeem and to distribute.
                uint256 sharesToDistribute =
                    IStrategy(strategies[i]).totalSupply() * totals[0] / IStrategy(strategies[i]).totalUsdValue();
                sharesToRedeem = sharesToDistribute * (totals[0] - totals[1]) / totals[0];
                sharesToDistribute -= sharesToRedeem;

                // Distribute matched shares to matched strategies.
                if (sharesToDistribute > 0) {
                    for (uint256 j = 0; j < strategies.length; ++j) {
                        uint256 matched;

                        // Take smaller for matched withdrawals.
                        if (reallocationTable[i][j][0] > reallocationTable[j][i][0]) {
                            matched = reallocationTable[j][i][0];
                        } else {
                            matched = reallocationTable[i][j][0];
                        }

                        if (matched == 0) {
                            continue;
                        }

                        // Give shares to strategy j.
                        reallocationTable[j][i][1] = sharesToDistribute * matched / totals[1];

                        sharesToDistribute -= reallocationTable[j][i][1]; // dust-less calculation
                        totals[1] -= matched;
                    }
                }
            }

            if (sharesToRedeem == 0) {
                // There is nothing to withdraw for strategy i.
                continue;
            }

            // Withdraw assets from underlying protocol.
            uint256[] memory withdrawnAssets = IStrategy(strategies[i]).redeemFast(
                sharesToRedeem,
                address(reallocationBag.masterWallet), // TODO: maybe have a clean bucket for reallocation
                assetGroup,
                exchangeRates,
                reallocationBag.priceFeedManager
            );

            // Distribute withdrawn assets to strategies according to reallocation table.
            for (uint256 j = 0; j < strategies.length; ++j) {
                if (reallocationTable[i][j][0] <= reallocationTable[j][i][0]) {
                    // Nothing to deposit into strategy j.
                    continue;
                }

                for (uint256 k = 0; k < assetGroup.length; ++k) {
                    // Find out how much of asset k should go to strategy j.
                    uint256 depositAmount = withdrawnAssets[k]
                        * (reallocationTable[i][j][0] - reallocationTable[j][i][0]) / totalUnmatchedWithdrawals;
                    toDeposit[j][k] += depositAmount;
                    // Mark that there is something to deposit for strategy j.
                    toDeposit[j][assetGroup.length] += 1;

                    // Use this table to temporarily store value deposited from strategy i to strategy j.
                    reallocationTable[i][j][2] += reallocationBag.priceFeedManager.assetToUsdCustomPrice(
                        assetGroup[k], depositAmount, exchangeRates[k]
                    );

                    withdrawnAssets[k] -= depositAmount; // dust-less calculation
                }
                totalUnmatchedWithdrawals -= (reallocationTable[i][j][0] - reallocationTable[j][i][0]); // dust-less calculation
            }
        }

        // Deposit assets into the underlying protocols.
        for (uint256 i = 0; i < strategies.length; ++i) {
            if (toDeposit[i][assetGroup.length] == 0) {
                // There is nothing to deposit for this strategy.
                continue;
            }

            // Transfer assets from master wallet to the strategy for the deposit.
            for (uint256 j = 0; j < assetGroup.length; ++j) {
                reallocationBag.masterWallet.transfer(IERC20(assetGroup[j]), strategies[i], toDeposit[i][j]);
            }

            // Do the deposit.
            uint256 mintedSsts =
                IStrategy(strategies[i]).depositFast(assetGroup, exchangeRates, reallocationBag.priceFeedManager);

            // Figure total value of assets gathered to be deposited.
            uint256 totalDepositedValue =
                reallocationBag.priceFeedManager.assetToUsdCustomPriceBulk(assetGroup, toDeposit[i], exchangeRates);

            // Distribute the minted shares to strategies that deposited into this strategy.
            for (uint256 j = 0; j < strategies.length; ++j) {
                if (reallocationTable[j][i][2] == 0) {
                    // No shares to give to strategy j.
                    continue;
                }

                // Calculate amount of shares to give to strategy j.
                uint256 shares = mintedSsts * reallocationTable[j][i][2] / totalDepositedValue;

                mintedSsts -= shares; // dust-less calculation
                totalDepositedValue -= reallocationTable[j][i][2]; // dust-less calculation

                // Overwrite this table with amount of given shares.
                reallocationTable[j][i][2] = shares;
            }
        }
    }

    function claimShares(
        address[] calldata smartVaults,
        address[] calldata strategies,
        uint256[][] memory strategyMapping,
        uint256[][][] memory reallocationTable,
        uint256[][][] memory reallocations
    ) private {
        // Loop over smart vaults.
        for (uint256 i = 0; i < smartVaults.length; ++i) {
            // Number of strategies for this smart vault.
            uint256 smartVaultStrategiesLength = strategyMapping[i].length;

            // Will store amount of shares to claim from each strategy,
            // plus two temporary variables used in the calculation.
            uint256[] memory toClaim = new uint256[](smartVaultStrategiesLength+2);

            // Find strategies that needed withdrawal.
            for (uint256 j = 0; j < smartVaultStrategiesLength; ++j) {
                if (reallocations[i][0][j] == 0) {
                    // Strategy didn't need any withdrawal.
                    continue;
                }

                // Merging two uints into an array due to stack depth.
                uint256[] memory values = new uint256[](2);
                values[0] = reallocations[i][0][j]; // value to withdraw from strategy
                values[1] = reallocations[i][1][smartVaultStrategiesLength]; // total value to deposit

                // Find strategiest that needed deposit.
                for (uint256 k = 0; k < smartVaultStrategiesLength; ++k) {
                    if (reallocations[i][1][k] == 0) {
                        // Strategy k had no deposits planned.
                        continue;
                    }

                    // Find value that should have moved from strategy j to k.
                    uint256 valueToDeposit = values[0] * reallocations[i][1][k] / values[1];

                    // Figure out amount strategy shares to claim:
                    // - matched shares
                    toClaim[smartVaultStrategiesLength] = reallocationTable[strategyMapping[i][j]][strategyMapping[i][k]][1]
                        * valueToDeposit / reallocationTable[strategyMapping[i][j]][strategyMapping[i][k]][0];
                    // - unmatched
                    toClaim[smartVaultStrategiesLength + 1] = reallocationTable[strategyMapping[i][j]][strategyMapping[i][k]][2]
                        * valueToDeposit / reallocationTable[strategyMapping[i][j]][strategyMapping[i][k]][0];

                    reallocationTable[strategyMapping[i][j]][strategyMapping[i][k]][0] -= valueToDeposit; // dust-less calculation - reallocation level
                    reallocationTable[strategyMapping[i][j]][strategyMapping[i][k]][1] -=
                        toClaim[smartVaultStrategiesLength];
                    reallocationTable[strategyMapping[i][j]][strategyMapping[i][k]][2] -=
                        toClaim[smartVaultStrategiesLength + 1];

                    values[0] -= valueToDeposit; // dust-less calculation - smart vault level
                    values[1] -= reallocations[i][1][k];

                    // Total amount of strategy k shares to claim by this smart vault.
                    toClaim[k] += toClaim[smartVaultStrategiesLength] + toClaim[smartVaultStrategiesLength + 1];
                }
            }

            // Claim strategy shares.
            for (uint256 j = 0; j < smartVaultStrategiesLength; ++j) {
                if (toClaim[j] == 0) {
                    // No shares to claim for strategy j.
                    continue;
                }

                IStrategy(strategies[strategyMapping[i][j]]).claimShares(smartVaults[i], toClaim[j]);
            }
        }
    }
}