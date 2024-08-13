// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./external/interfaces/weth/IWETH9.sol";
import "./interfaces/IAssetGroupRegistry.sol";
import "./interfaces/IDepositManager.sol";
import "./interfaces/IDepositSwap.sol";
import "./interfaces/ISmartVaultManager.sol";
import "./interfaces/ISwapper.sol";
import "./interfaces/IMetaVault.sol";
import "./interfaces/CommonErrors.sol";

/**
 * @dev Requires roles:
 * - ROLE_SWAPPER
 */
contract DepositSwap is IDepositSwap {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IWETH9 private immutable _weth;
    IAssetGroupRegistry private immutable _assetGroupRegistry;
    ISmartVaultManager private immutable _smartVaultManager;
    ISwapper private immutable _swapper;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        IWETH9 weth_,
        IAssetGroupRegistry assetGroupRegistry_,
        ISmartVaultManager smartVaultManager_,
        ISwapper swapper_
    ) {
        if (address(weth_) == address(0)) revert ConfigurationAddressZero();
        if (address(assetGroupRegistry_) == address(0)) revert ConfigurationAddressZero();
        if (address(smartVaultManager_) == address(0)) revert ConfigurationAddressZero();
        if (address(swapper_) == address(0)) revert ConfigurationAddressZero();

        _weth = weth_;
        _assetGroupRegistry = assetGroupRegistry_;
        _smartVaultManager = smartVaultManager_;
        _swapper = swapper_;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    function swapAndDeposit(SwapDepositBag calldata swapDepositBag) external payable returns (uint256 nftId) {
        _prepareSwap(swapDepositBag.inTokens, swapDepositBag.inAmounts);

        address[] memory outTokens =
            _assetGroupRegistry.listAssetGroup(_smartVaultManager.assetGroupId(swapDepositBag.smartVault));

        uint256[] memory outAmounts =
            _doSwap(swapDepositBag.inTokens, swapDepositBag.swapInfo, outTokens, address(_smartVaultManager));
        // Deposit into the smart vault.
        nftId = _smartVaultManager.deposit(
            DepositBag(
                swapDepositBag.smartVault,
                outAmounts,
                swapDepositBag.receiver,
                swapDepositBag.referral,
                swapDepositBag.doFlush
            )
        );

        _finalizeSwap(swapDepositBag.inTokens);
    }

    function swapAndDepositIntoMetaVault(
        IMetaVault metaVault,
        address[] calldata inTokens,
        uint256[] calldata inAmounts,
        SwapInfo[] calldata swapInfo
    ) external payable {
        _prepareSwap(inTokens, inAmounts);

        address[] memory outTokens = new address[](1);
        outTokens[0] = metaVault.asset();

        uint256[] memory outAmounts = _doSwap(inTokens, swapInfo, outTokens, address(metaVault));
        // Deposit into the smart vault.
        metaVault.deposit(outAmounts[0], msg.sender);

        _finalizeSwap(inTokens);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _prepareSwap(address[] calldata inTokens, uint256[] calldata inAmounts) internal {
        if (inTokens.length != inAmounts.length) revert InvalidArrayLength();

        // Wrap eth if needed.
        if (msg.value > 0) {
            _weth.deposit{value: msg.value}();
        }

        // Transfer the tokens from the caller to the swapper.
        for (uint256 i; i < inTokens.length; ++i) {
            IERC20(inTokens[i]).safeTransferFrom(msg.sender, address(_swapper), inAmounts[i]);

            if (inTokens[i] == address(_weth) && msg.value > 0) {
                IERC20(address(_weth)).safeTransfer(address(_swapper), msg.value);
            }
        }
    }

    function _doSwap(
        address[] calldata inTokens,
        SwapInfo[] calldata swapInfo,
        address[] memory outTokens,
        address target
    ) internal returns (uint256[] memory outAmounts) {
        // Make the swap.
        _swapper.swap(inTokens, swapInfo, outTokens, address(this));
        outAmounts = new uint256[](outTokens.length);
        // Figure out how much we got out of the swap.
        for (uint256 i; i < outTokens.length; ++i) {
            outAmounts[i] = IERC20(outTokens[i]).balanceOf(address(this));
            IERC20(outTokens[i]).safeApprove(target, outAmounts[i]);
        }
    }

    function _finalizeSwap(address[] calldata inTokens) internal {
        // Return unswapped tokens.
        uint256 returnBalance;
        for (uint256 i; i < inTokens.length; ++i) {
            returnBalance = IERC20(inTokens[i]).balanceOf(address(this));
            if (returnBalance > 0) {
                IERC20(inTokens[i]).safeTransfer(msg.sender, returnBalance);
            }
        }
        if (msg.value > 0) {
            returnBalance = IERC20(address(_weth)).balanceOf(address(this));
            if (returnBalance > 0) {
                IERC20(address(_weth)).safeTransfer(msg.sender, returnBalance);
            }
        }

        // send back eth if swapper returns eth
        if (address(this).balance > 0) {
            payable(msg.sender).transfer(address(this).balance);
        }
    }
}
