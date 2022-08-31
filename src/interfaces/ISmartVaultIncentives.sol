// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface ISmartVaultIncentives {
    /**
     * @notice TODO
     * @param vaults
     * @param tokens
     * @param amounts
     * @param incentivesEnd
     */
    function addIncentives(address[] vaults, address[][] token, uint256[][] calldata amount, uint256[] calldata incentivesEnd);

    /**
     * @notice TODO
     * @param vaults
     * @param tokens
     * @param incentivesEnd
     */
    function extendIncentives(address[] calldata vaults, address[][] calldata tokens, uint256[] calldata incentivesEnd);

    /**
     * @notice TODO
     * @param vaults
     * @param tokens
     */
    function endIncentives(address[] calldata vaults, address[][] calldata tokens);

    /**
     * @notice TODO
     * @param vaults
     * @param token
     * @param amount
     * @param incentivesEnd
     */
    function blacklistIncentives(address vault, address token);
}
