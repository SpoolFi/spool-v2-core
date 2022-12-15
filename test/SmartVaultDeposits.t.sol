// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../src/libraries/SmartVaultDeposits.sol";
import "./libraries/Arrays.sol";

contract SmartVaultDepositsTest is Test {
    uint256[] exchangeRates;
    uint256[] allocation;
    uint256[][] strategyRatios;

    function setUp() public {
        exchangeRates = Arrays.toArray(1200 * 10 ** 26, 16400 * 10 ** 26, 270 * 10 ** 26);
        allocation = Arrays.toArray(600, 300, 100);

        strategyRatios = new uint256[][](3);
        strategyRatios[0] = Arrays.toArray(1000, 71, 4300);
        strategyRatios[1] = Arrays.toArray(1000, 74, 4500);
        strategyRatios[2] = Arrays.toArray(1000, 76, 4600);
    }

    function test_calculateFlushFactors_shouldCalculateFlushFactors() public {
        uint256[][] memory flushFactors =
            SmartVaultDeposits.calculateFlushFactors(exchangeRates, allocation, strategyRatios);

        assertEq(flushFactors[0][0], 1701934532251659);
        assertEq(flushFactors[0][1], 120837351789867);
        assertEq(flushFactors[0][2], 7318318488682135);

        assertEq(flushFactors[1][0], 826765143581546);
        assertEq(flushFactors[1][1], 61180620625034);
        assertEq(flushFactors[1][2], 3720443146116959);

        assertEq(flushFactors[2][0], 271120268951306);
        assertEq(flushFactors[2][1], 20605140440299);
        assertEq(flushFactors[2][2], 1247153237176011);
    }

    function test_calculateDepositRatio_shouldCalculateDepositRatio() public {
        uint256[] memory depositRatio =
            SmartVaultDeposits.calculateDepositRatio(exchangeRates, allocation, strategyRatios);

        assertEq(depositRatio[0], 2799819944784511);
        assertEq(depositRatio[1], 202623112855200);
        assertEq(depositRatio[2], 12285914871975105);
    }

    function test_checkDepositRatio_shouldPassIfDepositIsCloseEnough() public {
        uint256[] memory deposit;

        deposit = Arrays.toArray(2799819944784511, 202623112855200, 12285914871975105);
        SmartVaultDeposits.checkDepositRatio(deposit, exchangeRates, allocation, strategyRatios);

        deposit = Arrays.toArray(279981994478451100, 20262311285520000, 1228591487197510500);
        SmartVaultDeposits.checkDepositRatio(deposit, exchangeRates, allocation, strategyRatios);

        deposit = Arrays.toArray(2799819944784, 202623112855, 12285914871975);
        SmartVaultDeposits.checkDepositRatio(deposit, exchangeRates, allocation, strategyRatios);

        deposit = Arrays.toArray(5599639889569022, 405246225710400, 24571829743950210);
        SmartVaultDeposits.checkDepositRatio(deposit, exchangeRates, allocation, strategyRatios);
    }

    function test_checkDepositRatio_shouldRevertIfDepositIsNotCloseEnough() public {
        uint256[] memory deposit;

        deposit = Arrays.toArray(1799819944784511, 202623112855200, 12285914871975105);
        vm.expectRevert(IncorrectDepositRatio.selector);
        SmartVaultDeposits.checkDepositRatio(deposit, exchangeRates, allocation, strategyRatios);

        deposit = Arrays.toArray(3799819944784511, 202623112855200, 12285914871975105);
        vm.expectRevert(IncorrectDepositRatio.selector);
        SmartVaultDeposits.checkDepositRatio(deposit, exchangeRates, allocation, strategyRatios);

        deposit = Arrays.toArray(2799819944784511, 102623112855200, 12285914871975105);
        vm.expectRevert(IncorrectDepositRatio.selector);
        SmartVaultDeposits.checkDepositRatio(deposit, exchangeRates, allocation, strategyRatios);

        deposit = Arrays.toArray(2799819944784511, 302623112855200, 12285914871975105);
        vm.expectRevert(IncorrectDepositRatio.selector);
        SmartVaultDeposits.checkDepositRatio(deposit, exchangeRates, allocation, strategyRatios);

        deposit = Arrays.toArray(2799819944784511, 202623112855200, 2285914871975105);
        vm.expectRevert(IncorrectDepositRatio.selector);
        SmartVaultDeposits.checkDepositRatio(deposit, exchangeRates, allocation, strategyRatios);

        deposit = Arrays.toArray(2799819944784511, 202623112855200, 32285914871975105);
        vm.expectRevert(IncorrectDepositRatio.selector);
        SmartVaultDeposits.checkDepositRatio(deposit, exchangeRates, allocation, strategyRatios);
    }

    function test_distributeDeposit_shouldDistributeIdealDeposit() public {
        uint256[] memory deposit = Arrays.toArray(2799819944784511, 202623112855200, 12285914871975105);

        uint256[][] memory distribution = SmartVaultDeposits.distributeDeposit(
            DepositQueryBag1({
                deposit: deposit,
                exchangeRates: exchangeRates,
                allocation: allocation,
                strategyRatios: strategyRatios
            })
        );

        assertEq(distribution[0][0], 1701934532251659);
        assertEq(distribution[0][1], 120837351789867);
        assertEq(distribution[0][2], 7318318488682135);

        assertEq(distribution[1][0], 826765143581546);
        assertEq(distribution[1][1], 61180620625034);
        assertEq(distribution[1][2], 3720443146116959);

        assertEq(distribution[2][0], 271120268951306);
        assertEq(distribution[2][1], 20605140440299);
        assertEq(distribution[2][2], 1247153237176011);
    }

    function test_distributeDeposit_shouldDistributeRealDeposit_1() public {
        uint256[] memory deposit = Arrays.toArray(1000 ether, 74 ether, 4300 ether);

        uint256[][] memory distribution = SmartVaultDeposits.distributeDeposit(
            DepositQueryBag1({
                deposit: deposit,
                exchangeRates: exchangeRates,
                allocation: allocation,
                strategyRatios: strategyRatios
            })
        );

        assertEq(distribution[0][0], 607_872851046015715415);
        assertEq(distribution[0][1], 44_131016972581648461);
        assertEq(distribution[0][2], 2561_369652097728273882);

        assertEq(distribution[1][0], 295_292254461448317392);
        assertEq(distribution[1][1], 22_343778369883672194);
        assertEq(distribution[1][2], 1302_133841476884060407);

        assertEq(distribution[2][0], 96_834894492535967193);
        assertEq(distribution[2][1], 7_525204657534679345);
        assertEq(distribution[2][2], 436_496506425387665711);
    }

    function test_distributeDeposit_shouldDistributeRealDeposit_2() public {
        uint256[] memory deposit = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        uint256[][] memory distribution = SmartVaultDeposits.distributeDeposit(
            DepositQueryBag1({
                deposit: deposit,
                exchangeRates: exchangeRates,
                allocation: allocation,
                strategyRatios: strategyRatios
            })
        );

        assertEq(distribution[0][0], 60_787285104601571542);
        assertEq(distribution[0][1], 4_315894186899640405);
        assertEq(distribution[0][2], 261_378837986158875949);

        assertEq(distribution[1][0], 29_529225446144831739);
        assertEq(distribution[1][1], 2_185161135984434265);
        assertEq(distribution[1][2], 132_878216195362029234);

        assertEq(distribution[2][0], 9_683489449253596719);
        assertEq(distribution[2][1], 735944677115925330);
        assertEq(distribution[2][2], 44_542945818479094817);
    }
}
