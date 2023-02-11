// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/CommonErrors.sol";
import "./interfaces/ISwapper.sol";
import "./access/SpoolAccessControllable.sol";
import "./libraries/SpoolUtils.sol";

contract Swapper is ISwapper, SpoolAccessControllable {
    using SafeERC20 for IERC20;

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

    function swap(address[] calldata tokens, SwapInfo[] calldata swapInfo, address receiver) external {
        // Perform the swaps.
        for (uint256 i = 0; i < swapInfo.length; i++) {
            if (!exchangeAllowlist[swapInfo[i].swapTarget]) {
                revert ExchangeNotAllowed(swapInfo[i].swapTarget);
            }

            IERC20(swapInfo[i].token).safeApprove(swapInfo[i].swapTarget, swapInfo[i].amountIn);

            (bool success, bytes memory data) = swapInfo[i].swapTarget.call(swapInfo[i].swapCallData);
            if (!success) revert(SpoolUtils.getRevertMsg(data));

            IERC20(swapInfo[i].token).safeApprove(swapInfo[i].swapTarget, 0);
        }

        // Return unswapped tokens.
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransfer(receiver, IERC20(tokens[i]).balanceOf(address(this)));
        }
    }

    function updateExchangeAllowlist(address[] calldata exchanges, bool[] calldata allowed)
        external
        onlyRole(ROLE_SPOOL_ADMIN, msg.sender)
    {
        if (exchanges.length != allowed.length) {
            revert InvalidArrayLength();
        }

        for (uint256 i = 0; i < exchanges.length; ++i) {
            exchangeAllowlist[exchanges[i]] = allowed[i];

            emit ExchangeAllowlistUpdated(exchanges[i], allowed[i]);
        }
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function isExchangeAllowed(address exchange) external view returns (bool) {
        return exchangeAllowlist[exchange];
    }
}
