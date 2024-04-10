// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/interfaces/IERC4626.sol";

import "../strategies/Strategy.sol";
import "../libraries/PackedRange.sol";
import "../libraries/ERC4626Lib.sol";

// one asset
// unknown amount of rewards
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
contract ERC4626StrategyBase is Strategy {
    using SafeERC20 for IERC20;

    error BeforeDepositCheck();
    error BeforeRedeemalCheck();
    error DepositSlippage();
    error RedeemalSlippage();
    error CompoundSlippage();

    /// @custom:storage-location erc7201:spool.storage.ERC4626Strategy
    struct ERC4626StrategyStorage {
        /// @notice redeem at the last DHW.
        uint256 lastConstantRedeem;
    }

    // keccak256(abi.encode(uint256(keccak256("spool.storage.ERC4626Strategy")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC4626StrategyStorageLocation =
        0x93937936ec2af9f038740e119e305f1ce13a5edce385c29ed1b1822d9fac4700;

    /// @notice vault implementation
    IERC4626 public immutable vault;

    /// @notice constant amount of shares to calculate vault performance
    uint256 immutable CONSTANT_SHARE_AMOUNT;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IERC4626 vault_,
        uint256 constantShareAmount_
    ) Strategy(assetGroupRegistry_, accessControl_, NULL_ASSET_GROUP_ID) {
        vault = vault_;
        CONSTANT_SHARE_AMOUNT = constantShareAmount_;
    }

    function _getERC4626StrategyStorage() private pure returns (ERC4626StrategyStorage storage $) {
        assembly {
            $.slot := ERC4626StrategyStorageLocation
        }
    }

    function __ERC4626Strategy_init(string memory strategyName_, uint256 assetGroupId_) internal onlyInitializing {
        __ERC4626Strategy_init_unchained(strategyName_, assetGroupId_);
    }

    function __ERC4626Strategy_init_unchained(string memory strategyName_, uint256 assetGroupId_)
        internal
        onlyInitializing
    {
        __Strategy_init(strategyName_, assetGroupId_);
        address[] memory tokens = assets();
        if (tokens.length != 1 || tokens[0] != vault.asset()) {
            revert InvalidAssetGroup(assetGroupId());
        }

        ERC4626StrategyStorage storage $ = _getERC4626StrategyStorage();
        $.lastConstantRedeem = previewConstantRedeem_();
    }

    function assetRatio() external pure override returns (uint256[] memory) {
        uint256[] memory _assetRatio = new uint256[](1);
        _assetRatio[0] = 1;
        return _assetRatio;
    }

    function getUnderlyingAssetAmounts() external view returns (uint256[] memory amounts) {
        amounts = new uint256[](1);
        amounts[0] = underlyingAssetAmount_();
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public override {
        if (slippages[0] > 2) {
            revert BeforeDepositCheck();
        }
        if (!PackedRange.isWithinRange(slippages[1], amounts[0])) revert BeforeDepositCheck();

        if (ERC4626Lib.depositFull(vault, amounts[0])) revert BeforeDepositCheck();
        beforeDepositCheck_(vault.previewDeposit(amounts[0]));
    }

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public override {
        uint256 slippage;
        if (slippages[0] < 2) {
            slippage = slippages[2];
        } else if (slippages[0] == 2) {
            slippage = slippages[1];
        } else {
            revert BeforeRedeemalCheck();
        }

        if (!PackedRange.isWithinRange(slippage, ssts)) revert BeforeRedeemalCheck();

        uint256 shares = beforeRedeemalCheck_(previewRedeemSSTs_(ssts));
        if (ERC4626Lib.redeemNotEnough(vault, shares)) revert BeforeRedeemalCheck();
    }

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        // We should account for possible reward gains for shares as well
        // e.g. Share token is deposited into another yield generating vault
        uint256 currentRedeem = previewConstantRedeem_();
        ERC4626StrategyStorage storage $ = _getERC4626StrategyStorage();
        baseYieldPercentage = _calculateYieldPercentage($.lastConstantRedeem, currentRedeem);
        $.lastConstantRedeem = currentRedeem;
    }

    function _compound(address[] calldata tokens, SwapInfo[] calldata compoundSwapInfo, uint256[] calldata slippages)
        internal
        virtual
        override
        returns (int256 compoundYield)
    {}

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
            revert DepositSlippage();
        }
        _depositToProtocolInternal(IERC20(tokens[0]), amounts[0], slippage);
    }

    function _depositToProtocolInternal(IERC20 token, uint256 amount, uint256 slippage) internal {
        if (amount > 0) {
            _resetAndApprove(token, address(vault), amount);
            uint256 shares = deposit_(vault.deposit(amount, address(this)));
            if (shares < slippage) revert DepositSlippage();
        }
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata slippages) internal override {
        uint256 slippage;
        if (slippages[0] == 1) {
            slippage = slippages[4];
        } else if (slippages[0] == 2) {
            slippage = slippages[2];
        } else if (slippages[0] == 3) {
            slippage = slippages[1];
        } else {
            revert RedeemalSlippage();
        }
        uint256 shares = previewRedeemSSTs_(ssts);
        _redeemFromProtocolInternal(shares, slippage);
    }

    function _redeemFromProtocolInternal(uint256 shares, uint256 slippage) internal {
        if (shares > 0) {
            uint256 assets = vault.redeem(redeem_(shares), address(this), address(this));
            if (assets < slippage) revert RedeemalSlippage();
        }
    }

    function _emergencyWithdrawImpl(uint256[] calldata, address recipient) internal override {
        redeem_();
        // not all funds can be available for withdrawal
        uint256 maxRedeem = vault.maxRedeem(address(this));
        uint256 totalShares = vault.balanceOf(address(this));
        // maxRedeem can be slightly lower so check for minimal difference - 3 decimals
        if (totalShares - maxRedeem < 10 ** vault.decimals() / 1000) {
            maxRedeem = totalShares;
        }
        vault.redeem(maxRedeem, recipient, address(this));
    }

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256 usdValue)
    {
        uint256 assetAmount = underlyingAssetAmount_();
        if (assetAmount > 0) {
            address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupId());
            usdValue = priceFeedManager.assetToUsdCustomPrice(assetGroup[0], assetAmount, exchangeRates[0]);
        }
    }

    function _getProtocolRewardsInternal() internal override returns (address[] memory, uint256[] memory) {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        (tokens[0], amounts[0]) = rewardInfo_();

        return (tokens, amounts);
    }

    function _swapAssets(address[] memory, uint256[] memory, SwapInfo[] calldata) internal virtual override {}

    /// @notice Internal functions specific to Modules for ERC4626 base strategy

    function beforeDepositCheck_(uint256 assets) internal virtual {}

    function beforeRedeemalCheck_(uint256 shares) internal virtual returns (uint256 assets) {
        return shares;
    }

    function deposit_(uint256 assets) internal virtual returns (uint256 shares) {
        return assets;
    }

    function redeem_() internal virtual {}

    function redeem_(uint256 shares) internal virtual returns (uint256 assets) {
        return shares;
    }

    function previewConstantRedeem_() internal view virtual returns (uint256) {
        return vault.previewRedeem(CONSTANT_SHARE_AMOUNT);
    }

    function previewRedeemSSTs_(uint256 ssts) internal view virtual returns (uint256) {
        return (vault.balanceOf(address(this)) * ssts) / totalSupply();
    }

    function rewardInfo_() internal virtual returns (address, uint256) {}

    function underlyingAssetAmount_() internal view virtual returns (uint256) {
        return vault.previewRedeem(vault.balanceOf(address(this)));
    }
}
