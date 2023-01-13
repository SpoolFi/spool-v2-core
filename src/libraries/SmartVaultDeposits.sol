// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "../interfaces/CommonErrors.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/ISmartVaultManager.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/IStrategy.sol";
import "../libraries/SpoolUtils.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

/**
 * @notice Used when deposit is not made in correct asset ratio.
 */
error IncorrectDepositRatio();

/**
 * @notice Contains parameters for distributeDeposit call.
 * @custom:member deposit Amounts deposited.
 * @custom:member exchangeRates Asset -> USD exchange rates.
 * @custom:member allocation Required allocation of value between different strategies.
 * @custom:member strategyRatios Required ratios between assets for each strategy.
 */
struct DepositQueryBag1 {
    uint256[] deposit;
    uint256[] exchangeRates;
    uint256[] allocation;
    uint256[][] strategyRatios;
}

library SmartVaultDeposits {
    /**
     * @dev Precission multiplier for internal calculations.
     */
    uint256 constant PRECISION_MULTIPLIER = 10 ** 42;

    /**
     * @dev Relative tolerance for deposit ratio compared to ideal ratio.
     * Equals to 0.5%/
     */
    uint256 constant DEPOSIT_TOLERANCE = 50;

    /**
     * @dev Represents full percent.
     * - 100_00 -> 100%
     * - 1_00 -> 1%
     * - 1 -> 0.01%
     */
    uint256 constant FULL_PERCENT = 100_00;

    /**
     * @notice Calculates fair distribution of deposit among strategies.
     * @param bag Parameter bag.
     * @return Distribution of deposits, with first index running over strategies and second index running over assets.
     */
    function distributeDeposit(DepositQueryBag1 memory bag) public pure returns (uint256[][] memory) {
        if (bag.deposit.length == 1) {
            return _distributeDepositSingleAsset(bag);
        } else {
            return _distributeDepositMultipleAssets(bag);
        }
    }

    /**
     * @notice Checks if deposit is made in correct ratio.
     * @dev Reverts with IncorrectDepositRatio if the check fails.
     * @param deposit Amounts deposited.
     * @param exchangeRates Asset -> USD exchange rates.
     * @param allocation Required allocation of value between different strategies.
     * @param strategyRatios Required ratios between assets for each strategy.
     */
    function checkDepositRatio(
        uint256[] memory deposit,
        uint256[] memory exchangeRates,
        uint256[] memory allocation,
        uint256[][] memory strategyRatios
    ) public pure {
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

    /**
     * @notice Calculates ideal deposit ratio for a smart vault.
     * @param exchangeRates Asset -> USD exchange rates.
     * @param allocation Required allocation of value between different strategies.
     * @param strategyRatios Required ratios between assets for each strategy.
     * @return Ideal deposit ratio.
     */
    function calculateDepositRatio(
        uint256[] memory exchangeRates,
        uint256[] memory allocation,
        uint256[][] memory strategyRatios
    ) public pure returns (uint256[] memory) {
        if (exchangeRates.length == 1) {
            uint256[] memory ratio = new uint256[](1);
            ratio[0] = 1;

            return ratio;
        }

        return _calculateDepositRatioFromFlushFactors(calculateFlushFactors(exchangeRates, allocation, strategyRatios));
    }

    /**
     * @dev Calculate flush factors - intermediate result.
     * @param exchangeRates Asset -> USD exchange rates.
     * @param allocation Required allocation of value between different strategies.
     * @param strategyRatios Required ratios between assets for each strategy.
     * @return Flush factors, with first index running over strategies and second index running over assets.
     */
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
                flushFactors[i][j] = allocation[i] * strategyRatios[i][j] * PRECISION_MULTIPLIER / normalization;
            }
        }

        return flushFactors;
    }

    /**
     * @dev Calculated deposit ratio from flush factors.
     * @param flushFactors Flush factors.
     * @return Deposit ratio, with first index running over strategies and second index running over assets.
     */
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

    /**
     * @dev Calculates fair distribution of single asset among strategies.
     * @param bag Parameter bag.
     * @return Distribution of deposits, with first index running over strategies and second index running over assets.
     */
    function _distributeDepositSingleAsset(DepositQueryBag1 memory bag) internal pure returns (uint256[][] memory) {
        uint256 distributed;
        uint256[][] memory distribution = new uint256[][](bag.allocation.length);

        uint256 totalAllocation;
        for (uint256 i = 0; i < bag.allocation.length; ++i) {
            totalAllocation += bag.allocation[i];
        }

        // loop over strategies
        for (uint256 i = 0; i < bag.allocation.length; ++i) {
            distribution[i] = new uint256[](1);

            distribution[i][0] = bag.deposit[0] * bag.allocation[i] / totalAllocation;
            distributed += distribution[i][0];
        }

        // handle dust
        distribution[0][0] += bag.deposit[0] - distributed;

        return distribution;
    }

    /**
     * @dev Calculates fair distribution of multiple assets among strategies.
     * @param bag Parameter bag.
     * @return Distribution of deposits, with first index running over strategies and second index running over assets.
     */
    function _distributeDepositMultipleAssets(DepositQueryBag1 memory bag) internal pure returns (uint256[][] memory) {
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
}
