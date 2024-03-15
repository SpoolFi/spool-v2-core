// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/utils/math/Math.sol";
import "../../external/interfaces/strategies/arbitrum/compound/v3/IComet.sol";
import "../../external/interfaces/strategies/arbitrum/compound/v3/ICToken.sol";
import "../../external/interfaces/strategies/arbitrum/compound/v3/IRewards.sol";
import "../../interfaces/ISwapper.sol";
import "../../strategies/Strategy.sol";

contract CompoundV3Strategy is Strategy {
    using SafeERC20 for IERC20;

    /// @notice Swapper implementation
    ISwapper public immutable swapper;

    /// @notice COMP token
    /// @dev Reward token when participating in the Compound protocol.
    IERC20 public immutable comp;

    IRewards public immutable rewards;

    /// @notice Compound market
    IComet public cToken;

    /// @notice supply rate at the last DHW.
    uint256 private _lastExchangeRate;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        IERC20 comp_,
        IRewards rewards_
    ) Strategy(assetGroupRegistry_, accessControl_, NULL_ASSET_GROUP_ID) {
        if (address(swapper_) == address(0)) revert ConfigurationAddressZero();
        if (address(comp_) == address(0)) revert ConfigurationAddressZero();
        if (address(rewards_) == address(0)) revert ConfigurationAddressZero();

        swapper = swapper_;
        comp = comp_;
        rewards = rewards_;
    }

    function initialize(string memory strategyName_, uint256 assetGroupId_, IComet cToken_) external initializer {
        __Strategy_init(strategyName_, assetGroupId_);

        if (address(cToken_) == address(0)) {
            revert ConfigurationAddressZero();
        }

        address[] memory tokens = assets();

        if (tokens.length != 1 || tokens[0] != cToken_.baseToken()) {
            revert InvalidAssetGroup(assetGroupId());
        }

        cToken = cToken_;
        _lastExchangeRate = _exchangeRateCurrent();
    }

    function assetRatio() external pure override returns (uint256[] memory) {
        uint256[] memory _assetRatio = new uint256[](1);
        _assetRatio[0] = 1;
        return _assetRatio;
    }

    function getUnderlyingAssetAmounts() external view returns (uint256[] memory amounts) {
        amounts = new uint256[](1);
        amounts[0] = cToken.balanceOf(address(this));
    }

    function beforeDepositCheck(uint256[] memory, uint256[] calldata) public view override {}

    function beforeRedeemalCheck(uint256, uint256[] calldata) public view override {}

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata)
        internal
        override
    {
        _depositToProtocolInternal(tokens[0], amounts[0]);
    }

    /**
     * @notice Withdraw lp tokens from the Compound market
     */
    function _redeemFromProtocol(address[] calldata tokens, uint256 ssts, uint256[] calldata) internal override {
        if (ssts == 0) {
            return;
        }

        uint256 cTokenWithdrawAmount = (cToken.balanceOf(address(this)) * ssts) / totalSupply();

        _redeemFromProtocolInternal(tokens[0], cTokenWithdrawAmount);
    }

    /**
     * @notice Nothing to swap as it's only one asset.
     */
    function _swapAssets(address[] memory, uint256[] memory, SwapInfo[] calldata) internal override {}

    function _compound(address[] calldata tokens, SwapInfo[] calldata swapInfo, uint256[] calldata)
        internal
        override
        returns (int256 compoundedYieldPercentage)
    {
        if (swapInfo.length > 0) {
            uint256 compBalance = _getCompoundReward();

            if (compBalance > 0) {
                comp.safeTransfer(address(swapper), compBalance);
                address[] memory tokensIn = new address[](1);
                tokensIn[0] = address(comp);
                uint256 swappedAmount = swapper.swap(tokensIn, swapInfo, tokens, address(this))[0];

                if (swappedAmount > 0) {
                    uint256 cTokenBalanceBefore = cToken.balanceOf(address(this));
                    _depositToProtocolInternal(tokens[0], swappedAmount);

                    compoundedYieldPercentage =
                        _calculateYieldPercentage(cTokenBalanceBefore, cToken.balanceOf(address(this)));
                }
            }
        }
    }

    function _emergencyWithdrawImpl(uint256[] calldata, address recipient) internal override {
        _redeemFromProtocolInternal(assets()[0], cToken.balanceOf(address(this)));

        IERC20 token = IERC20(assets()[0]);

        token.safeTransfer(recipient, token.balanceOf(address(this)));
    }

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        uint256 exchangeRateCurrent = _exchangeRateCurrent();

        baseYieldPercentage = _calculateYieldPercentage(_lastExchangeRate, exchangeRateCurrent);
        _lastExchangeRate = exchangeRateCurrent;
    }

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256 usdValue)
    {
        uint256 tokenValue = cToken.balanceOf(address(this));
        if (tokenValue > 0) {
            address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupId());
            usdValue = priceFeedManager.assetToUsdCustomPrice(assetGroup[0], tokenValue, exchangeRates[0]);
        }
    }

    function _getProtocolRewardsInternal() internal virtual override returns (address[] memory, uint256[] memory) {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = address(comp);
        amounts[0] = _getCompoundReward();

        return (tokens, amounts);
    }

    function _depositToProtocolInternal(address token, uint256 amount) private {
        if (amount > 0) {
            _resetAndApprove(IERC20(token), address(cToken), amount);

            cToken.supply(token, amount);
        }
    }

    function _redeemFromProtocolInternal(address token, uint256 amount) private {
        if (amount > 0) {
            cToken.withdraw(token, amount);
        }
    }

    function _getCompoundReward() private returns (uint256) {
        rewards.claim({comet: address(cToken), src: address(this), shouldAccrue: true});

        return comp.balanceOf(address(this));
    }

    function _exchangeRateCurrent() private view returns (uint256) {
        return (cToken.totalSupply() * 1 ether) / cToken.getCollateralReserves(assets()[0]);
    }
}
