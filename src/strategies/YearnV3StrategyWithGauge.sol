// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./ERC4626StrategyDouble.sol";
import {IYearnGaugeV2} from "../external/interfaces/strategies/yearn/v2/IYearnGaugeV2.sol";

/// @dev by staking primary shares into ERC4626 compliant Gauge contract (secondaryVault)
/// we will get dYFI rewards which are compounded
contract YearnV3StrategyWithGauge is ERC4626StrategyDouble {
    using SafeERC20 for IERC20;

    ISwapper public immutable swapper;

    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, ISwapper swapper_)
        ERC4626StrategyDouble(assetGroupRegistry_, accessControl_)
    {
        swapper = swapper_;
    }

    function initialize(
        string memory strategyName_,
        uint256 assetGroupId_,
        IERC4626 vault_,
        IERC4626 secondaryVault_,
        uint256 constantShareAmount_
    ) external initializer {
        if (address(IYearnGaugeV2(address(secondaryVault_)).REWARD_TOKEN()) == address(0)) {
            revert ConfigurationAddressZero();
        }
        __ERC4626StrategyDouble_init(strategyName_, assetGroupId_, vault_, secondaryVault_, constantShareAmount_);
    }

    function _getProtocolRewardsInternal()
        internal
        override
        returns (address[] memory rewards, uint256[] memory amounts)
    {
        rewards = new address[](1);
        amounts = new uint256[](1);

        IYearnGaugeV2 secondaryVault_ = IYearnGaugeV2(address(secondaryVault()));
        rewards[0] = secondaryVault_.REWARD_TOKEN();

        secondaryVault_.getReward();
        amounts[0] = IERC20(rewards[0]).balanceOf(address(this));
        if (amounts[0] > 0) {
            IERC20(rewards[0]).safeTransfer(address(swapper), amounts[0]);
        }
        return (rewards, amounts);
    }

    function _compound(address[] calldata tokens, SwapInfo[] calldata swapInfo, uint256[] calldata slippages)
        internal
        override
        returns (int256 compoundedYieldPercentage)
    {
        if (swapInfo.length == 0) {
            return compoundedYieldPercentage;
        }
        if (slippages[0] > 1) {
            revert CompoundSlippage();
        }
        (address[] memory rewards,) = _getProtocolRewardsInternal();
        uint256 swappedAmount = swapper.swap(rewards, swapInfo, tokens, address(this))[0];
        uint256 sharesBefore = secondaryVault().balanceOf(address(this));
        uint256 sharesMinted = _depositToProtocolInternal(IERC20(tokens[0]), swappedAmount, slippages[3]);
        compoundedYieldPercentage = int256(YIELD_FULL_PERCENT * sharesMinted / sharesBefore);
    }
}
