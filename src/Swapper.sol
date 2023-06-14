// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ISwapper.sol";
import "./interfaces/CommonErrors.sol";
import "./access/SpoolAccessControllable.sol";
import "./libraries/SpoolUtils.sol";
import "@openzeppelin/utils/Address.sol";

contract Swapper is ISwapper, SpoolAccessControllable {
    using SafeERC20 for IERC20;
    using Address for address;

    /* ========== STATE VARIABLES ========== */

    /**
     * @dev Exchanges that are allowed to execute a swap.
     */
    mapping(address => bool) private exchangeAllowlist;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @param accessControl_ Access control for Spool ecosystem.
     */
    constructor(ISpoolAccessControl accessControl_) SpoolAccessControllable(accessControl_) {}

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function swap(
        address[] calldata tokensIn,
        SwapInfo[] calldata swapInfo,
        address[] calldata tokensOut,
        address receiver
    ) external returns (uint256[] memory tokenAmounts) {
        _isAllowedToSwap();

        uint256[] memory amountsIn = new uint256[](tokensIn.length);

        for (uint256 i; i < tokensIn.length; ++i) {
            amountsIn[i] = IERC20(tokensIn[i]).balanceOf(address(this));
        }

        // Perform the swaps.
        for (uint256 i; i < swapInfo.length; ++i) {
            if (!swapInfo[i].swapTarget.isContract()) {
                revert AddressNotContract(swapInfo[i].swapTarget);
            }

            if (!exchangeAllowlist[swapInfo[i].swapTarget]) {
                revert ExchangeNotAllowed(swapInfo[i].swapTarget);
            }

            _approveMax(IERC20(swapInfo[i].token), swapInfo[i].swapTarget);

            (bool success, bytes memory data) = swapInfo[i].swapTarget.call(swapInfo[i].swapCallData);
            if (!success) revert(SpoolUtils.getRevertMsg(data));
        }

        tokenAmounts = new uint256[](tokensOut.length);
        for (uint256 i; i < tokensOut.length; ++i) {
            tokenAmounts[i] = IERC20(tokensOut[i]).balanceOf(address(this));
            if (tokenAmounts[i] > 0) {
                IERC20(tokensOut[i]).safeTransfer(receiver, tokenAmounts[i]);
            }
        }

        // Return unswapped tokens.
        for (uint256 i; i < tokensIn.length; ++i) {
            uint256 tokenInBalance = IERC20(tokensIn[i]).balanceOf(address(this));
            if (tokenInBalance > 0) {
                IERC20(tokensIn[i]).safeTransfer(receiver, tokenInBalance);
            }
        }

        emit Swapped(receiver, tokensIn, tokensOut, amountsIn, tokenAmounts);
    }

    function updateExchangeAllowlist(address[] calldata exchanges, bool[] calldata allowed)
        external
        onlyRole(ROLE_SPOOL_ADMIN, msg.sender)
    {
        if (exchanges.length != allowed.length) {
            revert InvalidArrayLength();
        }

        for (uint256 i; i < exchanges.length; ++i) {
            exchangeAllowlist[exchanges[i]] = allowed[i];

            emit ExchangeAllowlistUpdated(exchanges[i], allowed[i]);
        }
    }

    function _approveMax(IERC20 token, address spender) private {
        if (token.allowance(address(this), spender) == 0) {
            token.safeApprove(spender, type(uint256).max);
        }
    }

    function _isAllowedToSwap() private view {
        if (!_accessControl.hasRole(ROLE_STRATEGY, msg.sender) && !_accessControl.hasRole(ROLE_SWAPPER, msg.sender)) {
            revert NotSwapper(msg.sender);
        }
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function isExchangeAllowed(address exchange) external view returns (bool) {
        return exchangeAllowlist[exchange];
    }
}
