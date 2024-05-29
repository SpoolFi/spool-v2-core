// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./Strategy.sol";
import "../external/interfaces/strategies/ethena/IsUSDe.sol";
import "../libraries/BytesUint256Lib.sol";

/// @dev Strategy for investing in Ethena Protocol
// USDe is staked into sUSDe which accrues yield automatically

// Following contract supports arbitrary stablecoin asset group (such as DAI, USDT, USDC, USDe)

// It is possible to get USDe via EthenaMinting.mint(), but it is callable only by 'Minter role',
// Therefore we will swap asset to USDe (if asset group is other than USDe) and then stake it into sUSDe

// Although, USDe can be staked into sUSDe directly, instant redeem is not always possible.
// Ethena has a configuration parameter - "cooldownDuration". If it is non-zero then sUSDe will be burned immediately,
// but USDe will be claimed in separate tx after passing "cooldownDuration" (at the time of writing it is a one week).
// Even if we would wait for that, consequent redeem requests will reset our waiting period back,
// so that users who requested redeem first will wait more than one week.
// In that case we will swap sUSDe.
// Parameters for this swap will be passed through slippages array, please check description below.
// If "cooldownDuration" is zero, than normal redeem is possible.
// Therefore current strategy supports both scenarios depending on "cooldownDuration" value.

// $ENA reward will be auto-compounded - swapped and staked into sUSDe.

// Funds flow:
// "=>" is swap, "->" is staking/unstaking
//      - deposit:
//          asset group is USDe:    USDe -> sUSDe
//          otherwise:              Asset => USDe -> sUSDe
//      - redeem:
//          asset group is USDe:
//              "cooldown" is on:   sUSDe => USDe
//              "cooldown" if off:  sUSDe -> USDe
//          otherwise:
//              "cooldown" is on:   sUSDe => Asset
//              "cooldown" if off:  sUSDe -> USDe => Asset

