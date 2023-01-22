// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/CommonErrors.sol";
import "./interfaces/IAssetGroupRegistry.sol";
import "./interfaces/IDepositSwap.sol";
import "./interfaces/ISmartVaultManager.sol";
import "./interfaces/ISwapper.sol";
import "./interfaces/IDepositManager.sol";

contract DepositSwap is IDepositSwap {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IAssetGroupRegistry private immutable _assetGroupRegistry;
    ISmartVaultManager private immutable _smartVaultManager;
    ISwapper private immutable _swapper;
    IDepositManager private immutable _depositManager;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISmartVaultManager smartVaultManager_,
        ISwapper swapper_,
        IDepositManager depositManager_
    ) {
        _assetGroupRegistry = assetGroupRegistry_;
        _smartVaultManager = smartVaultManager_;
        _swapper = swapper_;
        _depositManager = depositManager_;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    function swapAndDeposit(
        address[] calldata inTokens,
        uint256[] calldata inAmounts,
        SwapInfo[] calldata swapInfo,
        address smartVault,
        address receiver
    ) external returns (uint256) {
        if (inTokens.length != inAmounts.length) revert InvalidArrayLength();
        // Transfer the tokens from the caller to the swapper.
        for (uint256 i = 0; i < inTokens.length; i++) {
            IERC20(inTokens[i]).safeTransferFrom(msg.sender, address(_swapper), inAmounts[i]);
        }

        // Make the swap.
        _swapper.swap(inTokens, swapInfo, address(this));

        address[] memory outTokens = _assetGroupRegistry.listAssetGroup(_smartVaultManager.assetGroupId(smartVault));
        uint256[] memory outAmounts = new uint256[](outTokens.length);
        // Figure out how much we got out of the swap.
        for (uint256 i = 0; i < outTokens.length; i++) {
            outAmounts[i] = IERC20(outTokens[i]).balanceOf(address(this));
            IERC20(outTokens[i]).safeApprove(address(_depositManager), outAmounts[i]);
        }

        // Deposit into the smart vault.
        uint256 nftId = _smartVaultManager.depositFor(smartVault, outAmounts, receiver, address(this), address(0));

        // Return unswapped tokens.
        for (uint256 i = 0; i < inTokens.length; i++) {
            IERC20(inTokens[i]).safeTransfer(msg.sender, IERC20(inTokens[i]).balanceOf(address(this)));
        }

        return nftId;
    }
}
