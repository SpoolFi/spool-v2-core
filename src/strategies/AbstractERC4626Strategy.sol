// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/interfaces/IERC4626.sol";

import "../strategies/Strategy.sol";
import "./AbstractERC4626Module.sol";

abstract contract AbstractERC4626Strategy is Strategy, AbstractERC4626Module {
    using SafeERC20 for IERC20;

    error BeforeDepositCheck();
    error BeforeRedeemalCheck();

    /// @custom:storage-location erc7201:spool.storage.ERC4626Strategy
    struct ERC4626StrategyStorage {
        /// @notice redeem at the last DHW.
        uint256 lastConstantRedeem;
    }

    // keccak256(abi.encode(uint256(keccak256("spool.storage.ERC4626Strategy")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC4626StrategyStorageLocation =
        0x93937936ec2af9f038740e119e305f1ce13a5edce385c29ed1b1822d9fac4700;

    /// @notice vault implementation (staking token)
    IERC4626 public immutable vault;

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
        $.lastConstantRedeem = _previewConstantRedeem();
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
        // TODO: not sure it is necessary
        uint256 maxDeposit = vault.maxDeposit(address(this));
        if (maxDeposit < amounts[0]) revert BeforeDepositCheck();
        uint256 shares = vault.previewDeposit(amounts[0]);
        beforeDepositCheck_(amounts[0], slippages[0], shares);

        // TODO: should we put something like that too?
        // if (slippages[0] > 2) {
        //     revert SfrxEthHoldingBeforeDepositCheckFailed();
        // }

        // if (!PackedRange.isWithinRange(slippages[1], amounts[0])) {
        //     revert SfrxEthHoldingBeforeDepositCheckFailed();
        // }
    }

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public override {
        // TODO: not sure it is necessary
        uint256 maxRedeem = vault.maxRedeem(address(this));
        uint256 shares = previewRedeemSsts_(ssts);
        if (maxRedeem < shares) revert BeforeRedeemalCheck();
        // TODO: not sure it is necessary
        beforeRedeemalCheck_(ssts, slippages[0], 0);
    }

    function _underlyingAssetAmount() internal view returns (uint256) {
        return vault.previewRedeem(vaultShareBalance_());
    }

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        // We should account for possible reward gains for shares as well
        // e.g. Share token is deposited into another yield generating vault
        uint256 currentRedeem = _previewConstantRedeem();
        ERC4626StrategyStorage storage $ = _getERC4626StrategyStorage();
        baseYieldPercentage = _calculateYieldPercentage($.lastConstantRedeem, currentRedeem);
        $.lastConstantRedeem = currentRedeem;
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
        uint256 shares = previewRedeemSsts_(ssts);
        _redeemFromProtocolInternal(shares);
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
        uint256 assetAmount = _underlyingAssetAmount();
        if (assetAmount > 0) {
            address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupId());
            usdValue = priceFeedManager.assetToUsdCustomPrice(assetGroup[0], assetAmount, exchangeRates[0]);
        }
    }

    function _redeemFromProtocolInternal(uint256 shares_) internal {
        if (shares_ > 0) {
            // shares is equal shares_ in case there is no rewards
            uint256 shares = redeem_(shares_);
            vault.redeem(shares, address(this), address(this));
        }
    }

    function _getProtocolRewardsInternal() internal override returns (address[] memory, uint256[] memory) {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        (tokens[0], amounts[0]) = rewardInfo_();

        return (tokens, amounts);
    }

    function _previewConstantRedeem() internal view virtual returns (uint256) {
        return vault.previewRedeem(CONSTANT_SHARE_AMOUNT);
    }

    function _swapAssets(address[] memory, uint256[] memory, SwapInfo[] calldata) internal override {}
}
