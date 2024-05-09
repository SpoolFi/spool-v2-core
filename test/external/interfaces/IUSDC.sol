// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IUSDC {
    function masterMinter() external view returns (address);

    function mint(address dst, uint256 amount) external;

    function configureMinter(address minter, uint256 minterAllowedAmount) external returns (bool);
}
