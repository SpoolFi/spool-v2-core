// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/interfaces/IERC4626.sol";

import "../strategies/Strategy.sol";
import "./AbstractERC4626Module.sol";

abstract contract AbstractERC4626Strategy is Strategy, AbstractERC4626Module {
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:spool.storage.ERC4626Strategy
    struct ERC4626StrategyStorage {
        /// @notice exchangeRate at the last DHW.
        uint256 _lastExchangeRate;
    }

    // keccak256(abi.encode(uint256(keccak256("spool.storage.ERC4626Strategy")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC4626StrategyStorageLocation =
        0x93937936ec2af9f038740e119e305f1ce13a5edce385c29ed1b1822d9fac4700;

    /// @notice vault implementation (staking token)
    IERC4626 public immutable vault;
    /// @notice precision for yield calculation
    uint256 private immutable _mantissa;

    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, IERC4626 vault_)
        Strategy(assetGroupRegistry_, accessControl_, NULL_ASSET_GROUP_ID)
    {
        vault = vault_;
        _mantissa = 10 ** (vault.decimals() * 2);
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
        $._lastExchangeRate = (_mantissa * vault.totalAssets()) / vault.totalSupply();
    }

    function assetRatio() external pure override returns (uint256[] memory) {
        uint256[] memory _assetRatio = new uint256[](1);
        _assetRatio[0] = 1;
        return _assetRatio;
    }

    function getUnderlyingAssetAmounts() external view returns (uint256[] memory amounts) {
        amounts = new uint256[](1);
        amounts[0] = _underlyingAssetAmount();
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public override {
        beforeDepositCheck_(amounts, slippages);
    }

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public override {
        beforeRedeemalCheck_(ssts, slippages);
    }

    function _underlyingAssetAmount() internal view returns (uint256) {
        return vault.previewRedeem(vaultShareBalance_());
    }

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        uint256 exchangeRateCurrent = (_mantissa * vault.totalAssets()) / vault.totalSupply();

        ERC4626StrategyStorage storage $ = _getERC4626StrategyStorage();
        baseYieldPercentage = _calculateYieldPercentage($._lastExchangeRate, exchangeRateCurrent);
        $._lastExchangeRate = exchangeRateCurrent;
    }

    function _compound(address[] calldata tokens, SwapInfo[] calldata compoundSwapInfo, uint256[] calldata slippages)
        internal
        override
        returns (int256 compoundYield)
    {
        return compound_(tokens, compoundSwapInfo, slippages);
    }

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata)
        internal
        override
    {
        _depositToProtocolInternal(IERC20(tokens[0]), amounts[0]);
    }

    function _depositToProtocolInternal(IERC20 token, uint256 amount) internal {
        if (amount > 0) {
            _resetAndApprove(token, address(vault), amount);
            uint256 shares = vault.deposit(amount, address(this));
            deposit_(shares);
        }
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata) internal override {
        uint256 dTokenWithdrawAmount = (vaultShareBalance_() * ssts) / totalSupply();
        _redeemFromProtocolInternal(dTokenWithdrawAmount);
    }

    function _emergencyWithdrawImpl(uint256[] calldata, address recipient) internal override {
        withdraw_();
        vault.redeem(vault.balanceOf(address(this)), recipient, address(this));
    }

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256 usdValue)
    {
        uint256 assetAmount = _underlyingAssetAmount();
        if (assetAmount > 0) {
            address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupId());
            usdValue = priceFeedManager.assetToUsdCustomPrice(assetGroup[0], assetAmount, exchangeRates[0]);
        }
    }

    function _redeemFromProtocolInternal(uint256 shares) internal {
        if (shares > 0) {
            withdraw_(shares);
            vault.redeem(shares, address(this), address(this));
        }
    }

    function _getProtocolRewardsInternal() internal override returns (address[] memory, uint256[] memory) {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        (tokens[0], amounts[0]) = rewardInfo_();

        return (tokens, amounts);
    }

    function _swapAssets(address[] memory, uint256[] memory, SwapInfo[] calldata) internal override {}

    function vaultShareBalance_() internal view virtual override returns (uint256) {
        return vault.balanceOf(address(this));
    }
}
