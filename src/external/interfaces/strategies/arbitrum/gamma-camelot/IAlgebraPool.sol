// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IAlgebraPool {
    function token0() external returns (address);
    function token1() external returns (address);
    function globalState()
        external
        view
        returns (
            uint160 price,
            int24 tick,
            uint16 feeZto,
            uint16 feeOtz,
            uint16 timepointIndex,
            uint8 communityFeeToken0,
            uint8 communityFeeToken1,
            bool unlocked
        );
}
