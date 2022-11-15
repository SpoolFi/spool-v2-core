// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/ISmartVaultManager.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/ISwapper.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

library SmartVaultUtils {
    function getStrategyRatios(address[] memory strategies_) public view returns (uint256[][] memory) {
        uint256[][] memory ratios = new uint256[][](strategies_.length);
        for (uint256 i = 0; i < strategies_.length; i++) {
            ratios[i] = IStrategy(strategies_[i]).assetRatio();
        }

        return ratios;
    }

    function getExchangeRates(address[] memory tokens, IUsdPriceFeedManager _priceFeedManager)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory exchangeRates = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            exchangeRates[i] = _priceFeedManager.assetToUsd(tokens[i], 10 ** _priceFeedManager.assetDecimals(tokens[i]));
        }

        return exchangeRates;
    }

    /**
     * @dev Gets revert message when a low-level call reverts, so that it can
     * be bubbled-up to caller.
     * @param _returnData Data returned from reverted low-level call.
     * @return Revert message.
     */
    function getRevertMsg(bytes memory _returnData) public pure returns (string memory) {
        // if the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) {
            return "SmartVaultManager::_getRevertMsg: Transaction reverted silently.";
        }

        assembly {
            // slice the sig hash
            _returnData := add(_returnData, 0x04)
        }

        return abi.decode(_returnData, (string)); // all that remains is the revert string
    }

    function getBalances(address[] memory tokens, address wallet) public view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = IERC20(tokens[i]).balanceOf(wallet);
        }

        return balances;
    }

    function assetsToUSD(address[] memory tokens, uint256[] memory assets, IUsdPriceFeedManager priceFeedManager)
        public
        view
        returns (uint256)
    {
        uint256 usdTotal = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            usdTotal = priceFeedManager.assetToUsd(tokens[i], assets[i]);
        }

        return usdTotal;
    }
}

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
        uint256[] memory oldBalances = SmartVaultUtils.getBalances(bag.tokens, bag.masterWallet);
        for (uint256 i; i < swapInfo.length; i++) {
            _swap(swapInfo[i], IMasterWallet(bag.masterWallet), ISwapper(bag.swapper));
        }
        uint256[] memory newBalances = SmartVaultUtils.getBalances(bag.tokens, bag.masterWallet);
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

    function _swap(SwapInfo memory _swapInfo, IMasterWallet _masterWallet, ISwapper _swapper) private {
        _masterWallet.approve(IERC20(_swapInfo.token), _swapInfo.swapTarget, _swapInfo.amountIn);
        _swapper.swap(_swapInfo);
        _masterWallet.resetApprove(IERC20(_swapInfo.token), _swapInfo.swapTarget);
    }
}
