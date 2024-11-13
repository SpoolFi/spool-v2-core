// Mock strategy for testnet. WILL NOT BE USED IN PRODUCTION.
// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../Strategy.sol";
import "./MockProtocol.sol";

contract MockProtocolStrategy is Strategy {
    using SafeERC20 for IERC20;

    MockProtocol public protocol;

    uint256 _lastAccumulator;

    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, MockProtocol protocol_)
        Strategy(assetGroupRegistry_, accessControl_, NULL_ASSET_GROUP_ID)
    {
        protocol = protocol_;
    }

    function initialize(string memory strategyName_, uint256 assetGroupId_) external initializer {
        __Strategy_init(strategyName_, assetGroupId_);

        (, _lastAccumulator,,) = protocol.update(address(this));
    }

    function assetRatio() external pure override returns (uint256[] memory) {
        uint256[] memory _assetRatio = new uint256[](1);
        _assetRatio[0] = 1;
        return _assetRatio;
    }

    function getUnderlyingAssetAmounts() external view returns (uint256[] memory amounts) {
        uint256 balance = protocol.balanceOf(address(this));

        amounts = new uint[](1);
        amounts[0] = balance;
    }

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        (, uint256 accumulator,,) = protocol.update(address(this));
        if (_lastAccumulator == 0) {
            return int256(accumulator);
        }

        baseYieldPercentage = _calculateYieldPercentage(_lastAccumulator, accumulator);

        _lastAccumulator = accumulator;
    }

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata)
        internal
        override
    {
        if (amounts[0] > 0) {
            _resetAndApprove(IERC20(tokens[0]), address(protocol), amounts[0]);
            protocol.deposit(amounts[0]);
        }
    }

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256)
    {
        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupId());
        uint256 balance = protocol.balanceOf(address(this));

        uint256 usdWorth = priceFeedManager.assetToUsdCustomPrice(assetGroup[0], balance, exchangeRates[0]);

        return usdWorth;
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata) internal override {
        if (ssts == 0) {
            return;
        }

        (uint256 shares,,) = protocol.users(address(this));

        uint256 toWithdraw = shares * ssts / totalSupply();

        protocol.withdraw(toWithdraw);
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public view override {}

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public view override {}

    function _emergencyWithdrawImpl(uint256[] calldata, address recipient) internal override {
        (uint256 shares,,) = protocol.users(address(this));

        IERC20 token = IERC20(assets()[0]);

        uint256 balanceBefore = token.balanceOf(address(this));
        protocol.withdraw(shares);
        uint256 withdrawn = token.balanceOf(address(this)) - balanceBefore;

        token.safeTransfer(recipient, withdrawn);
    }

    function _compound(address[] calldata, SwapInfo[] calldata, uint256[] calldata)
        internal
        override
        returns (int256)
    {}

    function _getProtocolRewardsInternal()
        internal
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {}

    function _swapAssets(address[] memory tokens, uint256[] memory toSwap, SwapInfo[] calldata swapInfo)
        internal
        override
    {}
}
