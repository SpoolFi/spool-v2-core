// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

interface IRocketSwapRouter {
    function rETH() external view returns (address);

    function swapTo(uint256 _uniswapPortion, uint256 _balancerPortion, uint256 _minTokensOut, uint256 _idealTokensOut)
        external
        payable;

    function swapFrom(
        uint256 _uniswapPortion,
        uint256 _balancerPortion,
        uint256 _minTokensOut,
        uint256 _idealTokensOut,
        uint256 _tokensIn
    ) external;
}
