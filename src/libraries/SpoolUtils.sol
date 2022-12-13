// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/utils/math/Math.sol";

library SpoolUtils {
    function getStrategyRatiosAtLastDhw(address[] memory strategies_, IStrategyRegistry strategyRegistry_)
        public
        view
        returns (uint256[][] memory)
    {
        uint256[][] memory strategyRatios = new uint256[][](strategies_.length);

        for (uint256 i = 0; i < strategies_.length; i++) {
            strategyRatios[i] = strategyRegistry_.assetRatioAtLastDhw(strategies_[i]);
        }

        return strategyRatios;
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

    function getVaultTotalUsdValue(address smartVault, address[] memory strategyAddresses)
        public
        view
        returns (uint256)
    {
        uint256 totalUsdValue = 0;

        for (uint256 i = 0; i < strategyAddresses.length; i++) {
            IStrategy strategy = IStrategy(strategyAddresses[i]);
            totalUsdValue = totalUsdValue
                + Math.mulDiv(strategy.totalUsdValue(), strategy.balanceOf(smartVault), strategy.totalSupply());
        }

        return totalUsdValue;
    }
}
