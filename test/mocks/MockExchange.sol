// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../src/interfaces/IUsdPriceFeedManager.sol";

contract MockExchange {
    using SafeERC20 for IERC20;

    IERC20 tokenA;
    IERC20 tokenB;
    IUsdPriceFeedManager priceFeedManager;

    constructor(IERC20 tokenA_, IERC20 tokenB_, IUsdPriceFeedManager priceFeedManager_) {
        tokenA = tokenA_;
        tokenB = tokenB_;
        priceFeedManager = priceFeedManager_;
    }

    function test_mock() external pure {}

    function swap(address token, uint256 amount, address recipient) external returns (uint256) {
        uint256 out = 0;
        IERC20 source;
        IERC20 target;

        uint256 usdDecimals = priceFeedManager.usdDecimals();
        uint256 exchangeRate = priceFeedManager.assetToUsd(address(tokenA), 1 ether) * 10 ** usdDecimals
            / priceFeedManager.assetToUsd(address(tokenB), 1 ether);

        if (address(token) == address(tokenA)) {
            source = tokenA;
            target = tokenB;
            out = amount * exchangeRate / 10 ** usdDecimals;
        } else if (address(token) == address(tokenB)) {
            source = tokenB;
            target = tokenA;
            out = amount * 10 ** usdDecimals / exchangeRate;
        } else {
            revert("Invalid token");
        }

        source.safeTransferFrom(msg.sender, address(this), amount);
        target.safeTransfer(recipient, out);

        return out;
    }
}
