// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "../../external/interfaces/strategies/stEth/ILido.sol";
import "../../external/interfaces/strategies/curve/ICurvePool.sol";

library EthStEthAssetGroupAdapter {
    using SafeERC20 for IERC20;

    int128 constant CURVE_ETH_POOL_ETH_INDEX = 0;
    int128 constant CURVE_ETH_POOL_STETH_INDEX = 1;

    ILido constant lido = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    ICurveEthPool constant curve = ICurveEthPool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

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
        lido.submit{value: amount}(address(this));
    }

    function _buyOnCurve(uint256 amount, uint256 slippage) private returns (uint256 bought) {
        bought = curve.exchange{value: amount}(CURVE_ETH_POOL_ETH_INDEX, CURVE_ETH_POOL_STETH_INDEX, amount, slippage);
    }

    function _sellOnCurve(uint256 amount, uint256 slippage) private returns (uint256 bought) {
        _resetAndApprove(IERC20(address(lido)), address(curve), amount);
        bought = curve.exchange(CURVE_ETH_POOL_STETH_INDEX, CURVE_ETH_POOL_ETH_INDEX, amount, slippage);
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
