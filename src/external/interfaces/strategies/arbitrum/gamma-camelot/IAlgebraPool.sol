// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IAlgebraPool {
    function token0() external returns (address);
    function token1() external returns (address);
}
