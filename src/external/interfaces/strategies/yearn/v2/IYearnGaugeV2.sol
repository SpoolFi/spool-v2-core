// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/interfaces/IERC4626.sol";

interface IYearnGaugeV2 is IERC4626 {
    function getReward() external returns (bool);
    function REWARD_TOKEN() external returns (address);
}
