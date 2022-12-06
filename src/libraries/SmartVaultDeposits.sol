// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "../interfaces/CommonErrors.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/ISmartVaultManager.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/ISwapper.sol";
import "../libraries/SpoolUtils.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

/**
 * @notice Used when deposit is not made in correct asset ratio.
 */
error IncorrectDepositRatio();

struct DepositQueryBag1 {
    uint256[] deposit;
    uint256[] exchangeRates;
    uint256[] allocation;
    uint256[][] strategyRatios;
}

library SmartVaultDeposits {
    uint256 constant PRECISSION_MULTIPLIER = 10 ** 42;
    uint256 constant DEPOSIT_TOLERANCE = 50;
    uint256 constant FULL_PERCENT = 100_00;

    function distributeDeposit(DepositQueryBag1 memory bag) public pure returns (uint256[][] memory) {
        uint256[][] memory flushFactors = calculateFlushFactors(bag.exchangeRates, bag.allocation, bag.strategyRatios);
        uint256[] memory idealDepositRatio = _calculateDepositRatioFromFlushFactors(flushFactors);

        uint256[] memory distributed = new uint256[](bag.deposit.length);
        uint256[][] memory distribution = new uint256[][](bag.allocation.length);

        // loop over strategies
        for (uint256 i = 0; i < bag.allocation.length; i++) {
            distribution[i] = new uint256[](bag.exchangeRates.length);

            // loop over assets
            for (uint256 j = 0; j < bag.exchangeRates.length; j++) {
                distribution[i][j] = bag.deposit[j] * flushFactors[i][j] / idealDepositRatio[j];
                distributed[j] += distribution[i][j];
            }
        }

        // handle dust
        for (uint256 j = 0; j < bag.exchangeRates.length; j++) {
            distribution[0][j] += bag.deposit[j] - distributed[j];
        }

        return distribution;
    }

    function checkDepositRatio(
        uint256[] memory deposit,
        uint256[] memory exchangeRates,
        uint256[] memory allocation,
        uint256[][] memory strategyRatios
    ) public view {
        if (deposit.length == 1) {
            return;
        }

        uint256[] memory idealDeposit = calculateDepositRatio(exchangeRates, allocation, strategyRatios);

        // loop over assets
        for (uint256 i = 1; i < deposit.length; i++) {
            uint256 valueA = deposit[i] * idealDeposit[i - 1];
            uint256 valueB = deposit[i - 1] * idealDeposit[i];

            if ( // check if valueA is within DEPOSIT_TOLERANCE of valueB
                valueA < (valueB * (FULL_PERCENT - DEPOSIT_TOLERANCE) / FULL_PERCENT)
                    || valueA > (valueB * (FULL_PERCENT + DEPOSIT_TOLERANCE) / FULL_PERCENT)
            ) {
                revert IncorrectDepositRatio();
            }
        }
    }

    function calculateDepositRatio(
        uint256[] memory exchangeRates,
        uint256[] memory allocation,
        uint256[][] memory strategyRatios
    ) public pure returns (uint256[] memory) {
        return _calculateDepositRatioFromFlushFactors(calculateFlushFactors(exchangeRates, allocation, strategyRatios));
    }

    function calculateFlushFactors(
        uint256[] memory exchangeRates,
        uint256[] memory allocation,
        uint256[][] memory strategyRatios
    ) public pure returns (uint256[][] memory) {
        uint256[][] memory flushFactors = new uint256[][](allocation.length);

        // loop over strategies
        for (uint256 i = 0; i < allocation.length; i++) {
            flushFactors[i] = new uint256[](exchangeRates.length);

            uint256 normalization = 0;
            // loop over assets
            for (uint256 j = 0; j < exchangeRates.length; j++) {
                normalization += strategyRatios[i][j] * exchangeRates[j];
            }

            // loop over assets
            for (uint256 j = 0; j < exchangeRates.length; j++) {
                flushFactors[i][j] = allocation[i] * strategyRatios[i][j] * PRECISSION_MULTIPLIER / normalization;
            }
        }

        return flushFactors;
    }

    function _calculateDepositRatioFromFlushFactors(uint256[][] memory flushFactors)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory depositRatio = new uint256[](flushFactors[0].length);

        // loop over strategies
        for (uint256 i = 0; i < flushFactors.length; i++) {
            // loop over assets
            for (uint256 j = 0; j < flushFactors[i].length; j++) {
                depositRatio[j] += flushFactors[i][j];
            }
        }

        return depositRatio;
    }
}
