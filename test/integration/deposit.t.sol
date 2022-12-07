// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../../src/managers/ActionManager.sol";
import "../../src/managers/AssetGroupRegistry.sol";
import "../../src/managers/GuardManager.sol";
import "../../src/managers/RiskManager.sol";
import "../../src/managers/SmartVaultManager.sol";
import "../../src/managers/StrategyRegistry.sol";
import "../../src/managers/UsdPriceFeedManager.sol";
import "../../src/MasterWallet.sol";
import "../../src/SmartVault.sol";
import "../../src/Swapper.sol";
import "../libraries/Arrays.sol";
import "../mocks/MockStrategy.sol";
import "../mocks/MockToken.sol";
import "../mocks/MockPriceFeedManager.sol";

contract DepositIntegrationTest is Test, SpoolAccessRoles {
    address private alice;

    MockToken tokenA;
    MockToken tokenB;
    MockToken tokenC;

    MockStrategy strategyA;
    MockStrategy strategyB;
    MockStrategy strategyC;
    address[] mySmartVaultStrategies;

    SmartVault private mySmartVault;
    SmartVaultManager private smartVaultManager;
    StrategyRegistry private strategyRegistry;
    MasterWallet private masterWallet;
    AssetGroupRegistry private assetGroupRegistry;
    ISpoolAccessControl accessControl;

    function setUp() public {
        alice = address(0xa);

        address riskProvider = address(0x1);

        tokenA = new MockToken("Token A", "TA");
        tokenB = new MockToken("Token B", "TB");
        tokenC = new MockToken("Token C", "TC");

        accessControl = new SpoolAccessControl();
        masterWallet = new MasterWallet(accessControl);

        address[] memory assetGroup = new address[](3);
        assetGroup[0] = address(tokenA);
        assetGroup[1] = address(tokenB);
        assetGroup[2] = address(tokenC);
        assetGroupRegistry = new AssetGroupRegistry();
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        MockPriceFeedManager priceFeedManager = new MockPriceFeedManager();
        strategyRegistry = new StrategyRegistry(masterWallet, accessControl, priceFeedManager);

        smartVaultManager = new SmartVaultManager(
            accessControl,
            strategyRegistry,
            priceFeedManager,
            assetGroupRegistry,
            masterWallet,
            new ActionManager(accessControl),
            new GuardManager(accessControl),
            new Swapper()
        );

        strategyA = new MockStrategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, new Swapper());
        uint256[] memory strategyRatios = new uint256[](3);
        strategyRatios[0] = 1000;
        strategyRatios[1] = 71;
        strategyRatios[2] = 4300;
        strategyA.initialize(assetGroupId, strategyRatios);
        strategyRegistry.registerStrategy(address(strategyA));

        strategyRatios[1] = 74;
        strategyRatios[2] = 4500;
        strategyB = new MockStrategy("StratB", strategyRegistry, assetGroupRegistry, accessControl, new Swapper());
        strategyB.initialize(assetGroupId, strategyRatios);
        strategyRegistry.registerStrategy(address(strategyB));

        strategyRatios[1] = 76;
        strategyRatios[2] = 4600;
        strategyC = new MockStrategy("StratC", strategyRegistry, assetGroupRegistry, accessControl, new Swapper());
        strategyC.initialize(assetGroupId, strategyRatios);
        strategyRegistry.registerStrategy(address(strategyC));

        mySmartVault = new SmartVault("MySmartVault", accessControl);
        mySmartVault.initialize();
        accessControl.grantRole(ROLE_SMART_VAULT, address(mySmartVault));

        mySmartVaultStrategies = new address[](3);
        mySmartVaultStrategies[0] = address(strategyA);
        mySmartVaultStrategies[1] = address(strategyB);
        mySmartVaultStrategies[2] = address(strategyC);

        uint256[] memory mySmartVaultStrategyAllocations = new uint256[](3);
        mySmartVaultStrategyAllocations[0] = 600;
        mySmartVaultStrategyAllocations[1] = 300;
        mySmartVaultStrategyAllocations[2] = 100;

        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
        accessControl.grantRole(ROLE_STRATEGY_CLAIMER, address(smartVaultManager));
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(strategyRegistry));

        SmartVaultRegistrationForm memory registrationForm = SmartVaultRegistrationForm({
            assetGroupId: assetGroupId,
            strategies: mySmartVaultStrategies,
            strategyAllocations: mySmartVaultStrategyAllocations,
            riskProvider: riskProvider
        });

        smartVaultManager.registerSmartVault(address(mySmartVault), registrationForm);

        priceFeedManager.setExchangeRate(address(tokenA), 1200 * 10 ** 26);
        priceFeedManager.setExchangeRate(address(tokenB), 16400 * 10 ** 26);
        priceFeedManager.setExchangeRate(address(tokenC), 270 * 10 ** 26);
    }

    function test_shouldBeAbleToDeposit() public {
        // set initial state
        deal(address(tokenA), alice, 100 ether, true);
        deal(address(tokenB), alice, 10 ether, true);
        deal(address(tokenC), alice, 500 ether, true);

        // Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        uint256 aliceDepositNftId = smartVaultManager.deposit(address(mySmartVault), depositAmounts, alice, address(0));

        vm.stopPrank();

        // check state
        // - tokens were transferred
        assertEq(tokenA.balanceOf(alice), 0 ether);
        assertEq(tokenB.balanceOf(alice), 2.763 ether);
        assertEq(tokenC.balanceOf(alice), 61.2 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 100 ether);
        assertEq(tokenB.balanceOf(address(masterWallet)), 7.237 ether);
        assertEq(tokenC.balanceOf(address(masterWallet)), 438.8 ether);
        // - deposit NFT was minted
        assertEq(aliceDepositNftId, 1);
        assertEq(mySmartVault.balanceOf(alice, aliceDepositNftId), 1);

        // flush
        smartVaultManager.flushSmartVault(address(mySmartVault));

        // DHW
        SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](3);
        dhwSwapInfo[0] = new SwapInfo[](0);
        dhwSwapInfo[1] = new SwapInfo[](0);
        dhwSwapInfo[2] = new SwapInfo[](0);

        strategyRegistry.doHardWork(mySmartVaultStrategies, dhwSwapInfo);

        // check state
        // - tokens were routed to the protocol
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 60_787285104601571542);
        assertEq(tokenB.balanceOf(address(strategyA.protocol())), 4_315894186899640405);
        assertEq(tokenC.balanceOf(address(strategyA.protocol())), 261_378837986158875949);
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 29_529225446144831739);
        assertEq(tokenB.balanceOf(address(strategyB.protocol())), 2_185161135984434265);
        assertEq(tokenC.balanceOf(address(strategyB.protocol())), 132_878216195362029234);
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 9_683489449253596719);
        assertEq(tokenB.balanceOf(address(strategyC.protocol())), 735944677115925330);
        assertEq(tokenC.balanceOf(address(strategyC.protocol())), 44_542945818479094817);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0);
        assertEq(tokenB.balanceOf(address(masterWallet)), 0);
        assertEq(tokenC.balanceOf(address(masterWallet)), 0);
        // - strategy tokens were minted
        assertEq(strategyA.totalSupply(), 21429769304693888499863000000000000000000000000000000000000000);
        assertEq(strategyB.totalSupply(), 10714883153826626792598000000000000000000000000000000000000000);
        assertEq(strategyC.totalSupply(), 3571627541479484707539000000000000000000000000000000000000000);

        // sync vault
        smartVaultManager.syncSmartVault(address(mySmartVault));

        // check state
        // - strategy tokens were claimed
        assertEq(
            strategyA.balanceOf(address(mySmartVault)), 21429769304693888499863000000000000000000000000000000000000000
        );
        assertEq(
            strategyB.balanceOf(address(mySmartVault)), 10714883153826626792598000000000000000000000000000000000000000
        );
        assertEq(
            strategyC.balanceOf(address(mySmartVault)), 3571627541479484707539000000000000000000000000000000000000000
        );
        assertEq(strategyA.balanceOf(address(strategyA)), 0);
        assertEq(strategyB.balanceOf(address(strategyB)), 0);
        assertEq(strategyB.balanceOf(address(strategyB)), 0);
        // - vault tokens were minted
        assertEq(mySmartVault.totalSupply(), 35716280000000000000000000000000000000000000000000000000000000);
        assertEq(
            mySmartVault.balanceOf(address(mySmartVault)),
            35716280000000000000000000000000000000000000000000000000000000
        );

        // claim deposit
        vm.prank(alice);
        smartVaultManager.claimSmartVaultTokens(address(mySmartVault), aliceDepositNftId);

        // check state
        // - vault tokens were claimed
        assertEq(mySmartVault.balanceOf(address(alice)), 35716280000000000000000000000000000000000000000000000000000000);
        assertEq(mySmartVault.balanceOf(address(mySmartVault)), 0);
        // - deposit NFT was burned
        assertEq(mySmartVault.balanceOf(alice, aliceDepositNftId), 0);
    }
}
