// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../external/interfaces/strategies/arbitrum/aave/v3/IAToken.sol";
import "../../external/interfaces/strategies/arbitrum/aave/v3/IPool.sol";
import "../../external/interfaces/strategies/arbitrum/aave/v3/IPoolAddressesProvider.sol";
import "../../external/interfaces/strategies/arbitrum/aave/v3/IRewardsController.sol";
import "../Strategy.sol";

// only uses one asset
// no slippages needed
contract AaveV3Strategy is Strategy {
    using SafeERC20 for IERC20;

    /// @notice Swapper implementation.
    ISwapper public immutable swapper;

    /// @notice Pool addresses provider
    IPoolAddressesProvider public immutable provider;

    /// @notice AAVE incentive controller
    IRewardsController public immutable incentive;

    /// @notice Pool implementation
    IPool public immutable pool;

    /// @notice AAVE token recieved after depositing into a lending pool
    IAToken public aToken;

    uint256 private _lastNormalizedIncome;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        IPoolAddressesProvider provider_,
        IRewardsController incentive_
    ) Strategy(assetGroupRegistry_, accessControl_, NULL_ASSET_GROUP_ID) {
        if (address(provider_) == address(0)) {
            revert ConfigurationAddressZero();
        }

        if (address(incentive_) == address(0)) {
            revert ConfigurationAddressZero();
        }

        pool = provider_.getPool();

        provider = provider_;
        incentive = incentive_;
        swapper = swapper_;
    }

    function initialize(string memory strategyName_, uint256 assetGroupId_) external initializer {
        __Strategy_init(strategyName_, assetGroupId_);

        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId_);

        if (tokens.length != 1) {
            revert InvalidAssetGroup(assetGroupId_);
        }

        IPool.ReserveData memory reserve = pool.getReserveData(tokens[0]);

        _lastNormalizedIncome = pool.getReserveNormalizedIncome(tokens[0]);
        aToken = IAToken(reserve.aTokenAddress);
    }

    function assetRatio() external pure override returns (uint256[] memory) {
        uint256[] memory _assetRatio = new uint256[](1);
        _assetRatio[0] = 1;
        return _assetRatio;
    }

    function getUnderlyingAssetAmounts() external view returns (uint256[] memory amounts) {
        amounts = new uint256[](1);
        amounts[0] = _getATokenBalance();
    }

    function beforeDepositCheck(uint256[] memory, uint256[] calldata) public view override {}

    function beforeRedeemalCheck(uint256, uint256[] calldata) public view override {}

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata)
        internal
        override
    {
        _depositToProtocolInternal(tokens[0], amounts[0]);
    }

    function _redeemFromProtocol(address[] calldata tokens, uint256 ssts, uint256[] calldata) internal override {
        if (ssts == 0) {
            return;
        }

        uint256 aTokenWithdrawAmount = _getATokenBalance() * ssts / totalSupply();
        _redeemFromProtocolInternal(tokens[0], aTokenWithdrawAmount, address(this));
    }

    function _emergencyWithdrawImpl(uint256[] calldata, address recipient) internal override {
        _redeemFromProtocolInternal(assets()[0], _getATokenBalance(), recipient);
    }

    function _compound(address[] calldata tokens, SwapInfo[] calldata swapInfo, uint256[] calldata)
        internal
        override
        returns (int256 compoundYield)
    {
        (address[] memory rewardTokens,) = _getProtocolRewardsInternal();

        if (rewardTokens.length > 0) {
            uint256[] memory swapped = swapper.swap(rewardTokens, swapInfo, tokens, address(this));

            uint256 sharesBefore = _getATokenBalance();
            uint256 shares = _depositToProtocolInternal(tokens[0], swapped[0]);
            if (_isViewExecution()) {
                emit Slippages(true, shares, "");
            }

            compoundYield = int256(YIELD_FULL_PERCENT * (_getATokenBalance() - sharesBefore) / sharesBefore);
        }
    }

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        uint256 currentNormalizedIncome = pool.getReserveNormalizedIncome(assets()[0]);

        baseYieldPercentage = _calculateYieldPercentage(_lastNormalizedIncome, currentNormalizedIncome);
        _lastNormalizedIncome = currentNormalizedIncome;
    }

    function _swapAssets(address[] memory, uint256[] memory, SwapInfo[] calldata) internal override {}

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256)
    {
        return priceFeedManager.assetToUsdCustomPrice(assets()[0], _getATokenBalance(), exchangeRates[0]);
    }

    function _depositToProtocolInternal(address token, uint256 amount) private returns (uint256 shares) {
        _resetAndApprove(IERC20(token), address(pool), amount);

        uint256 aTokenBalanceBefore = _getATokenBalance();
        pool.supply(token, amount, address(this), 0);

        shares = _getATokenBalance() - aTokenBalanceBefore;
    }

    function _redeemFromProtocolInternal(address token, uint256 amount, address recipient) private {
        pool.withdraw(token, amount, recipient);
    }

    function _getProtocolRewardsInternal()
        internal
        virtual
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        (tokens, amounts) = incentive.claimAllRewardsToSelf(assets());
    }

    function _getATokenBalance() private view returns (uint256) {
        return aToken.balanceOf(address(this));
    }
}
