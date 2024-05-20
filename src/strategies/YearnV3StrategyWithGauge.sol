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

    function _getProtocolRewardsInternal() internal override returns (address[] memory, uint256[] memory) {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        IERC4626 secondaryVault_ = secondaryVault();
        tokens[0] = IYearnGaugeV2(address(secondaryVault_)).REWARD_TOKEN();
        IYearnGaugeV2(address(secondaryVault_)).getReward();
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
        IERC4626 secondaryVault_ = secondaryVault();
        IYearnGaugeV2(address(secondaryVault_)).getReward();
        address[] memory rewards = new address[](1);
        rewards[0] = IYearnGaugeV2(address(secondaryVault_)).REWARD_TOKEN();
        uint256 balance = IERC20(rewards[0]).balanceOf(address(this));
        if (balance > 0) {
            IERC20(rewards[0]).safeTransfer(address(swapper), balance);
            uint256 swappedAmount = swapper.swap(rewards, swapInfo, tokens, address(this))[0];

            uint256 sharesBefore = secondaryVault_.balanceOf(address(this));
            uint256 sharesMinted = _depositToProtocolInternal(IERC20(tokens[0]), swappedAmount, slippages[3]);

            compoundedYieldPercentage = int256(YIELD_FULL_PERCENT * sharesMinted / sharesBefore);
        }
    }
}
