// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./ERC4626StrategyBase.sol";
import "../access/Roles.sol";

// slippages extension
// - for all actions
// - compound|underlyingRewardAmount: slippages[5]
contract MetamorphoStrategy is ERC4626StrategyBase {
    using SafeERC20 for IERC20;

    ISwapper public immutable swapper;

    /// @custom:storage-location erc7201:spool.storage.MetamorphoStrategy
    struct MetamorphoStrategyStorage {
        // we will set reward tokens for each strategy separately
        // rewards are claimed off-chain via UniversalRewardsDistributor
        // so for yield accrual we only need to know which tokens to swap and redeposit them back into metamorpho
        //
        // MORPHO token should not be included here for the time being
        // since it is not transferable right now
        // but we should claim it anyway and store in Strategy Contract
        // to decide how to deal with it once transfers are enabled
        address[] rewards;
    }

    // keccak256(abi.encode(uint256(keccak256("spool.storage.MetamorphoStrategy")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MetamorphoStrategyStorageLocation =
        0xba80ae0a45b1697a500a91d31dd2530d1622d0566cbb38bdf5b7a847a4c4ee00;

    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, ISwapper swapper_)
        ERC4626StrategyBase(assetGroupRegistry_, accessControl_)
    {
        _disableInitializers();
        swapper = swapper_;
    }

    function _getMetamorphoStrategyStorage() private pure returns (MetamorphoStrategyStorage storage $) {
        assembly {
            $.slot := MetamorphoStrategyStorageLocation
        }
    }

    function initialize(
        string memory strategyName_,
        uint256 assetGroupId_,
        IERC4626 vault_,
        uint256 constantShareAmount_,
        address[] calldata rewards_
    ) external initializer {
        __ERC4626Strategy_init(strategyName_, assetGroupId_, vault_, constantShareAmount_);
        MetamorphoStrategyStorage storage $ = _getMetamorphoStrategyStorage();
        $.rewards = rewards_;
    }

    /**
     * @dev spool admin is able to change reward tokens just in case
     * @notice in case vault shares are used elsewhere this function should be overwritten
     * @param rewards_ new array of reward tokens
     */
    function setRewards(address[] calldata rewards_) external {
        _checkRole(ROLE_SPOOL_ADMIN, msg.sender);
        MetamorphoStrategyStorage storage $ = _getMetamorphoStrategyStorage();
        $.rewards = rewards_;
    }

    function _getProtocolRewardsInternal() internal virtual override returns (address[] memory, uint256[] memory) {
        MetamorphoStrategyStorage memory $ = _getMetamorphoStrategyStorage();
        uint256[] memory amounts = new uint256[]($.rewards.length);
        address underlyingAsset = assets()[0];
        for (uint256 i; i < $.rewards.length; i++) {
            // for reward like underlying asset we will return 0
            // it should be calculated separately in DHW
            if (underlyingAsset != $.rewards[i]) {
                amounts[i] = IERC20($.rewards[i]).balanceOf(address(this));
            }
        }
        return ($.rewards, amounts);
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
        MetamorphoStrategyStorage memory $ = _getMetamorphoStrategyStorage();
        address underlyingAsset = assets()[0];
        for (uint256 i; i < $.rewards.length; ++i) {
            // we do not need to send underlying for swap
            if (underlyingAsset != $.rewards[i]) {
                uint256 balance = IERC20($.rewards[i]).balanceOf(address(this));
                if (balance > 0) {
                    IERC20($.rewards[i]).safeTransfer(address(swapper), balance);
                }
            }
        }

        uint256 swappedAmount = swapper.swap($.rewards, swapInfo, tokens, address(this))[0];

        uint256 sharesBefore = vault().balanceOf(address(this));
        // we should account for reward in same underlying token
        // if it zero it means there were no rewards yet
        // otherwise only this part is reinvested without minting shares
        uint256 underlyingForDeposit = slippages[5];
        uint256 sharesMinted =
            _depositToProtocolInternal(IERC20(tokens[0]), swappedAmount + underlyingForDeposit, slippages[3]);

        compoundedYieldPercentage = int256(YIELD_FULL_PERCENT * sharesMinted / sharesBefore);
    }
}
