// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IIdleToken {
    function balanceOf(address _user) external view returns (uint256);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function token() external view returns (address);

    // NOTE: some idle tokens don't have this: https://docs.idle.finance/developers/best-yield/methods/tokenprice
    function tokenPriceWithFee(address _user) external view returns (uint256);

    function tokenPrice() external view returns (uint256);

    function getGovTokens() external view returns (address[] memory);

    function getGovTokensAmounts(address _user) external view returns (uint256[] memory);

    function mintIdleToken(uint256 _amount, bool _skipWholeRebalance, address _referral)
        external
        returns (uint256 mintedTokens);

    function redeemIdleToken(uint256 _amount) external returns (uint256 redeemedTokens);
}
