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

library SmartVaultDeposits {
    /// @notice Deposit ratio precision
    uint256 constant RATIO_PRECISION = 10 ** 22;

    /// @notice Vault-strategy allocation precision
    uint256 constant ALLOC_PRECISION = 1000;

    /// @notice Difference between desired and actual amounts in WEI after swapping
    uint256 constant SWAP_TOLERANCE = 500;

    /**
     * @notice Calculate current Smart Vault asset deposit ratio
     * @dev As described in /notes/multi-asset-vault-deposit-ratios.md
     */
    function getDepositRatio(DepositRatioQueryBag memory bag) external pure returns (uint256[] memory) {
        uint256[] memory outRatios = new uint256[](bag.tokens.length);

        if (bag.tokens.length == 1) {
            outRatios[0] = 1;
            return outRatios;
        }

        uint256[][] memory ratios = _getDepositRatios(bag);
        for (uint256 i = 0; i < bag.strategies.length; i++) {
            for (uint256 j = 0; j < bag.tokens.length; j++) {
                outRatios[j] += ratios[i][j];
            }
        }

        for (uint256 j = bag.tokens.length; j > 0; j--) {
            outRatios[j - 1] = outRatios[j - 1] * RATIO_PRECISION / outRatios[0];
        }

        return outRatios;
    }

    /**
     * @notice Calculate Smart Vault deposit distributions for underlying strategies based on their
     * internal ratio.
     * @param bag Deposit specific parameters
     * @param swapInfo Information needed to perform asset swaps
     * @return Token deposit amounts per strategy
     */
    function distributeVaultDeposits(
        DepositRatioQueryBag memory bag,
        uint256[] memory depositsIn,
        SwapInfo[] calldata swapInfo
    ) external returns (uint256[][] memory) {
        if (bag.tokens.length != depositsIn.length) revert InvalidAssetLengths();

        uint256[] memory decimals = new uint256[](bag.tokens.length);
        uint256[][] memory depositRatios;
        uint256 depositUSD = 0;

        depositRatios = _getDepositRatios(bag);

        for (uint256 j = 0; j < bag.tokens.length; j++) {
            decimals[j] = ERC20(bag.tokens[j]).decimals();
            depositUSD += bag.exchangeRates[j] * depositsIn[j] / 10 ** decimals[j];
        }

        DepositBag memory depositBag = DepositBag(
            bag.tokens,
            bag.strategies,
            depositsIn,
            decimals,
            bag.exchangeRates,
            depositRatios,
            depositUSD,
            bag.usdDecimals,
            bag.masterWallet,
            bag.swapper
        );

        depositBag.depositsIn = _swapToRatio(depositBag, swapInfo);
        return _distributeAcrossStrategies(depositBag);
    }

    /**
     * @notice Swap to match required ratio
     * TODO: take slippage into consideration
     * TODO: check if "swap" feature is exploitable
     */
    function _swapToRatio(DepositBag memory bag, SwapInfo[] memory swapInfo) internal returns (uint256[] memory) {
        // Swap tokens:
        // - check initial balances of tokens
        uint256[] memory oldBalances = SpoolUtils.getBalances(bag.tokens, bag.masterWallet);
        if (swapInfo.length > 0) {
            // - transfer tokens to the swapper contract
            for (uint256 i = 0; i < bag.tokens.length; i++) {
                IMasterWallet(bag.masterWallet).transfer(IERC20(bag.tokens[i]), bag.swapper, bag.depositsIn[i]);
            }
            // - make swap
            ISwapper(bag.swapper).swap(bag.tokens, swapInfo, bag.masterWallet);
        }
        // - check final balances
        uint256[] memory newBalances = SpoolUtils.getBalances(bag.tokens, bag.masterWallet);

        uint256[] memory depositsOut = new uint256[](bag.tokens.length);
        for (uint256 i = 0; i < bag.tokens.length; i++) {
            uint256 ratio = 0;

            for (uint256 j = 0; j < bag.depositRatios.length; j++) {
                ratio += bag.depositRatios[j][i];
            }

            // Add/Subtract swapped amounts
            if (newBalances[i] >= oldBalances[i]) {
                depositsOut[i] = bag.depositsIn[i] + (newBalances[i] - oldBalances[i]);
            } else {
                depositsOut[i] = bag.depositsIn[i] - (oldBalances[i] - newBalances[i]);
            }

            // Desired token deposit amount
            uint256 desired = ratio * bag.depositUSD * 10 ** bag.decimals[i] / 10 ** bag.usdDecimals / RATIO_PRECISION;

            // Check discrepancies
            bool isOk = desired == depositsOut[i]
                || desired > depositsOut[i] && (desired - depositsOut[i]) < SWAP_TOLERANCE
                || desired < depositsOut[i] && (depositsOut[i] - desired) < SWAP_TOLERANCE;

            if (!isOk) {
                revert IncorrectDepositRatio();
            }
        }

        return depositsOut;
    }

    function _distributeAcrossStrategies(DepositBag memory bag) internal pure returns (uint256[][] memory) {
        uint256[] memory depositAccum = new uint256[](bag.tokens.length);
        uint256[][] memory strategyDeposits = new uint256[][](bag.strategies.length);
        uint256 usdPrecision = 10 ** bag.usdDecimals;

        for (uint256 i = 0; i < bag.strategies.length; i++) {
            strategyDeposits[i] = new uint256[](bag.tokens.length);

            for (uint256 j = 0; j < bag.tokens.length; j++) {
                uint256 tokenPrecision = 10 ** bag.decimals[j];
                strategyDeposits[i][j] =
                    bag.depositUSD * bag.depositRatios[i][j] * tokenPrecision / RATIO_PRECISION / usdPrecision;
                depositAccum[j] += strategyDeposits[i][j];

                // Dust
                if (i == bag.strategies.length - 1) {
                    strategyDeposits[i][j] += bag.depositsIn[j] - depositAccum[j];
                }
            }
        }

        return strategyDeposits;
    }

    function _getDepositRatios(DepositRatioQueryBag memory bag) internal pure returns (uint256[][] memory) {
        uint256[][] memory outRatios = new uint256[][](bag.strategies.length);
        if (bag.strategies.length != bag.allocations.length) revert InvalidArrayLength();

        uint256 usdPrecision = 10 ** bag.usdDecimals;

        for (uint256 i = 0; i < bag.strategies.length; i++) {
            outRatios[i] = new uint256[](bag.tokens.length);
            uint256 ratioNorm = 0;

            for (uint256 j = 0; j < bag.tokens.length; j++) {
                ratioNorm += bag.exchangeRates[j] * bag.strategyRatios[i][j];
            }

            for (uint256 j = 0; j < bag.tokens.length; j++) {
                outRatios[i][j] += bag.allocations[i] * bag.strategyRatios[i][j] * usdPrecision * RATIO_PRECISION
                    / ratioNorm / ALLOC_PRECISION;
            }
        }

        return outRatios;
    }
}
