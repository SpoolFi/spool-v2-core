// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../src/access/SpoolAccessControl.sol";
import "../src/managers/DepositManager.sol";
import "./libraries/Arrays.sol";

contract DepositManagerTest is Test {
    DepositManager depositManager;

    SpoolAccessControl spoolAccessControl;
    address strategyRegistry;
    address usdPriceFeedManager;
    address guardManager;
    address actionManager;
    address masterWallet;
    address ghostStrategy;

    address alice;

    function setUp() public {
        alice = address(0xa);

        strategyRegistry = address(0x1);
        usdPriceFeedManager = address(0x2);
        guardManager = address(0x3);
        actionManager = address(0x4);
        masterWallet = address(0x5);
        ghostStrategy = address(0x6);

        spoolAccessControl = new SpoolAccessControl();
        spoolAccessControl.initialize();

        depositManager = new DepositManager(
            IStrategyRegistry(strategyRegistry),
            IUsdPriceFeedManager(usdPriceFeedManager),
            IGuardManager(guardManager),
            IActionManager(actionManager),
            spoolAccessControl,
            IMasterWallet(masterWallet),
            ghostStrategy
        );
    }

    function test_recoverPendingDeposits_shouldRevertWhenNotCalledBySmartVaultManager() public {
        address smartVault = address(0x11);
        uint256 flushIndex = 1;
        address[] memory strategies = Arrays.toArray(address(0x12));
        address[] memory tokens = Arrays.toArray(address(0x13));
        address emergencyWallet = address(0x14);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SMART_VAULT_MANAGER, alice));
        depositManager.recoverPendingDeposits(smartVault, flushIndex, strategies, tokens, emergencyWallet);
        vm.stopPrank();
    }
}
