// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../external/interfaces/strategies/yearn/v2/IYearnTokenVault.sol";
import "./Strategy.sol";

error YearnV2BeforeDepositCheckFailed();
error YearnV2BeforeRedeemalCheckFailed();
error YearnV2CompoundSlippagesFailed();
error YearnV2DepositToProtocolSlippagesFailed();
error YearnV2RedeemSlippagesFailed();

// only uses one asset
// no rewards
// slippages
// - mode selection: slippages[0]
// - DHW with deposit: slippages[0] == 0
//   - beforeDepositCheck: slippages[1..2]
//   - beforeRedeemalCheck: slippages[3..4]
//   - compound: slippages[5]
//   - _depositToProtocol: slippages[6]
// - DHW with withdrawal: slippages[0] == 1
//   - beforeDepositCheck: slippages[1..2]
//   - beforeRedeemalCheck: slippages[3..4]
//   - compound: slippages[5]
//   - _redeemFromProtocol: slippages[6]
// - reallocate: slippages[0] == 2
//   - beforeDepositCheck: depositSlippages[1..2]
//   - _depositToProtocol: depositSlippages[3]
//   - beforeRedeemalCheck: withdrawalSlippages[1..2]
//   - _redeemFromProtocol: withdrawalSlippages[3]
// - redeemFast or emergencyWithdraw: slippages[0] == 3
//   - _redeemFromProtocol or _emergencyWithdrawImpl: slippages[1]
contract YearnV2Strategy is Strategy {
    using SafeERC20 for IERC20;

    IYearnTokenVault public immutable yTokenVault;

    uint256 public immutable oneShare;

    uint256 private _lastPricePerShare;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IYearnTokenVault yTokenVault_
    ) Strategy(assetGroupRegistry_, accessControl_, NULL_ASSET_GROUP_ID) {
        if (address(yTokenVault_) == address(0)) {
            revert ConfigurationAddressZero();
        }

        yTokenVault = yTokenVault_;
        oneShare = 10 ** (yTokenVault_.decimals());
    }

    function initialize(string memory name_, uint256 assetGroupId_) external initializer {
        __Strategy_init(name_, assetGroupId_);

        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId_);

        if (tokens.length != 1 || tokens[0] != yTokenVault.token()) {
            revert InvalidAssetGroup(assetGroupId_);
        }

        _lastPricePerShare = yTokenVault.pricePerShare();
    }

    function assetRatio() external pure override returns (uint256[] memory) {
        uint256[] memory _assetRatio = new uint256[](1);
        _assetRatio[0] = 1;
        return _assetRatio;
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public pure override {
        if (amounts[0] < slippages[1] || amounts[1] > slippages[2]) {
            revert YearnV2BeforeDepositCheckFailed();
        }
    }

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public pure override {
        if (
            (slippages[0] < 2 && (ssts < slippages[3] || ssts > slippages[4]))
                || (ssts < slippages[1] || ssts > slippages[2])
        ) {
            revert YearnV2BeforeRedeemalCheckFailed();
        }
    }

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata slippages)
        internal
        override
    {
        _resetAndApprove(IERC20(tokens[0]), address(yTokenVault), amounts[0]);

        uint256 mintedYearnTokens = yTokenVault.deposit(amounts[0]);

        if (
            !(
                (slippages[0] == 0 && (mintedYearnTokens >= slippages[6]))
                    || (slippages[0] == 2 && (mintedYearnTokens >= slippages[3]))
            )
        ) {
            revert YearnV2DepositToProtocolSlippagesFailed();
        }
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata slippages) internal override {
        uint256 yearnTokensToRedeem = yTokenVault.balanceOf(address(this)) * ssts / totalSupply();

        uint256 slippage;
        if (slippages[0] == 1) {
            slippage = slippages[6];
        } else if (slippages[0] == 2) {
            slippage = slippages[3];
        } else if (slippages[0] == 3) {
            slippage = slippages[1];
        } else {
            revert YearnV2RedeemSlippagesFailed();
        }

        _redeemFromYearn(yearnTokensToRedeem, address(this), slippage);
    }

    function _emergencyWithdrawImpl(uint256[] calldata slippages, address recipient) internal override {
        uint256 slippage;
        if (slippages[0] == 1) {
            slippage = slippages[6];
        } else if (slippages[0] == 2) {
            slippage = slippages[3];
        } else if (slippages[0] == 3) {
            slippage = slippages[1];
        } else {
            revert YearnV2RedeemSlippagesFailed();
        }

        _redeemFromYearn(type(uint256).max, recipient, slippage);
    }

    function _compound(address[] calldata tokens, SwapInfo[] calldata compoundSwapInfo, uint256[] calldata slippages)
        internal
        override
        returns (int256 compoundYield)
    {}

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        uint256 currentPricePerShare = yTokenVault.pricePerShare();

        baseYieldPercentage = _calculateYieldPercentage(_lastPricePerShare, currentPricePerShare);

        _lastPricePerShare = currentPricePerShare;
    }

    function _swapAssets(address[] memory tokens, uint256[] memory toSwap, SwapInfo[] calldata swapInfo)
        internal
        override
    {}

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256)
    {
        uint256 assetBalance = yTokenVault.balanceOf(address(this)) * yTokenVault.pricePerShare() / oneShare;
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId());

        return priceFeedManager.assetToUsdCustomPrice(tokens[0], assetBalance, exchangeRates[0]);
    }

    function _redeemFromYearn(uint256 yTokens, address recipient, uint256 slippage) private {
        uint256 redeemedAssets = yTokenVault.withdraw(yTokens, recipient, slippage);

        if (redeemedAssets < slippage) {
            revert YearnV2RedeemSlippagesFailed();
        }
    }
}
