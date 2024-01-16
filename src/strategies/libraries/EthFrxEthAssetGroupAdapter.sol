// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "../../external/interfaces/strategies/frxEth/IFrxEthMinter.sol";
import "../../external/interfaces/strategies/frxEth/ISfrxEthToken.sol";
import "../../external/interfaces/strategies/curve/ICurvePool.sol";
import "../../external/interfaces/weth/IWETH9.sol";

library EthFrxEthAssetGroupAdapter {
    using SafeERC20 for IERC20;

    int128 constant CURVE_ETH_POOL_ETH_INDEX = 0;
    int128 constant CURVE_ETH_POOL_FRXETH_INDEX = 1;

    IERC20 constant frxEthToken = IERC20(0x5E8422345238F34275888049021821E8E08CAa1f);
    IFrxEthMinter constant frxEthMinter = IFrxEthMinter(0xbAFA44EFE7901E04E39Dad13167D089C559c1138);
    ICurveEthPool constant curve = ICurveEthPool(0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577);
    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    function wrap(uint256 amount, uint256 slippage) public returns (uint256 bought) {
        if (slippage == type(uint256).max) {
            _stake(amount);
            return amount;
        }
        bought = _buyOnCurve(amount, slippage);
    }

    function unwrap(uint256 amount, uint256 slippage) public returns (uint256 bought) {
        bought = _sellOnCurve(amount, slippage);
    }

    function _stake(uint256 amount) private {
        weth.withdraw(amount);
        frxEthMinter.submit{value: amount}();
    }

    function _buyOnCurve(uint256 amount, uint256 slippage) private returns (uint256 bought) {
        weth.withdraw(amount);
        bought = curve.exchange{value: amount}(CURVE_ETH_POOL_ETH_INDEX, CURVE_ETH_POOL_FRXETH_INDEX, amount, slippage);
    }

    function _sellOnCurve(uint256 amount, uint256 slippage) private returns (uint256 bought) {
        _resetAndApprove(IERC20(address(frxEthToken)), address(curve), amount);
        bought = curve.exchange(CURVE_ETH_POOL_FRXETH_INDEX, CURVE_ETH_POOL_ETH_INDEX, amount, slippage);
        weth.deposit{value: bought}();
    }

    function _resetAndApprove(IERC20 token, address spender, uint256 amount) private {
        _resetAllowance(token, spender);
        token.safeApprove(spender, amount);
    }

    function _resetAllowance(IERC20 token, address spender) private {
        if (token.allowance(address(this), spender) > 0) {
            token.safeApprove(spender, 0);
        }
    }
}
