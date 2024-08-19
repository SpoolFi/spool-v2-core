// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CometStructs} from "./IComet.sol";

interface IRewards {
    function getRewardOwed(address comet, address account) external returns (CometStructs.RewardOwed memory);
    function claim(address comet, address src, bool shouldAccrue) external;
}
