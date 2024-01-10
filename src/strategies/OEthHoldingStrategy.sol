// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../external/interfaces/strategies/oEth/IVaultCore.sol";
import "../external/interfaces/strategies/oEth/IOEthToken.sol";
import "../external/interfaces/strategies/curve/ICurvePool.sol";
import "../libraries/PackedRange.sol";
import "./Strategy.sol";
import "./helpers/WethHelper.sol";

error OEthHoldingBeforeDepositCheckFailed();
error OEthHoldingBeforeRedeemalCheckFailed();
error OEthHoldingDepositSlippagesFailed();
error OEthHoldingRedeemSlippagesFailed();

// one asset
// no rewards
// slippages
// - mode selection: slippages[0]
// - DHW with deposit: slippages[0] == 0
//   - beforeDepositCheck: slippages[1]
//   - beforeRedeemalCheck: slippages[2]
//   - _depositToProtocol:
//          selection: slippages[3]
//          slippage: slippages[4]
// - DHW with withdrawal: slippages[0] == 1
//   - beforeDepositCheck: slippages[1]
//   - beforeRedeemalCheck: slippages[2]
//   - _redeemFromProtocol: slippages[3]
// - reallocate: slippages[0] == 2
//   - beforeDepositCheck: depositSlippages[1]
//   - _depositToProtocol:
//          selection: slippages[2]
//          slippage: slippages[3]
//   - beforeRedeemalCheck: withdrawalSlippages[1]
//   - _redeemFromProtocol: withdrawalSlippages[2]
// - redeemFast or emergencyWithdraw: slippages[0] == 3
//   - _redeemFromProtocol or _emergencyWithdrawImpl: slippages[1]
// - _depositToProtocol:
//   - if selection == 0 -> mint
//     else -> buy on curve
// Description:
// This is a strategy where ETH is staked with Origin to be used for investing
// in various liquid staking derivative strategies.
// Origin has one token, oETH, and the oETH vault. The oETH token is minted
// when submitting ETH to Origin on the vault.
// Redeeming via the vault is permitted without restrictions; however it returns
// a basket of the underlying LSDs + WETH (not just WETH), plus it incurs a
// 0.5% fee. So we instead just swap the oETH on Curve to get back WETH
// on redemption.
// Holding the OETH token is enough to be eligible for staking yield. The oETH
// token is rebalanced to always be worth 1 ETH (ie. share price of 1 token
// does not increase as other LSD strategies do); instead, User's balances
// increase directly when a rebase is performed on the Origin protocol.
// The strategy supports two ways to obtain oETH:
// - mint oETH on the Origin vault
// - buy oETH on Curve oETH/ETH pool
// The do-hard-worker can decide which way to use based on profitability by
// setting appropriate slippages (see slippages above).
contract OEthHoldingStrategy is Strategy, WethHelper {
    using SafeERC20 for IERC20;

    int128 public constant CURVE_ETH_POOL_ETH_INDEX = 0;
    int128 public constant CURVE_ETH_POOL_OETH_INDEX = 1;

    IOEthToken public immutable oEthToken;
    IVaultCore public immutable oEthVault;
    ICurveEthPool public immutable curve;

    uint256 private _rebasingCreditsPerTokenLast;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        uint256 assetGroupId_,
        IOEthToken oEthToken_,
        IVaultCore oEthVault_,
        ICurveEthPool curve_,
        address weth_
    ) Strategy(assetGroupRegistry_, accessControl_, assetGroupId_) WethHelper(weth_) {
        if (address(oEthToken_) == address(0)) {
            revert ConfigurationAddressZero();
        }
        if (address(oEthVault_) == address(0)) {
            revert ConfigurationAddressZero();
        }
        if (address(curve_) == address(0)) {
            revert ConfigurationAddressZero();
        }

        oEthToken = oEthToken_;
        oEthVault = oEthVault_;
        curve = curve_;
    }

    function initialize(string calldata strategyName_) external initializer {
        __Strategy_init(strategyName_, NULL_ASSET_GROUP_ID);

        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId());

        if (tokens.length != 1 || tokens[0] != weth) {
            revert InvalidAssetGroup(assetGroupId());
        }

        _rebasingCreditsPerTokenLast = oEthToken.rebasingCreditsPerToken();
    }

    function assetRatio() external pure override returns (uint256[] memory) {
        uint256[] memory _assetRatio = new uint256[](1);
        _assetRatio[0] = 1;
        return _assetRatio;
    }

    function getUnderlyingAssetAmounts() external view returns (uint256[] memory amounts) {
        amounts = new uint256[](1);
        amounts[0] = oEthToken.balanceOf(address(this));
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public override {
        if (_isViewExecution()) {
            uint256[] memory beforeDepositCheckSlippageAmounts = new uint256[](1);
            beforeDepositCheckSlippageAmounts[0] = amounts[0];

            emit BeforeDepositCheckSlippages(beforeDepositCheckSlippageAmounts);
            return;
        }

        if (slippages[0] > 2) {
            revert OEthHoldingBeforeDepositCheckFailed();
        }

        if (!PackedRange.isWithinRange(slippages[1], amounts[0])) {
            revert OEthHoldingBeforeDepositCheckFailed();
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
            revert OEthHoldingBeforeRedeemalCheckFailed();
        }

        if (!PackedRange.isWithinRange(slippage, ssts)) {
            revert OEthHoldingBeforeRedeemalCheckFailed();
        }
    }

    function _depositToProtocol(address[] calldata, uint256[] memory amounts, uint256[] calldata slippages)
        internal
        override
    {
        uint256 selection;
        uint256 slippage;
        if (slippages[0] == 0) {
            selection = slippages[3];
            slippage = slippages[4];
        } else if (slippages[0] == 2) {
            selection = slippages[2];
            slippage = slippages[3];
        } else {
            revert OEthHoldingDepositSlippagesFailed();
        }

        if (selection == 0) {
            _mint(amounts[0], slippage);
        } else {
            _buyOnCurve(amounts[0], slippage);
        }
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata slippages) internal override {
        uint256 slippage;
        if (slippages[0] == 1) {
            slippage = slippages[3];
        } else if (slippages[0] == 2) {
            slippage = slippages[2];
        } else if (slippages[0] == 3) {
            slippage = slippages[1];
        } else if (_isViewExecution()) {} else {
            revert OEthHoldingRedeemSlippagesFailed();
        }

        uint256 sharesToRedeem = oEthToken.balanceOf(address(this)) * ssts / totalSupply();
        _sellOnCurve(sharesToRedeem, slippage);
    }

    function _emergencyWithdrawImpl(uint256[] calldata slippages, address recipient) internal override {
        if (slippages[0] != 3) {
            revert OEthHoldingRedeemSlippagesFailed();
        }

        uint256 bought = _sellOnCurve(oEthToken.balanceOf(address(this)), slippages[1]);

        IERC20(weth).safeTransfer(recipient, bought);
    }

    function _compound(address[] calldata, SwapInfo[] calldata, uint256[] calldata)
        internal
        pure
        override
        returns (int256)
    {}

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        uint256 rebasingCreditsPerTokenCurrent = oEthToken.rebasingCreditsPerToken();

        baseYieldPercentage = _calculateYieldPercentage(rebasingCreditsPerTokenCurrent, _rebasingCreditsPerTokenLast);

        _rebasingCreditsPerTokenLast = rebasingCreditsPerTokenCurrent;
    }

    function _swapAssets(address[] memory, uint256[] memory, SwapInfo[] calldata) internal pure override {}

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256)
    {
        return priceFeedManager.assetToUsdCustomPrice(weth, oEthToken.balanceOf(address(this)), exchangeRates[0]);
    }

    function _mint(uint256 amount, uint256 minOut) private {
        _resetAndApprove(IERC20(address(weth)), address(oEthVault), amount);

        oEthVault.mint(address(weth), amount, minOut);
    }

    function _buyOnCurve(uint256 amount, uint256 slippage) private {
        unwrapEth(amount);

        uint256 bought =
            curve.exchange{value: amount}(CURVE_ETH_POOL_ETH_INDEX, CURVE_ETH_POOL_OETH_INDEX, amount, slippage);

        if (_isViewExecution()) {
            emit Slippages(true, bought, "");
        }
    }

    function _sellOnCurve(uint256 amount, uint256 slippage) private returns (uint256 bought) {
        _resetAndApprove(IERC20(address(oEthToken)), address(curve), amount);
        bought = curve.exchange(CURVE_ETH_POOL_OETH_INDEX, CURVE_ETH_POOL_ETH_INDEX, amount, slippage);

        wrapEth(bought);

        if (_isViewExecution()) {
            emit Slippages(false, bought, "");
        }
    }

    function _getProtocolRewardsInternal()
        internal
        virtual
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {}
}
