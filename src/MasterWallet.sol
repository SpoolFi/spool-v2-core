pragma solidity ^0.8.0;

import "./interfaces/IMasterWallet.sol";
import "./access/SpoolAccessControl.sol";

// TODO: Access control
contract MasterWallet is IMasterWallet, SpoolAccessControllable {
    mapping(address => bool) private _managerAllowlist;

    constructor (ISpoolAccessControl accessControl) SpoolAccessControllable(accessControl) {}

    function approve(IERC20 token, address spender, uint256 amount) external onlyRole(ROLE_MASTER_WALLET_MANAGER, msg.sender) {
        token.approve(spender, amount);
    }

    function resetApprove(IERC20 token, address spender) external onlyRole(ROLE_MASTER_WALLET_MANAGER, msg.sender) {
        token.approve(spender, 0);
    }

    function transfer(IERC20 token, address recipient, uint256 amount) external onlyRole(ROLE_MASTER_WALLET_MANAGER, msg.sender) {
        token.transfer(recipient, amount);
    }
}
