// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Test, console} from "forge-std/Test.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

import {
    MetamorphoStrategy,
    IAssetGroupRegistry,
    ISpoolAccessControl,
    ISwapper
} from "../../../src/strategies/MetamorphoStrategy.sol";
import {MetamorphoStrategyV2} from "../../../src/strategies/MetamorphoStrategyV2.sol";
import {ROLE_EMERGENCY_WITHDRAWAL_EXECUTOR} from "../../../src/access/Roles.sol";

contract E2eMainnetMetamorphoV2Test is Test {
    address constant owner = 0x4e736b96920a0f305022CBaAea493Ce7e49Eee6C;
    address constant emergencyWithdrawer = address(0x02);
    address constant metamorphoStrategy = 0x1D060A1B17a7FF1929133B202a7Ec1D9B90A1965;
    address spoolAccessControl = 0x7b533e72E0cDC63AacD8cDB926AC402b846Fbd13;
    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address constant LEGACY_MORPHO_TOKEN = 0x9994E35Db50125E0DF82e4c2dde62496CE330999;
    address constant MORPHO_WRAPPER = 0x9D03bb2092270648d7480049d0E58d2FcF0E5123;
    address constant NEW_MORPHO_TOKEN = 0x58D97B57BB95320F9a05dC918Aef65434969c2B2;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21273360);
        vm.store(metamorphoStrategy, _ADMIN_SLOT, bytes32(uint256(uint160(owner))));
        vm.startPrank(owner);
        ISpoolAccessControl(spoolAccessControl).grantRole(ROLE_EMERGENCY_WITHDRAWAL_EXECUTOR, emergencyWithdrawer);
        vm.stopPrank();
    }

    function test_upgrade_plus_exchangeLegacyMorpho() external {
        vm.startPrank(owner);
        address metamorphoStrategyV2Impl = address(
            new MetamorphoStrategyV2(
                IAssetGroupRegistry(address(0x02)),
                ISpoolAccessControl(0x7b533e72E0cDC63AacD8cDB926AC402b846Fbd13),
                ISwapper(address(0x04))
            )
        );

        TransparentUpgradeableProxy(payable(metamorphoStrategy)).upgradeTo(metamorphoStrategyV2Impl);

        uint256 legacyMorphoBalance = IERC20(LEGACY_MORPHO_TOKEN).balanceOf(metamorphoStrategy);
        assertGt(legacyMorphoBalance, 0);
        assertEq(IERC20(LEGACY_MORPHO_TOKEN).balanceOf(owner), 0);
        assertEq(IERC20(NEW_MORPHO_TOKEN).balanceOf(owner), 0);

        vm.stopPrank();

        vm.startPrank(address(0x1234));
        vm.expectRevert();
        MetamorphoStrategyV2(metamorphoStrategy).exchangeLegacyMorpho(owner);
        vm.stopPrank();

        vm.startPrank(emergencyWithdrawer);
        MetamorphoStrategyV2(metamorphoStrategy).exchangeLegacyMorpho(owner);
        vm.stopPrank();

        assertEq(IERC20(LEGACY_MORPHO_TOKEN).balanceOf(metamorphoStrategy), 0);
        assertEq(IERC20(LEGACY_MORPHO_TOKEN).balanceOf(owner), 0);
        assertEq(IERC20(NEW_MORPHO_TOKEN).balanceOf(owner), legacyMorphoBalance);
    }
}
