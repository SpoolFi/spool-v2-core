// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

interface ISmartVaultIncentives {
    /**
     * @notice TODO
     * @param vaults TODO
     * @param token TODO
     * @param amount TODO
     * @param incentivesEnd TODO
     */
    function addIncentives(
        address[] calldata vaults,
        address[][] calldata token,
        uint256[][] calldata amount,
        uint256[] calldata incentivesEnd
    ) external;

    /**
     * @notice TODO
     * @param vaults TODO
     * @param tokens TODO
     * @param incentivesEnd TODO
     */
    function extendIncentives(address[] calldata vaults, address[][] calldata tokens, uint256[] calldata incentivesEnd)
        external;

    /**
     * @notice TODO
     * @param vaults TODO
     * @param tokens TODO
     */
    function endIncentives(address[] calldata vaults, address[][] calldata tokens) external;

    /**
     * @notice TODO
     * @param vault TODO
     * @param token TODO
     */
    function blacklistIncentives(address vault, address token) external;
}
