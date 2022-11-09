pragma solidity ^0.8.0;

import "./interfaces/IMasterWallet.sol";

// TODO: Access control
contract MasterWallet is IMasterWallet {
    mapping(address => bool) private _managerAllowlist;

    function approve(IERC20 token, address spender, uint256 amount) external isManager {
        token.approve(spender, amount);
    }

    function resetApprove(IERC20 token, address spender) external isManager {
        token.approve(spender, 0);
    }

    function transfer(IERC20 token, address recipient, uint256 amount) external isManager {
        token.transfer(recipient, amount);
    }

    function setWalletManager(address manager, bool set) external {
        if (_managerAllowlist[manager] == set) {
            revert ManagerAlreadySet(manager);
        }

        _managerAllowlist[manager] = set;
    }

    function _checkManager() private view {
        if (!_managerAllowlist[msg.sender]) {
            revert ManagerNotAllowed(msg.sender);
        }
    }

    modifier isManager() {
        _checkManager();
        _;
    }
}
