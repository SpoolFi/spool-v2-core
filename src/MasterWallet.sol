// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IMasterWallet.sol";
import "./access/SpoolAccessControllable.sol";

contract MasterWallet is IMasterWallet, SpoolAccessControllable {
    using SafeERC20 for IERC20;

    constructor(ISpoolAccessControl accessControl_) SpoolAccessControllable(accessControl_) {}

    function transfer(IERC20 token, address recipient, uint256 amount)
        external
        onlyRole(ROLE_MASTER_WALLET_MANAGER, msg.sender)
    {
        token.safeTransfer(recipient, amount);
    }
}
