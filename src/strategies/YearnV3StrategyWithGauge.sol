// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/interfaces/IERC4626.sol";

import "./ERC4626StrategyDouble.sol";
import "../libraries/ERC4626Lib.sol";

import {IYearnGaugeV2} from "../external/interfaces/strategies/yearn/v2/IYearnGaugeV2.sol";

contract YearnV3StrategyWithGauge is ERC4626StrategyDouble {
    using SafeERC20 for IERC20;

    ISwapper public immutable swapper;
    IERC20 immutable rewardToken;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IERC4626 secondaryVault_,
        ISwapper swapper_
    ) ERC4626StrategyDouble(assetGroupRegistry_, accessControl_, secondaryVault_) {
        swapper = swapper_;
        rewardToken = IERC20(IYearnGaugeV2(address(secondaryVault_)).REWARD_TOKEN());
        if (address(rewardToken) == address(0)) revert ConfigurationAddressZero();
    }

    function _getProtocolRewardsInternal() internal virtual override returns (address[] memory, uint256[] memory) {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(rewardToken);
        IYearnGaugeV2(address(secondaryVault)).getReward();
        amounts[0] = IERC20(tokens[0]).balanceOf(address(this));
        return (tokens, amounts);
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
        IYearnGaugeV2(address(secondaryVault)).getReward();
        uint256 balance = rewardToken.balanceOf(address(this));
        if (balance > 0) {
            IERC20(rewardToken).safeTransfer(address(swapper), balance);
        }

        address[] memory rewards = new address[](1);
        rewards[0] = address(rewardToken);

        uint256 swappedAmount = swapper.swap(rewards, swapInfo, tokens, address(this))[0];

        uint256 sharesBefore = secondaryVault.balanceOf(address(this));
        uint256 sharesMinted = _depositToProtocolInternal(IERC20(tokens[0]), swappedAmount, slippages[3]);

        compoundedYieldPercentage = int256(YIELD_FULL_PERCENT * sharesMinted / sharesBefore);
    }
}
