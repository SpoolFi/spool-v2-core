// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../../external/interfaces/strategies/arbitrum/aave/v3/IAToken.sol";
import "../../../external/interfaces/strategies/arbitrum/aave/v3/IPool.sol";
import "../../../external/interfaces/strategies/arbitrum/aave/v3/IPoolAddressesProvider.sol";
import "../../../external/interfaces/strategies/arbitrum/aave/v3/IRewardsController.sol";
import "../../../strategies/Strategy.sol";

abstract contract AaveV3StrategyBase is Strategy {
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

    // @notice underlying pool token (USDC for aUSDC, USDC.e for aUSDC.e etc)
    address public underlying;

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

    function initialize(string memory strategyName_, uint256 assetGroupId_, IAToken aToken_) external initializer {
        __Strategy_init(strategyName_, assetGroupId_);

        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId_);

        if (tokens.length != 1) {
            revert InvalidAssetGroup(assetGroupId_);
        }

        underlying = aToken_.UNDERLYING_ASSET_ADDRESS();
        _lastNormalizedIncome = pool.getReserveNormalizedIncome(underlying);
        aToken = aToken_;
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

    function beforeDepositCheck(uint256[] memory, uint256[] calldata) public virtual override {}

    function beforeRedeemalCheck(uint256, uint256[] calldata) public virtual override {}

    function _depositToProtocol(address[] calldata, uint256[] memory amounts, uint256[] calldata)
        internal
        virtual
        override
    {
        _depositToProtocolInternal(amounts[0]);
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata) internal virtual override {
        if (ssts == 0) {
            return;
        }

        uint256 aTokenWithdrawAmount = _getATokenBalance() * ssts / totalSupply();
        _redeemFromProtocolInternal(aTokenWithdrawAmount, address(this));
    }

    function _emergencyWithdrawImpl(uint256[] calldata, address recipient) internal virtual override {
        _redeemFromProtocolInternal(_getATokenBalance(), recipient);
    }

    function _compound(address[] calldata, SwapInfo[] calldata swapInfo, uint256[] calldata)
        internal
        override
        returns (int256 compoundedYieldPercentage)
    {
        (address[] memory rewardTokens,) = _getProtocolRewardsInternal();

        if (rewardTokens.length > 0) {
            address[] memory tokensOut = new address[](1);
            tokensOut[0] = underlying;
            uint256 swappedAmount = swapper.swap(rewardTokens, swapInfo, tokensOut, address(this))[0];

            if (swappedAmount > 0) {
                uint256 aTokenBalanceBefore = _getATokenBalance();
                _depositToProtocolInternal(swappedAmount);

                compoundedYieldPercentage = _calculateYieldPercentage(aTokenBalanceBefore, _getATokenBalance());
            }
        }
    }

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        uint256 currentNormalizedIncome = pool.getReserveNormalizedIncome(underlying);

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

    function _getProtocolRewardsInternal()
        internal
        virtual
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        address[] memory aTokens = new address[](1);
        aTokens[0] = address(aToken);
        (tokens, amounts) = incentive.claimAllRewardsToSelf(aTokens);

        for (uint256 i; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeTransfer(address(swapper), amounts[i]);
        }
    }

    function _depositToProtocolInternal(uint256 amount) private {
        if (amount > 0) {
            _resetAndApprove(IERC20(underlying), address(pool), amount);

            pool.supply(underlying, amount, address(this), 0);
        }
    }

    function _redeemFromProtocolInternal(uint256 amount, address recipient) private {
        pool.withdraw(underlying, amount, recipient);
    }

    function _getATokenBalance() private view returns (uint256) {
        return aToken.balanceOf(address(this));
    }
}
