// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "./mocks/MockToken.sol";
import "./mocks/MockGuard.sol";
import "../src/access/SpoolAccessControl.sol";
import "../src/strategies/GhostStrategy.sol";
import "../src/Swapper.sol";
import "../src/managers/ActionManager.sol";
import "../src/managers/AssetGroupRegistry.sol";
import "../src/managers/GuardManager.sol";
import "../src/MasterWallet.sol";
import "./mocks/MockPriceFeedManager.sol";
import "../src/managers/StrategyRegistry.sol";
import "./libraries/TimeUtils.sol";

contract StrategyRegistryTest is Test {
    MockGuard internal guard;
    MockToken internal token;
    GuardManager internal guardManager;
    SpoolAccessControl internal accessControl;
    AssetGroupRegistry internal assetGroupRegistry;
    ActionManager internal actionManager;
    MockPriceFeedManager internal priceFeedManager;
    StrategyRegistry strategyRegistry;
    MasterWallet internal masterWallet;
    IStrategy internal ghostStrategy;
    Swapper internal swapper;

    address internal doHardWorker = address(0x222);
    address internal ecosystemFeeRecipient = address(0xfec);
    address internal treasuryFeeRecipient = address(0xfab);
    address internal emergencyWithdrawalRecipient = address(0xfee);

    function setUp() public {
        token = new MockToken("Token", "T");
        guard = new MockGuard();

        accessControl = new SpoolAccessControl();
        accessControl.initialize();

        ghostStrategy = new GhostStrategy();
        swapper = new Swapper(accessControl);
        actionManager = new ActionManager(accessControl);

        assetGroupRegistry = new AssetGroupRegistry(accessControl);
        assetGroupRegistry.initialize(Arrays.toArray(address(token)));

        guardManager = new GuardManager(accessControl);
        masterWallet = new MasterWallet(accessControl);
        priceFeedManager = new MockPriceFeedManager();

        strategyRegistry = new StrategyRegistry(
    masterWallet, accessControl, priceFeedManager, address(ghostStrategy)
    );
        strategyRegistry.initialize(0, 0, ecosystemFeeRecipient, treasuryFeeRecipient, emergencyWithdrawalRecipient);

        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY_REGISTRY, address(strategyRegistry));
        accessControl.grantRole(ROLE_DO_HARD_WORKER, doHardWorker);
        accessControl.grantRole(ADMIN_ROLE_STRATEGY, address(strategyRegistry));
    }

    function test_dhw_whenValidUntilExpired_shouldRevertBeforeProcessing() public {
        uint256 timestampInPast = TimeUtils.getTimestampInPast(1);
        DoHardWorkParameterBag memory params = _generateEmptyParameterBag(timestampInPast);
        vm.startPrank(doHardWorker);
        vm.expectRevert("DoHardWork expiration time reached");
        console.log("before doHardWork");
        strategyRegistry.doHardWork(params);
        vm.stopPrank;
    }

    function _generateEmptyParameterBag(uint256 validUntil) internal pure returns (DoHardWorkParameterBag memory) {
        return DoHardWorkParameterBag({
            strategies: new address[][](0),
            swapInfo: new SwapInfo[][][](0),
            compoundSwapInfo: new SwapInfo[][][](0),
            strategySlippages: new uint256[][][](0),
            baseYields: new int256[][](0),
            tokens: new address[](0),
            exchangeRateSlippages: new uint256[2][](0),
            validUntil: validUntil
        });
    }
}
