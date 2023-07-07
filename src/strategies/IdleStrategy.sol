// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/utils/math/SafeCast.sol";
import "../external/interfaces/strategies/idle/IIdleToken.sol";
import "../libraries/PackedRange.sol";
import "./Strategy.sol";

error IdleBeforeDepositCheckFailed();
error IdleBeforeRedeemalCheckFailed();
error IdleDepositSlippagesFailed();
error IdleRedeemSlippagesFailed();
error IdleCompoundSlippagesFailed();

// one asset
// multiple rewards
// slippages
// - mode selection: slippages[0]
// - DHW with deposit: slippages[0] == 0
//   - beforeDepositCheck: slippages[1]
//   - beforeRedeemalCheck: slippages[2]
//   - compound: slippages[3]
//   - _depositToProtocol: slippages[4]
// - DHW with withdrawal: slippages[0] == 1
//   - beforeDepositCheck: slippages[1]
//   - beforeRedeemalCheck: slippages[2]
//   - compound: slippages[3]
//   - _redeemFromProtocol: slippages[4]
// - reallocate: slippages[0] == 2
//   - beforeDepositCheck: depositSlippages[1]
//   - _depositToProtocol: depositSlippages[2]
//   - beforeRedeemalCheck: withdrawalSlippages[1]
//   - _redeemFromProtocol: withdrawalSlippages[2]
// - redeemFast or emergencyWithdraw: slippages[0] == 3
//   - _redeemFromProtocol or _emergencyWithdrawImpl: slippages[1]
contract IdleStrategy is Strategy {
    using SafeERC20 for IERC20;

    ISwapper public immutable swapper;

    IIdleToken public idleToken;
    uint96 public oneShare;

    uint256 private _lastIdleTokenPrice;

    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, ISwapper swapper_)
        Strategy(assetGroupRegistry_, accessControl_, NULL_ASSET_GROUP_ID)
    {
        swapper = swapper_;
    }

    function initialize(string memory strategyName_, uint256 assetGroupId_, IIdleToken idleToken_)
        external
        initializer
    {
        __Strategy_init(strategyName_, assetGroupId_);

        if (address(idleToken_) == address(0)) {
            revert ConfigurationAddressZero();
        }

        idleToken = idleToken_;
        oneShare = SafeCast.toUint96(10 ** idleToken_.decimals());

        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId_);

        if (tokens.length != 1 || tokens[0] != idleToken.token()) {
            revert InvalidAssetGroup(assetGroupId_);
        }

        _lastIdleTokenPrice = idleToken.tokenPriceWithFee(address(this));
    }

    function assetRatio() external pure override returns (uint256[] memory) {
        uint256[] memory _assetRatio = new uint256[](1);
        _assetRatio[0] = 1;
        return _assetRatio;
    }

    function getUnderlyingAssetAmounts() external view returns (uint256[] memory amounts) {
        amounts = new uint256[](1);
        amounts[0] = idleToken.tokenPriceWithFee(address(this)) * idleToken.balanceOf(address(this)) / oneShare;
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public override {
        if (_isViewExecution()) {
            uint256[] memory beforeDepositCheckSlippageAmounts = new uint256[](1);
            beforeDepositCheckSlippageAmounts[0] = amounts[0];

            emit BeforeDepositCheckSlippages(beforeDepositCheckSlippageAmounts);
            return;
        }

        if (slippages[0] > 2) {
            revert IdleBeforeDepositCheckFailed();
        }

        if (!PackedRange.isWithinRange(slippages[1], amounts[0])) {
            revert IdleBeforeDepositCheckFailed();
        }
    }

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public override {
        if (_isViewExecution()) {
            emit BeforeRedeemalCheckSlippages(ssts);
            return;
        }

        uint256 slippage;
        if (slippages[0] < 2) {
            slippage = slippages[2];
        } else if (slippages[0] == 2) {
            slippage = slippages[1];
        } else {
            revert IdleBeforeRedeemalCheckFailed();
        }

        if (!PackedRange.isWithinRange(slippage, ssts)) {
            revert IdleBeforeRedeemalCheckFailed();
        }
    }

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata slippages)
        internal
        override
    {
        uint256 slippage;
        if (slippages[0] == 0) {
            slippage = slippages[4];
        } else if (slippages[0] == 2) {
            slippage = slippages[2];
        } else {
            revert IdleDepositSlippagesFailed();
        }

        _depositToIdle(tokens[0], amounts[0], slippage);
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata slippages) internal override {
        uint256 slippage;
        if (slippages[0] == 1) {
            slippage = slippages[4];
        } else if (slippages[0] == 2) {
            slippage = slippages[2];
        } else if (slippages[0] == 3) {
            slippage = slippages[1];
        } else if (_isViewExecution()) {} else {
            revert IdleRedeemSlippagesFailed();
        }

        uint256 idleTokensToRedeem = idleToken.balanceOf(address(this)) * ssts / totalSupply();
        _redeemFromIdle(idleTokensToRedeem, slippage);
    }

    function _emergencyWithdrawImpl(uint256[] calldata slippages, address recipient) internal override {
        if (slippages[0] != 3) {
            revert IdleRedeemSlippagesFailed();
        }

        uint256 assetsWithdrawn = _redeemFromIdle(idleToken.balanceOf((address(this))), slippages[1]);

        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId());
        IERC20(tokens[0]).safeTransfer(recipient, assetsWithdrawn);
    }

    function _compound(address[] calldata tokens, SwapInfo[] calldata compoundSwapInfo, uint256[] calldata slippages)
        internal
        override
        returns (int256 compoundYield)
    {
        if (compoundSwapInfo.length == 0) {
            return compoundYield;
        }

        if (slippages[0] > 1) {
            revert IdleCompoundSlippagesFailed();
        }

        (address[] memory govTokens,) = _getProtocolRewardsInternal();

        uint256 swappedAmount = swapper.swap(govTokens, compoundSwapInfo, tokens, address(this))[0];

        uint256 idleTokensBefore = idleToken.balanceOf(address(this));

        uint256 idleTokensMinted = _depositToIdle(tokens[0], swappedAmount, slippages[3]);

        compoundYield = int256(YIELD_FULL_PERCENT * idleTokensMinted / idleTokensBefore);
    }

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        uint256 currentIdleTokenPrice = idleToken.tokenPriceWithFee(address(this));

        baseYieldPercentage = _calculateYieldPercentage(_lastIdleTokenPrice, currentIdleTokenPrice);

        _lastIdleTokenPrice = currentIdleTokenPrice;
    }

    function _swapAssets(address[] memory, uint256[] memory, SwapInfo[] calldata) internal override {}

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256)
    {
        uint256 assetWorth = idleToken.tokenPriceWithFee(address(this)) * idleToken.balanceOf(address(this)) / oneShare;
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId());

        return priceFeedManager.assetToUsdCustomPrice(tokens[0], assetWorth, exchangeRates[0]);
    }

    function _depositToIdle(address token, uint256 amount, uint256 slippage) private returns (uint256) {
        _resetAndApprove(IERC20(token), address(idleToken), amount);

        uint256 mintedIdleTokens = idleToken.mintIdleToken(
            amount,
            true, // not used by the protocol, can be anything
            address(this)
        );

        if (mintedIdleTokens < slippage) {
            revert IdleDepositSlippagesFailed();
        }

        if (_isViewExecution()) {
            emit Slippages(true, mintedIdleTokens, "");
        }

        return mintedIdleTokens;
    }

    function _redeemFromIdle(uint256 idleTokens, uint256 slippage) private returns (uint256) {
        uint256 redeemedAssets = idleToken.redeemIdleToken(idleTokens);

        if (redeemedAssets < slippage) {
            revert IdleRedeemSlippagesFailed();
        }

        if (_isViewExecution()) {
            emit Slippages(false, redeemedAssets, "");
        }

        return redeemedAssets;
    }

    function _getProtocolRewardsInternal() internal virtual override returns (address[] memory, uint256[] memory) {
        address[] memory govTokens = idleToken.getGovTokens();
        uint256[] memory balances = new uint256[](govTokens.length);

        idleToken.redeemIdleToken(0);

        for (uint256 i; i < govTokens.length; ++i) {
            uint256 balance = IERC20(govTokens[i]).balanceOf(address(this));

            if (balance > 0) {
                IERC20(govTokens[i]).safeTransfer(address(swapper), balance);
            }

            balances[i] = balance;
        }

        return (govTokens, balances);
    }
}
