// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../src/Strategy.sol";

contract MockStrategy is Strategy {
    using SafeERC20 for IERC20;

    uint256[] public ratios;
    uint256[] public __withdrawnAssets;
    bool public __withdrawnAssetsSet;

    ISwapper _swapper;
    MockProtocol public protocol;

    constructor(
        string memory name_,
        IStrategyRegistry strategyRegistry_,
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_
    ) Strategy(name_, strategyRegistry_, assetGroupRegistry_, accessControl_) {
        _swapper = swapper_;
        protocol = new MockProtocol();
    }

    function test_mock() external pure {}

    function initialize(uint256 assetGroupId_, uint256[] memory ratios_) public virtual {
        super.initialize(assetGroupId_);

        ratios = ratios_;
    }

    function assetRatio() external view override returns (uint256[] memory) {
        return ratios;
    }

    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256[] memory) {
        require(__withdrawnAssetsSet, "MockStrategy::dhw: Withdrawn assets not set.");

        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(_assetGroupId);

        // withdraw from protocol
        for (uint256 i = 0; i < assetGroup.length; i++) {
            IERC20(assetGroup[i]).safeTransfer(receiver, __withdrawnAssets[i]);
        }

        // burn SSTs for withdrawal
        _burn(address(this), shares);

        __withdrawnAssetsSet = false;
        return __withdrawnAssets;
    }

    function setTotalUsdValue(uint256 totalUsdValue_) external {
        totalUsdValue = totalUsdValue_;
    }

    function swapAssets(address[] memory tokens, SwapInfo[] calldata swapInfo) internal override {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransfer(address(_swapper), IERC20(tokens[i]).balanceOf(address(this)));
        }

        _swapper.swap(tokens, swapInfo, address(this));
    }

    function depositToProtocol(address[] memory tokens, uint256[] memory amounts) internal override {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransfer(address(protocol), amounts[i]);
        }
    }

    function getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        override
        returns (uint256)
    {
        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(_assetGroupId);

        uint256 usdWorth = 0;
        for (uint256 i = 0; i < assetGroup.length; i++) {
            usdWorth += priceFeedManager.assetToUsdCustomPrice(
                assetGroup[i], IERC20(assetGroup[i]).balanceOf(address(protocol)), exchangeRates[i]
            );
        }

        return usdWorth;
    }

    function redeemFromProtocol(address[] memory tokens, uint256 ssts) internal override {
        if (ssts == 0) {
            return;
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 toWithdraw = IERC20(tokens[i]).balanceOf(address(protocol)) * ssts / totalSupply();
            protocol.withdraw(tokens[i], toWithdraw);
        }
    }
}

contract MockProtocol {
    using SafeERC20 for IERC20;

    function test_mock() external pure {}

    function withdraw(address token, uint256 amount) external {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
