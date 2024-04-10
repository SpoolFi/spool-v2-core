// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./ERC4626StrategyBase.sol";
import "../external/interfaces/strategies/gearbox/v3/IFarmingPool.sol";

contract GearboxV3ERC4626 is ERC4626StrategyBase {
    using SafeERC20 for IERC20;

    /// @notice Swapper implementation
    ISwapper public immutable swapper;

    /// @notice GEAR token
    /// @dev Reward token when participating in the Gearbox V3 protocol.
    IERC20 public immutable gear;

    /// @notice sdToken implementation (LP token)
    IFarmingPool public immutable sdToken;

    /// @notice maximum balance allowed of the staking token
    uint256 private constant _MAX_BALANCE = 1e32;

    error GearboxV3BeforeDepositCheckFailed();

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        ISwapper swapper_,
        IFarmingPool sdToken_,
        IERC4626 vault_
    ) ERC4626StrategyBase(assetGroupRegistry_, accessControl_, vault_, 10 ** (vault_.decimals() * 2)) {
        _disableInitializers();
        swapper = swapper_;
        gear = IERC20(sdToken_.rewardsToken());
        sdToken = sdToken_;
    }

    function initialize(string memory strategyName_, uint256 assetGroupId_) external initializer {
        __ERC4626Strategy_init(strategyName_, assetGroupId_);
    }

    function beforeDepositCheck_(uint256 assets) internal view override {
        if (assets + sdToken.balanceOf(address(this)) > _MAX_BALANCE) {
            revert GearboxV3BeforeDepositCheckFailed();
        }
    }

    function deposit_(uint256 amount) internal override returns (uint256) {
        _resetAndApprove(vault, address(sdToken), amount);
        sdToken.deposit(amount);
        return amount;
    }

    function _compound(address[] calldata tokens, SwapInfo[] calldata swapInfo, uint256[] calldata slippages)
        internal
        override
        returns (int256 compoundedYieldPercentage)
    {
        if (slippages[0] > 1) {
            revert CompoundSlippage();
        }
        if (swapInfo.length > 0) {
            uint256 gearBalance = _claimReward();

            if (gearBalance > 0) {
                gear.safeTransfer(address(swapper), gearBalance);
                address[] memory tokensIn = new address[](1);
                tokensIn[0] = address(gear);
                uint256 swappedAmount = swapper.swap(tokensIn, swapInfo, tokens, address(this))[0];

                if (swappedAmount > 0) {
                    uint256 sdTokenBalanceBefore = sdToken.balanceOf(address(this));
                    _depositToProtocolInternal(IERC20(tokens[0]), swappedAmount, slippages[3]);
                    compoundedYieldPercentage =
                        _calculateYieldPercentage(sdTokenBalanceBefore, sdToken.balanceOf(address(this)));
                }
            }
        }
    }

    function previewRedeemSSTs_(uint256 ssts) internal view override returns (uint256) {
        return (sdToken.balanceOf(address(this)) * ssts) / totalSupply();
    }

    function redeem_() internal override {
        _claimReward();
        redeem_(sdToken.balanceOf(address(this)));
    }

    function redeem_(uint256 shares) internal override returns (uint256) {
        sdToken.withdraw(shares);
        return shares;
    }

    function rewardInfo_() internal override returns (address, uint256) {
        return (address(gear), _claimReward());
    }

    function underlyingAssetAmount_() internal view override returns (uint256) {
        return vault.previewRedeem(sdToken.balanceOf(address(this)));
    }

    function _claimReward() internal returns (uint256) {
        sdToken.claim();
        return gear.balanceOf(address(this));
    }
}
