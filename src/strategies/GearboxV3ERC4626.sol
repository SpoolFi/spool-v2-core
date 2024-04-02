// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./AbstractERC4626Strategy.sol";
import "../external/interfaces/strategies/gearbox/v3/IFarmingPool.sol";

contract GearboxV3ERC4626 is AbstractERC4626Strategy {
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
    ) AbstractERC4626Strategy(assetGroupRegistry_, accessControl_, vault_) {
        _disableInitializers();
        swapper = swapper_;
        gear = IERC20(sdToken_.rewardsToken());
        sdToken = sdToken_;
    }

    function initialize(
        string memory strategyName_,
        uint256 assetGroupId_
    ) external initializer {
        __ERC4626Strategy_init(strategyName_, assetGroupId_);
    }

    function vaultShareBalance_() internal view override returns (uint256) {
        return sdToken.balanceOf(address(this));
    }

    function beforeDepositCheck_(
        uint256[] memory,
        uint256[] calldata
    ) internal view override {
        if (sdToken.balanceOf(address(this)) > _MAX_BALANCE) {
            revert GearboxV3BeforeDepositCheckFailed();
        }
    }

    function beforeRedeemalCheck_(
        uint256 ssts,
        uint256[] calldata slippages
    ) internal view override {}

    function deposit_() internal override {
        deposit_(vault.balanceOf(address(this)));
    }

    function deposit_(uint256 amount) internal override {
        _resetAndApprove(vault, address(sdToken), amount);
        sdToken.deposit(amount);
    }

    function withdraw_() internal override {
        _claimReward();
        withdraw_(sdToken.balanceOf(address(this)));
    }

    function withdraw_(uint256 sharesToGet) internal override {
        sdToken.withdraw(sharesToGet);
    }

    function compound_(
        address[] calldata tokens,
        SwapInfo[] calldata swapInfo,
        uint256[] calldata
    ) internal override returns (int256 compoundedYieldPercentage) {
        if (swapInfo.length > 0) {
            uint256 gearBalance = _claimReward();

            if (gearBalance > 0) {
                gear.safeTransfer(address(swapper), gearBalance);
                address[] memory tokensIn = new address[](1);
                tokensIn[0] = address(gear);
                uint256 swappedAmount = swapper.swap(
                    tokensIn,
                    swapInfo,
                    tokens,
                    address(this)
                )[0];

                if (swappedAmount > 0) {
                    uint256 sdTokenBalanceBefore = sdToken.balanceOf(
                        address(this)
                    );
                    _depositToProtocolInternal(
                        IERC20(tokens[0]),
                        swappedAmount
                    );
                    compoundedYieldPercentage = _calculateYieldPercentage(
                        sdTokenBalanceBefore,
                        sdToken.balanceOf(address(this))
                    );
                }
            }
        }
    }

    function rewardInfo_() internal override returns (address, uint256) {
        return (address(gear), _claimReward());
    }

    function _claimReward() internal returns (uint256) {
        sdToken.claim();
        return gear.balanceOf(address(this));
    }
}
