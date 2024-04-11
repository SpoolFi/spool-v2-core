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
        uint256 lastPreviewRedeem;
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
        $.lastPreviewRedeem = previewConstantRedeem_();
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
        _beforeDepositCheckSlippage(amounts, slippages);
        if (ERC4626Lib.depositFull(vault, amounts[0])) revert BeforeDepositCheck();
        beforeDepositCheck_(vault.previewDeposit(amounts[0]));
    }

    /// @dev can be overwritten in particular strategy to remove slippages
    function _beforeDepositCheckSlippage(uint256[] memory amounts, uint256[] calldata slippages) internal virtual {
        if (_isViewExecution()) {
            uint256[] memory beforeDepositCheckSlippageAmounts = new uint256[](1);
            beforeDepositCheckSlippageAmounts[0] = amounts[0];
            emit BeforeDepositCheckSlippages(beforeDepositCheckSlippageAmounts);
            return;
        }
        if (slippages[0] > 2) {
            revert BeforeDepositCheck();
        }
        if (!PackedRange.isWithinRange(slippages[1], amounts[0])) revert BeforeDepositCheck();
    }

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public override {
        _beforeRedeemalCheckSlippages(ssts, slippages);
        uint256 shares = beforeRedeemalCheck_(previewRedeemSSTs_(ssts));
        if (ERC4626Lib.redeemNotEnough(vault, shares)) revert BeforeRedeemalCheck();
    }

    /// @dev can be overwritten in particular strategy to remove slippages
    function _beforeRedeemalCheckSlippages(uint256 ssts, uint256[] calldata slippages) internal virtual {
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
            revert BeforeRedeemalCheck();
        }
        if (!PackedRange.isWithinRange(slippage, ssts)) revert BeforeRedeemalCheck();
    }

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        // We should account for possible reward gains for shares as well
        // e.g. Share token is deposited into another yield generating vault
        uint256 currentRedeem = previewConstantRedeem_();
        ERC4626StrategyStorage storage $ = _getERC4626StrategyStorage();
        baseYieldPercentage = _calculateYieldPercentage($.lastPreviewRedeem, currentRedeem);
        $.lastPreviewRedeem = currentRedeem;
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
        uint256 slippage = _depositToProtocolSlippages(slippages);
        _depositToProtocolInternal(IERC20(tokens[0]), amounts[0], slippage);
    }

    /// @dev can be overwritten in particular strategy to remove slippages
    function _depositToProtocolSlippages(uint256[] calldata slippages) internal pure returns (uint256 slippage) {
        if (slippages[0] == 0) {
            slippage = slippages[4];
        } else if (slippages[0] == 2) {
            slippage = slippages[2];
        } else {
            revert DepositSlippage();
        }
    }

    function _depositToProtocolInternal(IERC20 token, uint256 amount, uint256 slippage)
        internal
        returns (uint256 shares)
    {
        if (amount > 0) {
            _resetAndApprove(token, address(vault), amount);
            shares = deposit_(vault.deposit(amount, address(this)));
            _depositToProtocolInternalSlippages(shares, slippage);
        }
    }

    /// @dev can be overwritten in particular strategy to remove slippages
    function _depositToProtocolInternalSlippages(uint256 shares, uint256 slippage) internal {
        if (shares < slippage) revert DepositSlippage();
        if (_isViewExecution()) {
            emit Slippages(true, shares, "");
        }
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata slippages) internal override {
        uint256 slippage = _redeemFromProtocolSlippages(slippages);
        uint256 shares = previewRedeemSSTs_(ssts);
        _redeemFromProtocolInternal(shares, slippage);
    }

    /// @dev can be overwritten in particular strategy to remove slippages
    function _redeemFromProtocolSlippages(uint256[] calldata slippages) internal view returns (uint256 slippage) {
        if (slippages[0] == 1) {
            slippage = slippages[4];
        } else if (slippages[0] == 2) {
            slippage = slippages[2];
        } else if (slippages[0] == 3) {
            slippage = slippages[1];
        } else if (_isViewExecution()) {} else {
            revert RedeemalSlippage();
        }
    }

    function _redeemFromProtocolInternal(uint256 shares, uint256 slippage) internal {
        if (shares > 0) {
            uint256 assets = vault.redeem(redeem_(shares), address(this), address(this));
            _redeemFromProtocolInternalSlippages(assets, slippage);
        }
    }

    /// @dev can be overwritten in particular strategy to remove slippages
    function _redeemFromProtocolInternalSlippages(uint256 assets, uint256 slippage) internal {
        if (assets < slippage) revert RedeemalSlippage();
        if (_isViewExecution()) {
            emit Slippages(false, assets, "");
        }
    }

    function _emergencyWithdrawImpl(uint256[] calldata, address recipient) internal override {
        redeem_();
        vault.redeem(ERC4626Lib.getMaxRedeem(vault), recipient, address(this));
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

    function _getProtocolRewardsInternal() internal virtual override returns (address[] memory, uint256[] memory) {
        return (new address[](0), new uint256[](0));
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

    function underlyingAssetAmount_() internal view virtual returns (uint256) {
        return vault.previewRedeem(vault.balanceOf(address(this)));
    }
}
