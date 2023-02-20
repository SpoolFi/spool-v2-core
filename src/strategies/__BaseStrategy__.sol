// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./Strategy.sol";

contract __BaseStrategy__ is Strategy {
    using SafeERC20 for IERC20;

    constructor(string memory name_, IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_)
        Strategy(name_, assetGroupRegistry_, accessControl_)
    {}

    function initialize(uint256 assetGroupId_) external initializer {
        __Strategy_init(assetGroupId_);
        // TODO
    }

    function assetRatio() external view override returns (uint256[] memory) {
        // TODO
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public view override {
        // TODO
    }

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public view override {
        // TODO
    }

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata slippages)
        internal
        override
    {
        // TODO
    }

    function _redeemFromProtocol(address[] calldata tokens, uint256 ssts, uint256[] calldata slippages)
        internal
        override
    {
        // TODO
    }

    function _emergencyWithdrawImpl(uint256[] calldata slippages, address recipient) internal override {
        // TODO
    }

    function _compound(address[] calldata tokens, SwapInfo[] calldata compoundSwapInfo, uint256[] calldata slippages)
        internal
        override
        returns (int256 compoundYield)
    {
        // TODO
    }

    function _getYieldPercentage(int256 manualYield) internal override returns (int256) {
        // TODO
    }

    function _swapAssets(address[] memory tokens, uint256[] memory toSwap, SwapInfo[] calldata swapInfo)
        internal
        override
    {
        // TODO
    }

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        override
        returns (uint256)
    {
        // TODO
    }
}
