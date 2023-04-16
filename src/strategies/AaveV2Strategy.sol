// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "forge-std/console.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../external/interfaces/strategies/aave/v2/ILendingPool.sol";
import "../external/interfaces/strategies/aave/v2/ILendingPoolAddessesProvider.sol";
import "./Strategy.sol";

// only uses one asset
// no rewards
// no slippages needed
contract AaveV2Strategy is Strategy {
    using SafeERC20 for IERC20;

    ILendingPoolAddressesProvider public immutable provider;

    IERC20 public aToken;

    uint256 private _lastNormalizedIncome;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ILendingPoolAddressesProvider provider_
    ) Strategy(assetGroupRegistry_, accessControl_, NULL_ASSET_GROUP_ID) {
        if (address(provider_) == address(0)) {
            revert ConfigurationAddressZero();
        }

        provider = provider_;
    }

    function initialize(string memory strategyName_, uint256 assetGroupId_) external initializer {
        __Strategy_init(strategyName_, assetGroupId_);

        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId_);

        if (tokens.length != 1) {
            revert InvalidAssetGroup(assetGroupId_);
        }

        aToken = IERC20(provider.getLendingPool().getReserveData(tokens[0]).aTokenAddress);
        _lastNormalizedIncome = provider.getLendingPool().getReserveNormalizedIncome(tokens[0]);
    }

    function assetRatio() external pure override returns (uint256[] memory) {
        uint256[] memory _assetRatio = new uint256[](1);
        _assetRatio[0] = 1;
        return _assetRatio;
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public view override {}

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public view override {}

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata)
        internal
        override
    {
        ILendingPool pool = provider.getLendingPool();

        _resetAndApprove(IERC20(tokens[0]), address(pool), amounts[0]);

        pool.deposit(tokens[0], amounts[0], address(this), 0);
    }

    function _redeemFromProtocol(address[] calldata tokens, uint256 ssts, uint256[] calldata) internal override {
        if (ssts == 0) {
            return;
        }

        uint256 aTokenWithdrawAmount = aToken.balanceOf(address(this)) * ssts / totalSupply();

        provider.getLendingPool().withdraw(tokens[0], aTokenWithdrawAmount, address(this));
    }

    function _emergencyWithdrawImpl(uint256[] calldata, address recipient) internal override {
        address[] memory tokens = assets();

        provider.getLendingPool().withdraw(tokens[0], type(uint256).max, recipient);
    }

    function _compound(address[] calldata tokens, SwapInfo[] calldata compoundSwapInfo, uint256[] calldata slippages)
        internal
        override
        returns (int256 compoundYield)
    {}

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId());

        uint256 currentNormalizedIncome = provider.getLendingPool().getReserveNormalizedIncome(tokens[0]);

        baseYieldPercentage = _calculateYieldPercentage(_lastNormalizedIncome, currentNormalizedIncome);
        _lastNormalizedIncome = currentNormalizedIncome;
    }

    function _swapAssets(address[] memory tokens, uint256[] memory toSwap, SwapInfo[] calldata swapInfo)
        internal
        override
    {}

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256)
    {
        uint256 aTokenBalance = aToken.balanceOf(address(this));
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId());

        return priceFeedManager.assetToUsdCustomPrice(tokens[0], aTokenBalance, exchangeRates[0]);
    }
}
