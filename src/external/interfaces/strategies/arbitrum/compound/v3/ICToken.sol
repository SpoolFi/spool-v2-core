// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

interface ICToken is IERC20 {
    function borrow(uint256) external returns (uint256);

    function borrowRatePerBlock() external view returns (uint256);

    function borrowBalanceCurrent(address) external returns (uint256);

    function repayBorrow(uint256) external returns (uint256);
    function repayBorrow() external payable;

    function mint(uint256 underlying) external payable returns (uint256);
    function mint() external payable;

    function redeemUnderlying(uint256) external returns (uint256);

    function balanceOfUnderlying(address) external returns (uint256);

    function exchangeRateCurrent() external returns (uint256);
}