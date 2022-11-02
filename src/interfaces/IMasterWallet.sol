pragma solidity ^0.8.13;

import "@openzeppelin/token/ERC20/IERC20.sol";

error SpenderAlreadySet(address spender);
error SpenderNotAllowed(address spender);

interface IMasterWallet {
    function approve(IERC20 token, address spender, uint256 amount) external;

    function resetApprove(IERC20 token, address spender) external;

    function setSpenderWhitelist(address spender, bool canApprove) external;
}
