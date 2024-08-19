// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IHypervisor {
    /// @param shares Number of liquidity tokens to redeem as pool assets
    /// @param to Address to which redeemed pool assets are sent
    /// @param from Address from which liquidity tokens are sent
    /// @param minAmounts min amount0,1 returned for shares of liq
    /// @return amount0 Amount of token0 redeemed by the submitted liquidity tokens
    /// @return amount1 Amount of token1 redeemed by the submitted liquidity tokens
    function withdraw(uint256 shares, address to, address from, uint256[4] memory minAmounts)
        external
        returns (uint256 amount0, uint256 amount1);

    function whitelistedAddress() external view returns (address);

    function pool() external view returns (address);

    function getTotalAmounts() external view returns (uint256, uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function PRECISION() external view returns (uint256);

    function owner() external view returns (address);

    function compound(uint256[4] memory) external;
}
