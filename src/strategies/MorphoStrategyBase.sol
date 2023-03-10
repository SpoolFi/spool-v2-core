// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../external/interfaces/strategies/morpho/IMorpho.sol";
import "../interfaces/ISwapper.sol";
import "../strategies/Strategy.sol";

abstract contract MorphoStrategyBase is Strategy {
    using SafeERC20 for IERC20;

    /// @notice Swapper implementaiton.
    ISwapper public immutable swapper;

    /// @notice Morpho implementaiton.
    IMorpho public immutable morpho;

    /// @notice Reward token when participating in the underlying protocol Morpho deposits into.
    IERC20 public immutable poolRewardToken;

    /// @notice Token of the underlying protocol (e.g., cToken, aToken)
    address public poolTokenAddress;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IMorpho morpho_,
        IERC20 poolRewardToken_,
        ISwapper swapper_,
        uint256 assetGroupId_
    ) Strategy(assetGroupRegistry_, accessControl_, assetGroupId_) {
        if (address(swapper_) == address(0)) revert ConfigurationAddressZero();
        if (address(morpho_) == address(0)) revert ConfigurationAddressZero();
        if (address(poolRewardToken_) == address(0)) revert ConfigurationAddressZero();

        swapper = swapper_;
        morpho = morpho_;
        poolRewardToken = poolRewardToken_;
    }

    function __MorphoStrategyBase_init(string memory strategyName_, address poolTokenAddress_) internal onlyInitializing {
        __Strategy_init(strategyName_);

        if (poolTokenAddress_ == address(0)) revert ConfigurationAddressZero();

        poolTokenAddress = poolTokenAddress_;
    }

    function assetRatio() external pure override returns (uint256[] memory) {
        uint256[] memory _assetRatio = new uint256[](1);
        _assetRatio[0] = 1;
        return _assetRatio;
    }

    /**
     * @notice Nothing to swap as it's only one asset.
     */
    function _swapAssets(address[] memory, uint256[] memory, SwapInfo[] calldata) internal override {}

    function _compound(address[] calldata tokens, SwapInfo[] calldata swapInfo, uint256[] calldata)
        internal
        virtual
        override
        returns (int256 compoundedYieldPercentage)
    {
        if (swapInfo.length > 0) {
            address[] memory cTokens = new address[](1);
            cTokens[0] = poolTokenAddress;
            morpho.claimRewards(cTokens, false);

            uint256 compBalance = poolRewardToken.balanceOf(address(this));

            if (compBalance > 0) {
                poolRewardToken.safeTransfer(address(swapper), compBalance);
                address[] memory tokensIn = new address[](1);
                tokensIn[0] = address(poolRewardToken);
                uint256 swappedAmount = swapper.swap(tokensIn, swapInfo, tokens, address(this))[0];

                if (swappedAmount > 0) {
                    uint256 balanceBefore = _getTotalBalance();

                    _depositToMorphoProtocol(IERC20(tokens[0]), swappedAmount);

                    compoundedYieldPercentage =
                        _calculateYieldPercentage(balanceBefore, balanceBefore + swappedAmount);
                }
            }
        }
    }

    function _getYieldPercentage(int256) internal view virtual override returns (int256 baseYieldPercentage) {
        return baseYieldPercentage;
    }

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata)
        internal
        override
    {
        _depositToMorphoProtocol(IERC20(tokens[0]), amounts[0]);
    }

    function _depositToMorphoProtocol(IERC20 token, uint256 amount) private {
        if (amount > 0) {
            _resetAndApprove(token, address(morpho), amount);

            morpho.supply(poolTokenAddress, address(this), amount);
        }
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata) internal override {
        if (ssts == 0) {
            return;
        }

        uint256 withdrawAmount = (_getTotalBalance() * ssts) / totalSupply();

        if (withdrawAmount > 0) {
            morpho.withdraw(poolTokenAddress, withdrawAmount);
        }
    }

    function _emergencyWithdrawImpl(uint256[] calldata, address recipient) internal override {
        morpho.withdraw(poolTokenAddress, type(uint256).max);

        address[] memory tokens = assets();
        IERC20(tokens[0]).safeTransfer(recipient, IERC20(tokens[0]).balanceOf(address(this)));
    }

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256 usdValue)
    {
        uint256 assetBalance = _getTotalBalance();
        if (assetBalance > 0) {
            address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(_assetGroupId);
            usdValue = priceFeedManager.assetToUsdCustomPrice(assetGroup[0], assetBalance, exchangeRates[0]);
        }
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public view override {}

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public view override {}

    function _getTotalBalance() internal view virtual returns (uint256);
}
