// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

interface IsUSDe is IERC4626 {
    /// @dev if it is zero USDe can be immediately withdrawn/redeemed via IERC4626
    function cooldownDuration() external returns (uint24);

    /// @dev if cooldownDuration > 0 this function is used instead of withdraw(uint256 assets, address receiver, address owner)
    function cooldownAssets(uint256 assets) external returns (uint256 shares);

    /// @dev if cooldownDuration > 0 this function is used instead of redeem(uint256 shares, address receiver, address owner)
    function cooldownShares(uint256 shares) external returns (uint256 assets);

    /// @dev after passing cooldown period (e.g. 1 week) assets can be withdrawn using this function
    function unstake(address receiver) external;

    function owner() external view returns (address);

    function setCooldownDuration(uint24 duration) external;

    function getUnvestedAmount() external returns (uint256);
}
