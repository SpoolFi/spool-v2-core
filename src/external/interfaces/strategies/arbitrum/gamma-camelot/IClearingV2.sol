// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IClearingV2 {
    struct Position {
        bool customRatio;
        bool customTwap;
        bool ratioRemoved;
        bool depositOverride; // force custom deposit constraints
        bool twapOverride; // force twap check for hypervisor instance
        uint8 version;
        uint32 twapInterval; // override global twap
        uint256 priceThreshold; // custom price threshold
        uint256 deposit0Max;
        uint256 deposit1Max;
        uint256 maxTotalSupply;
        uint256 fauxTotal0;
        uint256 fauxTotal1;
        uint256 customDepositDelta;
    }

    function positions(address) external view returns (Position memory);
    function checkPriceChange(address, uint32, uint256) external view returns (uint256);
    function twapInterval() external view returns (uint32);
    function priceThreshold() external view returns (uint256);
}
