// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/utils/math/Math.sol";
import "../../src/Strategy.sol";
import "../external/uniswap/interfaces/IUniswapV2Factory.sol";
import "../external/uniswap/interfaces/IUniswapV2Router02.sol";
import "../external/uniswap/interfaces/IUniswapV2Pair.sol";
import "../external/uniswap/libraries/UniswapV2Library.sol";

contract MockUniswapV2Strategy is Strategy {
    using SafeERC20 for IERC20;

    IUniswapV2Router02 public immutable uniswapRouter;
    IUniswapV2Factory public immutable uniswapFactory;
    IUniswapV2Pair public uniswapPair;

    constructor(
        string memory name_,
        IStrategyRegistry strategyRegistry_,
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IUniswapV2Router02 uniswapRouter_
    ) Strategy(name_, strategyRegistry_, assetGroupRegistry_, accessControl_) {
        uniswapRouter = uniswapRouter_;
        uniswapFactory = IUniswapV2Factory(uniswapRouter_.factory());
    }

    function test_mock() external pure {}

    function initialize(uint256 assetGroupId_) external initializer {
        __Strategy_init(assetGroupId_);

        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupId_);

        require(assetGroup.length == 2, "MockUniswapV2Strategy::initialize: Asset group must contain 2 assets");

        address pairAddress = uniswapFactory.getPair(assetGroup[0], assetGroup[1]);
        require(pairAddress != address(0), "MockUniswapV2Strategy::initialize: Uniswap pair does not exist");

        uniswapPair = IUniswapV2Pair(pairAddress);
    }

    function assetRatio() external view override returns (uint256[] memory) {
        // NOTE: NOT OK, NEEDS SOME SLIPPAGES/CONSTRAINTS
        (uint112 reserve0, uint112 reserve1,) = uniswapPair.getReserves();

        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(_assetGroupId);
        (address tokenA,) = UniswapV2Library.sortTokens(assetGroup[0], assetGroup[1]);

        if (tokenA != assetGroup[0]) {
            (reserve0, reserve1) = (reserve1, reserve0);
        }

        uint256[] memory _assetRatio = new uint256[](2);
        _assetRatio[0] = reserve0;
        _assetRatio[1] = reserve1;

        return _assetRatio;
    }

    function swapAssets(address[] memory tokens, SwapInfo[] calldata swapInfo) internal override {}

    function compound() internal override {}

    // NOTE: IMPORTAINT - asset ratio needs to be perfect for this, otherwise assets are lost
    // can use the formula for uniswap v2 swap + add liquidity (https://blog.alphaventuredao.io/onesideduniswap/)
    function depositToProtocol(address[] memory tokens, uint256[] memory amounts) internal override {
        // TODO: add reserves and tokens ratio check

        if (amounts[0] > 0) {
            IERC20(tokens[0]).safeTransfer(address(uniswapPair), amounts[0]);
            IERC20(tokens[1]).safeTransfer(address(uniswapPair), amounts[1]);

            uniswapPair.mint(address(this));
        }
    }

    // NOTE: add slippage
    function getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256)
    {
        uint256 lpBalance = uniswapPair.balanceOf(address(this));
        if (lpBalance == 0) {
            return 0;
        }

        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(_assetGroupId);
        (address tokenA,) = UniswapV2Library.sortTokens(assetGroup[0], assetGroup[1]);

        (uint256 reserveA, uint256 reserveB,) = uniswapPair.getReserves();

        if (tokenA != assetGroup[0]) {
            (reserveA, reserveB) = (reserveB, reserveA);
        }

        uint256 usdWorth = priceFeedManager.assetToUsdCustomPrice(assetGroup[0], reserveA, exchangeRates[0]);

        usdWorth += priceFeedManager.assetToUsdCustomPrice(assetGroup[1], reserveB, exchangeRates[1]);

        return Math.mulDiv(usdWorth, lpBalance, uniswapPair.totalSupply());
    }

    function redeemFromProtocol(address[] memory, uint256 ssts) internal override {
        if (ssts == 0) {
            return;
        }

        uint256 lpBalance = uniswapPair.balanceOf(address(this));

        uint256 toWithdraw = Math.mulDiv(lpBalance, ssts, totalSupply());

        uniswapPair.transfer(address(uniswapPair), toWithdraw);

        // NOTE: add slippage
        uniswapPair.burn(address(this));
    }
}
