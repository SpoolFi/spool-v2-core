// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IUniProxy {
    function deposit(uint256 deposit0, uint256 deposit1, address to, address pos, uint256[4] memory minIn)
        external
        returns (uint256 shares);

    function getDepositAmount(address pos, address token, uint256 _deposit)
        external
        view
        returns (uint256 amountStart, uint256 amountEnd);

    function clearance() external view returns (address);
}
