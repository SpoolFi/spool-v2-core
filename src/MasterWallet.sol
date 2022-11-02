pragma solidity ^0.8.0;

import "./interfaces/IMasterWallet.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

// TODO: Access control
contract MasterWallet is IMasterWallet {
    mapping(address => bool) private _spenderWhitelist;

    function approve(IERC20 token, address spender, uint256 amount) external spenderWhitelisted(spender) {
        token.approve(spender, amount);
    }

    function resetApprove(IERC20 token, address spender) external spenderWhitelisted(spender) {
        token.approve(spender, 0);
    }

    function setSpenderWhitelist(address spender, bool canApprove) external {
        if (_spenderWhitelist[spender] == canApprove) {
            revert SpenderAlreadySet(spender);
        }

        _spenderWhitelist[spender] = canApprove;
    }

    function _checkSpenderWhitelist(address spender) private {
        if (!_spenderWhitelist[spender]) {
            revert SpenderNotAllowed(spender);
        }
    }

    modifier spenderWhitelisted(address spender) {
        _checkSpenderWhitelist(spender);
        _;
    }
}