// Swap slippages
//      slippages[1] - if equals 1 used as estimation flag, else swapTarget
//      slippages[2] - bytesLength
//      slippages[3..n] - swap payload to decode
contract EthenaStrategy is Strategy {
    using SafeERC20 for IsUSDe;
    using SafeERC20 for IERC20Metadata;

    /// @dev used for parameter gatherer to prepare swap payload
    event SwapEstimation(address tokenIn, address tokenOut, uint256 tokenInAmount);

    /// @dev thrown if slippages array is not valid for swap
    error SwapSlippage();

    /// @dev USDe token address
    IERC20Metadata public immutable USDe;
    /// @dev sUSDe token address
    IsUSDe public immutable sUSDe;

    ISwapper public immutable swapper;
    /// @dev reward on Ethena protocol
    IERC20Metadata public immutable ENAToken;
    /// @dev used for calculating yield percentage
    uint256 public immutable constantShareAmount;

    /// @dev last preview redeem of sUSDe to USDe using constantShareAmount
    uint256 lastPreviewRedeem;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IERC20Metadata USDe_,
        IsUSDe sUSDe_,
        IERC20Metadata ENAToken_,
        ISwapper swapper_
    ) Strategy(assetGroupRegistry_, accessControl_, NULL_ASSET_GROUP_ID) {
        _disableInitializers();
        if (
            address(ENAToken_) == address(0) || address(swapper_) == address(0) || address(sUSDe_) == address(0)
                || address(USDe_) == address(0)
        ) {
            revert ConfigurationAddressZero();
        }
        USDe = USDe_;
        sUSDe = sUSDe_;
        ENAToken = ENAToken_;
        swapper = swapper_;
        constantShareAmount = 10 ** (sUSDe.decimals() * 2);
    }

    function initialize(string memory strategyName_, uint256 assetGroupId_) external virtual initializer {
        __Strategy_init(strategyName_, assetGroupId_);
        USDe.safeApprove(address(sUSDe), type(uint256).max);
        USDe.safeApprove(address(swapper), type(uint256).max);
        sUSDe.safeApprove(address(swapper), type(uint256).max);
        lastPreviewRedeem = _previewConstantRedeem();
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public override {}
    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public override {}

    /// @dev returns USDe amount for all asset groups
    /// since it is stable and this function is used for informational purposes
    /// it is ok to made an assumption of 1:1 ratio
    function getUnderlyingAssetAmounts() external view returns (uint256[] memory amounts) {
        amounts = new uint256[](1);
        amounts[0] = _underlyingAssetAmount();
    }

    function assetRatio() external pure override returns (uint256[] memory) {
        uint256[] memory _assetRatio = new uint256[](1);
        _assetRatio[0] = 1;
        return _assetRatio;
    }

    function _swapAssets(address[] memory, uint256[] memory, SwapInfo[] calldata) internal virtual override {}

    /// @dev used to decide whether USDe should be swapped to asset group
    function _shouldSwap() internal view returns (bool) {
        return address(USDe) != assets()[0];
    }

    function _depositToProtocol(address[] calldata, uint256[] memory amounts, uint256[] calldata slippages)
        internal
        virtual
        override
    {
        uint256 amount = amounts[0];
        // first swap asset to USDe in case it is not a USDe asset group
        if (_shouldSwap()) {
            amount = _swap(assets()[0], address(USDe), amount, slippages);
        }
        // conditional is needed since on estimation _swap returns 0 and staking will fail in this case
        if (amount > 0) {
            sUSDe.deposit(amount, address(this));
        }
    }

    function _compound(address[] calldata, SwapInfo[] calldata swapInfo, uint256[] calldata)
        internal
        virtual
        override
        returns (int256 compoundedYieldPercentage)
    {
        if (swapInfo.length > 0) {
            uint256 enaBalance = ENAToken.balanceOf(address(this));

            if (enaBalance > 0) {
                address[] memory tokensIn = new address[](1);
                tokensIn[0] = address(ENAToken);
                address[] memory tokensOut = new address[](1);
                tokensOut[0] = address(USDe);
                ENAToken.safeTransfer(address(swapper), enaBalance);
                uint256 swappedAmount = swapper.swap(tokensIn, swapInfo, tokensOut, address(this))[0];

                if (swappedAmount > 0) {
                    uint256 sUSDeBalanceBefore = sUSDe.balanceOf(address(this));
                    sUSDe.deposit(swappedAmount, address(this));
                    compoundedYieldPercentage =
                        _calculateYieldPercentage(sUSDeBalanceBefore, sUSDe.balanceOf(address(this)));
                }
            }
        }
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata slippages) internal override {
        uint256 supply = totalSupply();
        uint256 shares = supply == 0 ? supply : (sUSDe.balanceOf(address(this)) * ssts) / supply;
        _redeemFromProtocolInternal(shares, slippages);
    }

    function _redeemFromProtocolInternal(uint256 shares, uint256[] calldata slippages) internal virtual {
        uint256 cooldownDuration = sUSDe.cooldownDuration();
        // if cooldown duration is zero it means sUSDe can be directly redeemed to USDe
        if (cooldownDuration == 0) {
            _redeemDirectly(shares, slippages);
        } else {
            // otherwise we need to swap to underlying asset
            _swap(address(sUSDe), assets()[0], shares, slippages);
        }
    }

    function _emergencyWithdrawImpl(uint256[] calldata slippages, address recipient) internal virtual override {
        _redeemFromProtocolInternal(sUSDe.balanceOf(address(this)), slippages);
        IERC20Metadata underlyingToken = IERC20Metadata(assets()[0]);
        underlyingToken.safeTransfer(recipient, underlyingToken.balanceOf(address(this)));
    }

    function _redeemDirectly(uint256 shares, uint256[] calldata slippages) internal virtual {
        // redeem sUSDe directly to USDe
        uint256 amount = sUSDe.redeem(shares, address(this), address(this));
        // if USDe is not an asset group we need to swap it
        if (_shouldSwap()) {
            _swap(address(USDe), assets()[0], amount, slippages);
        }
    }

    function _getProtocolRewardsInternal() internal virtual override returns (address[] memory, uint256[] memory) {
        address[] memory tokens = new address[](1);
        tokens[0] = address(ENAToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ENAToken.balanceOf(address(this));
        return (tokens, amounts);
    }

    /// @dev swaps "tokenInAmount" of "tokenIn" to "tokenOut" using "slippages" to build swap payload for Swapper
    function _swap(address tokenIn, address tokenOut, uint256 tokenInAmount, uint256[] calldata slippages)
        internal
        virtual
        returns (uint256)
    {
        // used for parameter gatherer in order to prepare swap calldata
        if (_isViewExecution() && slippages[0] == 1) {
            emit SwapEstimation(tokenIn, tokenOut, tokenInAmount);
            return 0;
        }
        if (slippages.length < 3) revert SwapSlippage();
        address swapTarget = address(uint160(slippages[0]));
        uint256 bytesLength = slippages[1];
        uint256[] memory toDecode = new uint256[](slippages.length - 2);
        for (uint256 i; i < toDecode.length; i++) {
            toDecode[i] = slippages[2 + i];
        }
        bytes memory payload = BytesUint256Lib.decode(toDecode, bytesLength);
        address[] memory tokensIn = new address[](1);
        tokensIn[0] = tokenIn;
        SwapInfo[] memory swapInfos = new SwapInfo[](1);
        swapInfos[0] = SwapInfo(swapTarget, tokensIn[0], payload);
        address[] memory tokensOut = new address[](1);
        tokensOut[0] = tokenOut;
        IERC20Metadata(tokenIn).safeTransfer(address(swapper), tokenInAmount);
        return swapper.swap(tokensIn, swapInfos, tokensOut, address(this))[0];
    }

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        uint256 currentRedeem = _previewConstantRedeem();
        baseYieldPercentage = _calculateYieldPercentage(lastPreviewRedeem, currentRedeem);
        lastPreviewRedeem = currentRedeem;
    }

    function _previewConstantRedeem() internal view virtual returns (uint256) {
        return sUSDe.previewRedeem(constantShareAmount);
    }

    function _underlyingAssetAmount() internal view virtual returns (uint256) {
        return sUSDe.previewRedeem(sUSDe.balanceOf(address(this)));
    }

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256 usdValue)
    {
        uint256 assetAmount = _underlyingAssetAmount();
        if (assetAmount > 0) {
            usdValue = priceFeedManager.assetToUsdCustomPrice(address(USDe), assetAmount, exchangeRates[0]);
        }
    }
}
