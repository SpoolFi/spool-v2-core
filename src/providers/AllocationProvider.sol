// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../interfaces/IAllocationProvider.sol";
import "../interfaces/IRiskManager.sol";

contract AllocationProvider is IAllocationProvider {
    // @notice Risk manager
    IRiskManager internal immutable riskManager;

    uint256 constant PRECISION = 100_000;

    constructor(IRiskManager riskManager_) {
        riskManager = riskManager_;
    }

    function calculateAllocationProvider(AllocationCalculationInput calldata data)
        external
        view
        returns (uint256[] memory)
    {
        uint256 resSum = 0;

        uint256 apySum = 0;
        uint256 riskSum = 0;

        uint256[] memory results = new uint256[](data.strategies.length);

        uint24[21] memory riskArray = [
            100000,
            95000,
            900000,
            85000,
            80000,
            75000,
            70000,
            65000,
            60000,
            55000,
            50000,
            45000,
            40000,
            35000,
            30000,
            25000,
            20000,
            15000,
            10000,
            5000,
            0
        ];
        //uint8 [21] memory riskArray = [200,198,196,194,192,190,188,186,184,182,180,178,176,174,172,170,168,166,164,162,160]; // od 200 po 2 dol,
        //uint16 [21] memory riskArray = [10000,9950,9900,9850,9800,9750,9700,9650,9600,9550,9500,9450,9400,9350,9300,9250,9200,9150,9100,9050,9000]; // od 10000 po 50 dol
        //uint8 [21] memory riskArray = [25,24,23,22,21,20,19,18,17,16,15,14,13,12,11,10,9,8,7,6,5]; // od 25 po 1 dol

        uint256[] memory arrayRiskScores = riskManager.getRiskScores(data.riskProvider, data.strategies); // optimize
        for (uint8 i = 0; i < data.strategies.length; i++) {
            apySum += data.apys[i];
            riskSum += arrayRiskScores[i];
            // risk per protocol // todo if we need this....
        }

        int8 riskt = data.riskTolerance + 10; // od 0 - 20

        for (uint8 i = 0; i < data.strategies.length; i++) {
            uint256 apy = (data.apys[i] * PRECISION) / apySum;
            uint256 risk = (PRECISION - (arrayRiskScores[i] * PRECISION) / riskSum) / (data.strategies.length - 1);

            results[i] = apy * riskArray[uint8(20 - riskt)] + risk * riskArray[uint8(riskt)];

            resSum += results[i];
        }

        for (uint8 i = 0; i < results.length; i++) {
            results[i] = PRECISION * results[i] / resSum;
        }

        return results;
    }
}
