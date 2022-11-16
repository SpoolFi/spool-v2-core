// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/ISwapper.sol";
import "../interfaces/IStrategy.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

library SpoolUtils {
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
            usdTotal += priceFeedManager.assetToUsd(tokens[i], assets[i]);
        }

        return usdTotal;
    }
}
