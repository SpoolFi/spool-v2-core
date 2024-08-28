// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/utils/math/Math.sol";
import "../external/interfaces/strategies/gearbox/v3/IFarmingPool.sol";
import "../external/interfaces/strategies/gearbox/v3/IPoolV3.sol";
import "../interfaces/ISwapper.sol";
import "../libraries/PackedRange.sol";
import "../strategies/Strategy.sol";

error GearboxV3BeforeDepositCheckFailed();

// One asset: WETH || USDC
// One reward: GEAR
// no slippages needed
// Description:
// This is a Gearbox V3 strategy. WETH or USDC is deposited to it's equivalent
// Gearbox V3 pool, where it is lent via Compound/Aave. We receive "diesel"
// tokens (dTokens) following deposit. These tokens accrue value automatically.
//
// The dTokens are then deposited into a Gearbox farming pool to receive extra
// rewards, in the form of GEAR. this process mints sdTokens, 1:1 with dTokens.
// Therefore, we consider dTokens and sdTokens to be equivalent in value.
//
// Liquidity availability on redeem is subject to Aave/Compound rules.
contract GearboxV3Strategy is Strategy {
    using SafeERC20 for IERC20;

    /// @notice Swapper implementation
    ISwapper public immutable swapper;

    /// @notice GEAR token
    /// @dev Reward token when participating in the Gearbox V3 protocol.
    IERC20 public gear;

    /// @notice dToken implementation (staking token)
    IPoolV3 public dToken;

    /// @notice sdToken implementation (LP token)
    IFarmingPool public sdToken;

    /// @notice exchangeRate at the last DHW.
    uint256 internal _lastExchangeRate;

    /// @notice precision for yield calculation
    uint256 internal _mantissa;

    /// @notice maximum balance allowed of the staking token
    uint256 private constant _MAX_BALANCE = 1e32;

    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, ISwapper swapper_)
        Strategy(assetGroupRegistry_, accessControl_, NULL_ASSET_GROUP_ID)
    {
        if (address(swapper_) == address(0)) revert ConfigurationAddressZero();

        swapper = swapper_;
    }

    function initialize(string memory strategyName_, uint256 assetGroupId_, IFarmingPool sdToken_)
        external
        virtual
        initializer
    {
        __Strategy_init(strategyName_, assetGroupId_);

        sdToken = sdToken_;
        dToken = IPoolV3(sdToken_.stakingToken());
        gear = IERC20(sdToken_.rewardsToken());

        address[] memory tokens = assets();

        if (tokens.length != 1 || tokens[0] != dToken.underlyingToken()) {
            revert InvalidAssetGroup(assetGroupId());
        }

        _mantissa = 10 ** (dToken.decimals() * 2);
        _lastExchangeRate = (_mantissa * dToken.expectedLiquidity()) / dToken.totalSupply();
    }

    function assetRatio() external pure override returns (uint256[] memory) {
        uint256[] memory _assetRatio = new uint256[](1);
        _assetRatio[0] = 1;
        return _assetRatio;
    }

    function getUnderlyingAssetAmounts() external view virtual returns (uint256[] memory amounts) {
        amounts = new uint256[](1);
        amounts[0] = _getdTokenValue(sdToken.balanceOf(address(this)));
    }

    /**
     * @notice Nothing to swap as it's only one asset.
     */
    function _swapAssets(address[] memory, uint256[] memory, SwapInfo[] calldata) internal override {}

    function _compound(address[] calldata tokens, SwapInfo[] calldata swapInfo, uint256[] calldata slippages)
        internal
        virtual
        override
        returns (int256 compoundedYieldPercentage)
    {
        compoundedYieldPercentage = _compoundInternal(tokens, swapInfo, slippages);
    }

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        uint256 exchangeRateCurrent = (_mantissa * dToken.expectedLiquidity()) / dToken.totalSupply();

        baseYieldPercentage = _calculateYieldPercentage(_lastExchangeRate, exchangeRateCurrent);
        _lastExchangeRate = exchangeRateCurrent;
    }

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata)
        internal
        virtual
        override
    {
        _depositToProtocolInternal(IERC20(tokens[0]), amounts[0]);
    }

    /**
     * @notice Withdraw lp tokens from the GearboxV3 market
     */
    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata) internal virtual override {
        uint256 dTokenWithdrawAmount = (sdToken.balanceOf(address(this)) * ssts) / totalSupply();

        _redeemFromProtocolInternal(dTokenWithdrawAmount);
    }

    function _emergencyWithdrawImpl(uint256[] calldata, address recipient) internal virtual override {
        uint256 sdTokenBalance = sdToken.balanceOf(address(this));

        _redeemFromProtocolInternal(sdTokenBalance);
        address[] memory tokens = assets();
        IERC20(tokens[0]).safeTransfer(recipient, IERC20(tokens[0]).balanceOf(address(this)));
    }

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        virtual
        override
        returns (uint256 usdValue)
    {
        uint256 sdTokenBalance = sdToken.balanceOf(address(this));
        if (sdTokenBalance > 0) {
            uint256 tokenValue = _getdTokenValue(sdTokenBalance);

            address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupId());
            usdValue = priceFeedManager.assetToUsdCustomPrice(assetGroup[0], tokenValue, exchangeRates[0]);
        }
    }

    /**
     * @dev Get value of the desired dToken amount in the asset token amount
     * @param dTokenAmount dToken amount
     * @return tokenAmount value of `dTokenAmount` in asset tokens
     */
    function _getdTokenValue(uint256 dTokenAmount) internal view returns (uint256) {
        if (dTokenAmount == 0) {
            return 0;
        }

        return dToken.previewRedeem(dTokenAmount);
    }

    function beforeDepositCheck(uint256[] memory, uint256[] calldata) public view override {
        if (sdToken.balanceOf(address(this)) > _MAX_BALANCE) {
            revert GearboxV3BeforeDepositCheckFailed();
        }
    }

    function beforeRedeemalCheck(uint256, uint256[] calldata) public view override {}

    function _compoundInternal(address[] memory tokens, SwapInfo[] calldata swapInfo, uint256[] calldata)
        internal
        returns (int256 compoundedYieldPercentage)
    {
        if (swapInfo.length > 0) {
            uint256 gearBalance = _getGearboxReward();

            if (gearBalance > 0) {
                gear.safeTransfer(address(swapper), gearBalance);
                address[] memory tokensIn = new address[](1);
                tokensIn[0] = address(gear);
                uint256 swappedAmount = swapper.swap(tokensIn, swapInfo, tokens, address(this))[0];

                if (swappedAmount > 0) {
                    uint256 sdTokenBalanceBefore = sdToken.balanceOf(address(this));
                    _depositToProtocolInternal(IERC20(tokens[0]), swappedAmount);

                    compoundedYieldPercentage =
                        _calculateYieldPercentage(sdTokenBalanceBefore, sdToken.balanceOf(address(this)));
                }
            }
        }
    }

    function _depositToProtocolInternal(IERC20 token, uint256 amount) internal {
        if (amount > 0) {
            _resetAndApprove(token, address(dToken), amount);

            uint256 shares = dToken.deposit(amount, address(this));

            _resetAndApprove(dToken, address(sdToken), shares);
            sdToken.deposit(shares);
        }
    }

    function _redeemFromProtocolInternal(uint256 shares) internal {
        if (shares > 0) {
            sdToken.withdraw(shares);
            dToken.redeem(shares, address(this), address(this));
        }
    }

    function _getProtocolRewardsInternal() internal virtual override returns (address[] memory, uint256[] memory) {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = address(gear);
        amounts[0] = _getGearboxReward();

        return (tokens, amounts);
    }

    function _getGearboxReward() internal returns (uint256) {
        sdToken.claim();

        return gear.balanceOf(address(this));
    }
}
