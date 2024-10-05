// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./ERC4626StrategyBase.sol";
import "./helpers/SwapAdapter.sol";
import "./helpers/WethHelper.sol";
import "../external/interfaces/strategies/apxEth/IPirexEth.sol";
import "../interfaces/ISwapper.sol";

contract ApxEthHoldingStrategy is ERC4626StrategyBase, SwapAdapter, WethHelper {
    using SafeERC20 for IERC20;

    /// @notice PirexEth protocol deposit contract implementation
    IPirexEth public pirexEth;

    /// @notice pxEth token implementation
    IERC20 public pxEth;

    /// @notice Swapper implementation
    ISwapper public immutable swapper;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        address weth_
    ) ERC4626StrategyBase(assetGroupRegistry_, accessControl_) WethHelper(weth_) {
        _disableInitializers();

        swapper = swapper_;
    }

    function initialize(string memory strategyName_, uint256 assetGroupId_, IPirexEth _pirexEth) external initializer {
        IERC4626 apxEth = IERC4626(_pirexEth.autoPxEth());
        pxEth = IERC20(_pirexEth.pxEth());
        pirexEth = _pirexEth;

        uint256 constantShareAmount_ = 10 ** (apxEth.decimals() * 2);
        __ERC4626Strategy_init(strategyName_, assetGroupId_, apxEth, constantShareAmount_);
    }

    function beforeDepositCheck(uint256[] memory, uint256[] calldata) public view override {}
    function beforeRedeemalCheck(uint256, uint256[] calldata) public view override {}

    function _depositToProtocol(address[] calldata, uint256[] memory amounts, uint256[] calldata) internal override {
        // WETH -> ETH
        unwrapEth(amounts[0]);

        // ETH -> pxETH -> apxETH (compounding flag autodeposits to vault)
        pirexEth.deposit{value: amounts[0]}(address(this), true);
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata slippages) internal override {
        // apxETH -> pxETH
        uint256 shares = previewRedeemSSTs_(ssts);
        if (shares > 0) {
            vault().redeem(redeem_(shares), address(this), address(this));
        }

        // pxETH -> WETH
        _performSwap(slippages);
    }

    function _emergencyWithdrawImpl(uint256[] calldata slippages, address recipient) internal override {
        // apxETH -> pxETH
        vault().redeem(ERC4626Lib.getMaxRedeem(vault()), address(this), address(this));

        // pxETH -> WETH
        _performSwap(slippages);

        // Transfer all WETH to recipient
        uint256 balance = IERC20(weth).balanceOf(address(this));
        if (balance > 0) {
            IERC20(weth).safeTransfer(recipient, balance);
        }
    }

    function _performSwap(uint256[] calldata slippages) private {
        uint256 balance = pxEth.balanceOf(address(this));
        if (balance > 0) {
            _swap(swapper, address(pxEth), weth, balance, slippages, 0);
        }
    }

    function _invalidAssetGroupToken(address[] memory tokens, IERC4626 vault_) internal view override returns (bool) {
        return tokens[0] != weth || address(pxEth) != vault_.asset();
    }

    /**
     * @dev used for calculation of yield
     * @dev cannot use previewRedeem as it underflows for share amount > totalSupply
     * @return amount of assets which will be obtained from constant amount of shares
     */
    function previewConstantRedeem_() internal view override returns (uint256) {
        return vault().convertToAssets(constantShareAmount());
    }
}
