// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/managers/ActionManager.sol";
import "../../src/managers/AssetGroupRegistry.sol";
import "../../src/managers/DepositManager.sol";
import "../../src/managers/GuardManager.sol";
import "../../src/managers/RewardManager.sol";
import "../../src/managers/RiskManager.sol";
import "../../src/managers/SmartVaultManager.sol";
import "../../src/managers/StrategyRegistry.sol";
import "../../src/managers/UsdPriceFeedManager.sol";
import "../../src/managers/WithdrawalManager.sol";
import "../../src/MasterWallet.sol";
import "../../src/SmartVault.sol";
import "../../src/SmartVaultFactory.sol";
import "../../src/Swapper.sol";
import "../libraries/Arrays.sol";
import "../libraries/Constants.sol";
import "../mocks/MockStrategy.sol";
import "../mocks/MockToken.sol";
import "../mocks/MockPriceFeedManager.sol";

contract ReallocationIntegrationTest is Test {
    address private alice;

    address riskProvider;

    MockToken tokenA;
    MockToken tokenB;
    MockToken tokenC;

    SmartVaultManager private smartVaultManager;
    StrategyRegistry private strategyRegistry;
    MasterWallet private masterWallet;
    AssetGroupRegistry private assetGroupRegistry;
    SpoolAccessControl private accessControl;
    IRiskManager private riskManager;
    MockPriceFeedManager private priceFeedManager;
    Swapper private swapper;
    SmartVaultFactory private smartVaultFactory;

    function setUp() public {
        alice = address(0xa);

        tokenA = new MockToken("Token A", "TA");
        tokenB = new MockToken("Token B", "TB");
        tokenC = new MockToken("Token C", "TC");

        accessControl = new SpoolAccessControl();
        accessControl.initialize();

        riskProvider = address(0x1);
        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);

        masterWallet = new MasterWallet(accessControl);

        assetGroupRegistry = new AssetGroupRegistry(accessControl);
        assetGroupRegistry.initialize(Arrays.toArray(address(tokenA), address(tokenB), address(tokenC)));

        priceFeedManager = new MockPriceFeedManager();

        strategyRegistry = new StrategyRegistry(masterWallet, accessControl, priceFeedManager);
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(strategyRegistry));

        IActionManager actionManager = new ActionManager(accessControl);
        IGuardManager guardManager = new GuardManager(accessControl);

        riskManager = new RiskManager(accessControl);

        swapper = new Swapper();

        DepositManager depositManager =
            new DepositManager(strategyRegistry, priceFeedManager, guardManager, actionManager, accessControl);
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(depositManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(depositManager));

        WithdrawalManager withdrawalManager =
        new WithdrawalManager(strategyRegistry, priceFeedManager, masterWallet, guardManager, actionManager, accessControl);
        accessControl.grantRole(ROLE_STRATEGY_CLAIMER, address(withdrawalManager));
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(withdrawalManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(withdrawalManager));

        address managerAddress = computeCreateAddress(address(this), 1);
        RewardManager rewardManager =
            new RewardManager(accessControl, assetGroupRegistry, ISmartVaultBalance(managerAddress));

        smartVaultManager = new SmartVaultManager(
            accessControl,
            assetGroupRegistry,
            riskManager,
            depositManager,
            withdrawalManager,
            strategyRegistry,
            masterWallet,
            rewardManager,
            priceFeedManager
        );
        accessControl.grantRole(ROLE_STRATEGY_CLAIMER, address(smartVaultManager));
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(smartVaultManager));

        address smartVaultImplementation = address(new SmartVault(accessControl, guardManager));
        smartVaultFactory = new SmartVaultFactory(
            smartVaultImplementation,
            accessControl,
            actionManager,
            guardManager,
            smartVaultManager,
            assetGroupRegistry
        );
        accessControl.grantRole(ROLE_SMART_VAULT_INTEGRATOR, address(smartVaultFactory));

        deal(address(tokenA), alice, 1000 ether, true);
        deal(address(tokenB), alice, 1000 ether, true);
        deal(address(tokenC), alice, 1000 ether, true);
    }

    function test_reallocate_01() public {
        // setup:
        // - tokens: A
        // - smart vaults: A
        //   - strategies: A, B
        // reallocation
        // - smart vault A
        //   - strategy A: withdraw 10
        //   - strategy B: deposit 10
        // [[ 0, 10]
        //  [ 0,  0]]

        // setup asset group with TokenA
        uint256 assetGroupId;
        {
            assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(tokenA)));

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategy strategyA;
        MockStrategy strategyB;
        {
            strategyA = new MockStrategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyA.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyA));

            strategyB = new MockStrategy("StratB", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyB.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyB));
        }

        // setup smart vault
        ISmartVault smartVaultA;
        {
            SmartVaultSpecification memory specification = SmartVaultSpecification({
                smartVaultName: "SmartVaultA",
                assetGroupId: assetGroupId,
                actions: new IAction[](0),
                actionRequestTypes: new RequestType[](0),
                guards: new GuardDefinition[][](0),
                guardRequestTypes: new RequestType[](0),
                strategies: Arrays.toArray(address(strategyA), address(strategyB)),
                riskAppetite: 4,
                riskProvider: riskProvider,
                managementFeePct: 0
            });
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(60_00, 40_00))
            );
            smartVaultA = smartVaultFactory.deploySmartVault(specification);
        }

        // setup initial state
        {
            // Alice deposits 100 TokenA into SmartVaultA
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            uint256 depositNft = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(100 ether),
                    receiver: alice,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));

            SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](2);
            dhwSwapInfo[0] = new SwapInfo[](0);
            dhwSwapInfo[1] = new SwapInfo[](0);
            strategyRegistry.doHardWork(Arrays.toArray(address(strategyA), address(strategyB)), dhwSwapInfo);

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim SVTs
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNft), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        console.log("token A", address(tokenA));
        console.log("smart vault A", address(smartVaultA));
        console.log("strategy A", address(strategyA));
        console.log("strategy B", address(strategyB));

        // check initial state
        // - assets were routed to strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 60 ether);
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 40 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether);
        // - strategy tokens were minted
        assertEq(strategyA.totalSupply(), 60_000000000000000000000);
        assertEq(strategyB.totalSupply(), 40_000000000000000000000);
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 60_000000000000000000000);
        assertEq(strategyB.balanceOf(address(smartVaultA)), 40_000000000000000000000);
        // - smart vault tokens were minted
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000);
        // - smart vault tokens were distributed
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000);

        // mock changes in allocation
        vm.mockCall(
            address(riskManager),
            abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
            abi.encode(Arrays.toArray(50_00, 50_00))
        );

        // reallocate
        smartVaultManager.reallocate(Arrays.toArray(address(smartVaultA)));

        // check final state
        // - assets were redistributed between strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 50 ether, "final tokenA balance strategyA");
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 50 ether, "final tokenA balance strategyB");
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "final tokenA balance masterWallet");
        // - strategy tokens were minted and burned
        assertEq(strategyA.totalSupply(), 50_000000000000000000000, "final SSTA supply");
        assertEq(strategyB.totalSupply(), 50_000000000000000000000, "final SSTB supply");
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 50_000000000000000000000, "final SSTA balance smartVaultA");
        assertEq(strategyB.balanceOf(address(smartVaultA)), 50_000000000000000000000, "final SSTB balance smartVaultA");
        // - smart vault tokens remain unchanged
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000, "final SVTA supply");
        // - smart vault tokens distribution remains unchanged
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000, "final SVTA balance alice");
    }

    function test_reallocate_02() public {
        // setup:
        // - tokens: A
        // - smart vaults: A
        //   - strategies: A, B, C
        // reallocation
        // - smart vault A
        //   - strategy A: withdraw 10
        //   - strategy B: withdraw 5
        //   - strategy C: deposit 15
        // [[ 0,  0, 10]
        //  [ 0,  0,  5]
        //  [ 0,  0,  0]]

        // setup asset group with TokenA
        uint256 assetGroupId;
        {
            assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(tokenA)));

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategy strategyA;
        MockStrategy strategyB;
        MockStrategy strategyC;
        {
            strategyA = new MockStrategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyA.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyA));

            strategyB = new MockStrategy("StratB", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyB.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyB));

            strategyC = new MockStrategy("StratC", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyC.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyC));
        }

        // setup smart vault
        ISmartVault smartVaultA;
        {
            SmartVaultSpecification memory specification = SmartVaultSpecification({
                smartVaultName: "SmartVaultA",
                assetGroupId: assetGroupId,
                actions: new IAction[](0),
                actionRequestTypes: new RequestType[](0),
                guards: new GuardDefinition[][](0),
                guardRequestTypes: new RequestType[](0),
                strategies: Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)),
                riskAppetite: 4,
                riskProvider: riskProvider,
                managementFeePct: 0
            });
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(50_00, 35_00, 15_00))
            );
            smartVaultA = smartVaultFactory.deploySmartVault(specification);
        }

        // setup initial state
        {
            // Alice deposits 100 TokenA into SmartVaultA
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            uint256 depositNft = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(100 ether),
                    receiver: alice,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));

            SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](3);
            dhwSwapInfo[0] = new SwapInfo[](0);
            dhwSwapInfo[1] = new SwapInfo[](0);
            dhwSwapInfo[2] = new SwapInfo[](0);
            strategyRegistry.doHardWork(Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)), dhwSwapInfo);

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim SVTs
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNft), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        console.log("token A", address(tokenA));
        console.log("smart vault A", address(smartVaultA));
        console.log("strategy A", address(strategyA));
        console.log("strategy B", address(strategyB));
        console.log("strategy C", address(strategyC));

        // check initial state
        // - assets were routed to strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 50 ether);
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 35 ether);
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 15 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether);
        // - strategy tokens were minted
        assertEq(strategyA.totalSupply(), 50_000000000000000000000);
        assertEq(strategyB.totalSupply(), 35_000000000000000000000);
        assertEq(strategyC.totalSupply(), 15_000000000000000000000);
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 50_000000000000000000000);
        assertEq(strategyB.balanceOf(address(smartVaultA)), 35_000000000000000000000);
        assertEq(strategyC.balanceOf(address(smartVaultA)), 15_000000000000000000000);
        // - smart vault tokens were minted
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000);
        // - smart vault tokens were distributed
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000);

        // mock changes in allocation
        vm.mockCall(
            address(riskManager),
            abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
            abi.encode(Arrays.toArray(40_00, 30_00, 30_00))
        );

        // reallocate
        smartVaultManager.reallocate(Arrays.toArray(address(smartVaultA)));

        // check final state
        // - assets were redistributed between strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 40 ether, "final tokenA balance strategyA");
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 30 ether, "final tokenA balance strategyB");
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 30 ether, "final tokenA balance strategyC");
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "final tokenA balance masterWallet");
        // - strategy tokens were minted and burned
        assertEq(strategyA.totalSupply(), 40_000000000000000000000, "final SSTA supply");
        assertEq(strategyB.totalSupply(), 30_000000000000000000000, "final SSTB supply");
        assertEq(strategyC.totalSupply(), 30_000000000000000000000, "final SSTC supply");
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 40_000000000000000000000, "final SSTA balance smartVaultA");
        assertEq(strategyB.balanceOf(address(smartVaultA)), 30_000000000000000000000, "final SSTB balance smartVaultA");
        assertEq(strategyC.balanceOf(address(smartVaultA)), 30_000000000000000000000, "final SSTC balance smartVaultA");
        // - smart vault tokens remain unchanged
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000, "final SVTA supply");
        // - smart vault tokens distribution remains unchanged
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000, "final SVTA balance alice");
    }

    function test_reallocate_03() public {
        // setup:
        // - tokens: A
        // - smart vaults: A
        //   - strategies: A, B, C
        // reallocation
        // - smart vault A
        //   - strategy A: withdraw 15
        //   - strategy B: deposit 5
        //   - strategy C: deposit 10
        // [[ 0,  5, 10]
        //  [ 0,  0,  0]
        //  [ 0,  0,  0]]

        // setup asset group with TokenA
        uint256 assetGroupId;
        {
            assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(tokenA)));

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategy strategyA;
        MockStrategy strategyB;
        MockStrategy strategyC;
        {
            strategyA = new MockStrategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyA.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyA));

            strategyB = new MockStrategy("StratB", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyB.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyB));

            strategyC = new MockStrategy("StratC", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyC.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyC));
        }

        // setup smart vault
        ISmartVault smartVaultA;
        {
            SmartVaultSpecification memory specification = SmartVaultSpecification({
                smartVaultName: "SmartVaultA",
                assetGroupId: assetGroupId,
                actions: new IAction[](0),
                actionRequestTypes: new RequestType[](0),
                guards: new GuardDefinition[][](0),
                guardRequestTypes: new RequestType[](0),
                strategies: Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)),
                riskAppetite: 4,
                riskProvider: riskProvider,
                managementFeePct: 0
            });
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(55_00, 25_00, 20_00))
            );
            smartVaultA = smartVaultFactory.deploySmartVault(specification);
        }

        // setup initial state
        {
            // Alice deposits 100 TokenA into SmartVaultA
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            uint256 depositNft = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(100 ether),
                    receiver: alice,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));

            SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](3);
            dhwSwapInfo[0] = new SwapInfo[](0);
            dhwSwapInfo[1] = new SwapInfo[](0);
            dhwSwapInfo[2] = new SwapInfo[](0);
            strategyRegistry.doHardWork(Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)), dhwSwapInfo);

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim SVTs
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNft), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        console.log("token A", address(tokenA));
        console.log("smart vault A", address(smartVaultA));
        console.log("strategy A", address(strategyA));
        console.log("strategy B", address(strategyB));
        console.log("strategy C", address(strategyC));

        // check initial state
        // - assets were routed to strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 55 ether);
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 25 ether);
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 20 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether);
        // - strategy tokens were minted
        assertEq(strategyA.totalSupply(), 55_000000000000000000000);
        assertEq(strategyB.totalSupply(), 25_000000000000000000000);
        assertEq(strategyC.totalSupply(), 20_000000000000000000000);
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 55_000000000000000000000);
        assertEq(strategyB.balanceOf(address(smartVaultA)), 25_000000000000000000000);
        assertEq(strategyC.balanceOf(address(smartVaultA)), 20_000000000000000000000);
        // - smart vault tokens were minted
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000);
        // - smart vault tokens were distributed
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000);

        // mock changes in allocation
        vm.mockCall(
            address(riskManager),
            abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
            abi.encode(Arrays.toArray(40_00, 30_00, 30_00))
        );

        // reallocate
        smartVaultManager.reallocate(Arrays.toArray(address(smartVaultA)));

        // check final state
        // - assets were redistributed between strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 40 ether, "final tokenA balance strategyA");
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 30 ether, "final tokenA balance strategyB");
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 30 ether, "final tokenA balance strategyC");
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "final tokenA balance masterWallet");
        // - strategy tokens were minted and burned
        assertEq(strategyA.totalSupply(), 40_000000000000000000000, "final SSTA supply");
        assertEq(strategyB.totalSupply(), 30_000000000000000000000, "final SSTB supply");
        assertEq(strategyC.totalSupply(), 30_000000000000000000000, "final SSTC supply");
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 40_000000000000000000000, "final SSTA balance smartVaultA");
        assertEq(strategyB.balanceOf(address(smartVaultA)), 30_000000000000000000000, "final SSTB balance smartVaultA");
        assertEq(strategyC.balanceOf(address(smartVaultA)), 30_000000000000000000000, "final SSTC balance smartVaultA");
        // - smart vault tokens remain unchanged
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000, "final SVTA supply");
        // - smart vault tokens distribution remains unchanged
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000, "final SVTA balance alice");
    }

    function test_reallocate_04() public {
        // setup:
        // - tokens: A
        // - smart vaults: A
        //   - strategies: A, B, C
        // reallocation
        // - smart vault A
        //   - strategy A: withdraw 10
        //   - strategy B: /
        //   - strategy C: deposit 10
        // [[ 0,  0, 10]
        //  [ 0,  0,  0]
        //  [ 0,  0,  0]]

        // setup asset group with TokenA
        uint256 assetGroupId;
        {
            assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(tokenA)));

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategy strategyA;
        MockStrategy strategyB;
        MockStrategy strategyC;
        {
            strategyA = new MockStrategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyA.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyA));

            strategyB = new MockStrategy("StratB", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyB.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyB));

            strategyC = new MockStrategy("StratC", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyC.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyC));
        }

        // setup smart vault
        ISmartVault smartVaultA;
        {
            SmartVaultSpecification memory specification = SmartVaultSpecification({
                smartVaultName: "SmartVaultA",
                assetGroupId: assetGroupId,
                actions: new IAction[](0),
                actionRequestTypes: new RequestType[](0),
                guards: new GuardDefinition[][](0),
                guardRequestTypes: new RequestType[](0),
                strategies: Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)),
                riskAppetite: 4,
                riskProvider: riskProvider,
                managementFeePct: 0
            });
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(50_00, 30_00, 20_00))
            );
            smartVaultA = smartVaultFactory.deploySmartVault(specification);
        }

        // setup initial state
        {
            // Alice deposits 100 TokenA into SmartVaultA
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            uint256 depositNft = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(100 ether),
                    receiver: alice,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));

            SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](3);
            dhwSwapInfo[0] = new SwapInfo[](0);
            dhwSwapInfo[1] = new SwapInfo[](0);
            dhwSwapInfo[2] = new SwapInfo[](0);
            strategyRegistry.doHardWork(Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)), dhwSwapInfo);

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim SVTs
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNft), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        console.log("token A", address(tokenA));
        console.log("smart vault A", address(smartVaultA));
        console.log("strategy A", address(strategyA));
        console.log("strategy B", address(strategyB));
        console.log("strategy C", address(strategyC));

        // check initial state
        // - assets were routed to strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 50 ether);
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 30 ether);
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 20 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether);
        // - strategy tokens were minted
        assertEq(strategyA.totalSupply(), 50_000000000000000000000);
        assertEq(strategyB.totalSupply(), 30_000000000000000000000);
        assertEq(strategyC.totalSupply(), 20_000000000000000000000);
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 50_000000000000000000000);
        assertEq(strategyB.balanceOf(address(smartVaultA)), 30_000000000000000000000);
        assertEq(strategyC.balanceOf(address(smartVaultA)), 20_000000000000000000000);
        // - smart vault tokens were minted
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000);
        // - smart vault tokens were distributed
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000);

        // mock changes in allocation
        vm.mockCall(
            address(riskManager),
            abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
            abi.encode(Arrays.toArray(40_00, 30_00, 30_00))
        );

        // reallocate
        smartVaultManager.reallocate(Arrays.toArray(address(smartVaultA)));

        // check final state
        // - assets were redistributed between strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 40 ether, "final tokenA balance strategyA");
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 30 ether, "final tokenA balance strategyB");
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 30 ether, "final tokenA balance strategyC");
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "final tokenA balance masterWallet");
        // - strategy tokens were minted and burned
        assertEq(strategyA.totalSupply(), 40_000000000000000000000, "final SSTA supply");
        assertEq(strategyB.totalSupply(), 30_000000000000000000000, "final SSTB supply");
        assertEq(strategyC.totalSupply(), 30_000000000000000000000, "final SSTC supply");
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 40_000000000000000000000, "final SSTA balance smartVaultA");
        assertEq(strategyB.balanceOf(address(smartVaultA)), 30_000000000000000000000, "final SSTB balance smartVaultA");
        assertEq(strategyC.balanceOf(address(smartVaultA)), 30_000000000000000000000, "final SSTC balance smartVaultA");
        // - smart vault tokens remain unchanged
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000, "final SVTA supply");
        // - smart vault tokens distribution remains unchanged
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000, "final SVTA balance alice");
    }

    function test_reallocate_05() public {
        // setup:
        // - tokens: A
        // - smart vaults: A, B
        //   - A strategies: A, B
        //   - B strategies: B, C
        // reallocation
        // - smart vault A
        //   - strategy A: withdraw 10
        //   - strategy B: deposit 10
        // - smart vault B
        //   - strategy B: withdraw 15
        //   - strategy C: deposit 15
        // [[ 0, 10,  0]
        //  [ 0,  0, 15]
        //  [ 0,  0,  0]]

        // setup asset group with TokenA
        uint256 assetGroupId;
        {
            assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(tokenA)));

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategy strategyA;
        MockStrategy strategyB;
        MockStrategy strategyC;
        {
            strategyA = new MockStrategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyA.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyA));

            strategyB = new MockStrategy("StratB", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyB.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyB));

            strategyC = new MockStrategy("StratC", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyC.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyC));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory specification = SmartVaultSpecification({
                smartVaultName: "SmartVaultA",
                assetGroupId: assetGroupId,
                actions: new IAction[](0),
                actionRequestTypes: new RequestType[](0),
                guards: new GuardDefinition[][](0),
                guardRequestTypes: new RequestType[](0),
                strategies: Arrays.toArray(address(strategyA), address(strategyB)),
                riskAppetite: 4,
                riskProvider: riskProvider,
                managementFeePct: 0
            });
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(60_00, 40_00))
            );
            smartVaultA = smartVaultFactory.deploySmartVault(specification);

            specification.smartVaultName = "SmartVaultB";
            specification.strategies = Arrays.toArray(address(strategyB), address(strategyC));
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(65_00, 35_00))
            );
            smartVaultB = smartVaultFactory.deploySmartVault(specification);
        }

        // setup initial state
        {
            // Alice deposits 100 TokenA into SmartVaultA and SmartVaultB
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 200 ether);
            DepositBag memory bag = DepositBag({
                smartVault: address(smartVaultA),
                assets: Arrays.toArray(100 ether),
                receiver: alice,
                referral: address(0),
                doFlush: false
            });
            uint256 depositNftA = smartVaultManager.deposit(bag);

            bag.smartVault = address(smartVaultB);
            uint256 depositNftB = smartVaultManager.deposit(bag);
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](3);
            dhwSwapInfo[0] = new SwapInfo[](0);
            dhwSwapInfo[1] = new SwapInfo[](0);
            dhwSwapInfo[2] = new SwapInfo[](0);
            strategyRegistry.doHardWork(Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)), dhwSwapInfo);

            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim SVTs
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftA), Arrays.toArray(NFT_MINTED_SHARES)
            );
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftB), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        console.log("token A", address(tokenA));
        console.log("smart vault A", address(smartVaultA));
        console.log("smart vault B", address(smartVaultB));
        console.log("strategy A", address(strategyA));
        console.log("strategy B", address(strategyB));
        console.log("strategy C", address(strategyC));

        // check initial state
        // - assets were routed to strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 60 ether);
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 105 ether);
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 35 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether);
        // - strategy tokens were minted
        assertEq(strategyA.totalSupply(), 60_000000000000000000000);
        assertEq(strategyB.totalSupply(), 105_000000000000000000000);
        assertEq(strategyC.totalSupply(), 35_000000000000000000000);
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 60_000000000000000000000);
        assertEq(strategyB.balanceOf(address(smartVaultA)), 40_000000000000000000000);
        assertEq(strategyB.balanceOf(address(smartVaultB)), 65_000000000000000000000);
        assertEq(strategyC.balanceOf(address(smartVaultB)), 35_000000000000000000000);
        // - smart vault tokens were minted
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000);
        assertEq(smartVaultB.totalSupply(), 100_000000000000000000000);
        // - smart vault tokens were distributed
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000);
        assertEq(smartVaultB.balanceOf(alice), 100_000000000000000000000);

        // mock changes in allocation
        vm.mockCall(
            address(riskManager),
            abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
            abi.encode(Arrays.toArray(50_00, 50_00))
        );

        // reallocate
        smartVaultManager.reallocate(Arrays.toArray(address(smartVaultA), address(smartVaultB)));

        // check final state
        // - assets were redistributed between strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 50 ether, "final tokenA balance strategyA");
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 100 ether, "final tokenA balance strategyB");
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 50 ether, "final tokenA balance strategyC");
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "final tokenA balance masterWallet");
        // - strategy tokens were minted and burned
        assertEq(strategyA.totalSupply(), 50_000000000000000000000, "final SSTA supply");
        assertEq(strategyB.totalSupply(), 100_000000000000000000000, "final SSTB supply");
        assertEq(strategyC.totalSupply(), 50_000000000000000000000, "final SSTC supply");
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 50_000000000000000000000, "final SSTA balance smartVaultA");
        assertEq(strategyB.balanceOf(address(smartVaultA)), 50_000000000000000000000, "final SSTB balance smartVaultA");
        assertEq(strategyB.balanceOf(address(smartVaultB)), 50_000000000000000000000, "final SSTB balance smartVaultB");
        assertEq(strategyC.balanceOf(address(smartVaultB)), 50_000000000000000000000, "final SSTC balance smartVaultB");
        // - smart vault tokens remain unchanged
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000, "final SVTA supply");
        assertEq(smartVaultB.totalSupply(), 100_000000000000000000000, "final SVTB supply");
        // - smart vault tokens distribution remains unchanged
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000, "final SVTA balance alice");
        assertEq(smartVaultB.balanceOf(alice), 100_000000000000000000000, "final SVTB balance alice");
    }

    function test_reallocate_06() public {
        // setup:
        // - tokens: A
        // - smart vaults: A, B
        //   - A strategies: A, B
        //   - B strategies: B, C
        // reallocation
        // - smart vault A
        //   - strategy A: withdraw 15
        //   - strategy B: deposit 15
        // - smart vault B
        //   - strategy B: withdraw 10
        //   - strategy C: deposit 10
        // [[ 0, 15,  0]
        //  [ 0,  0, 10]
        //  [ 0,  0,  0]]

        // setup asset group with TokenA
        uint256 assetGroupId;
        {
            assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(tokenA)));

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategy strategyA;
        MockStrategy strategyB;
        MockStrategy strategyC;
        {
            strategyA = new MockStrategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyA.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyA));

            strategyB = new MockStrategy("StratB", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyB.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyB));

            strategyC = new MockStrategy("StratC", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyC.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyC));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory specification = SmartVaultSpecification({
                smartVaultName: "SmartVaultA",
                assetGroupId: assetGroupId,
                actions: new IAction[](0),
                actionRequestTypes: new RequestType[](0),
                guards: new GuardDefinition[][](0),
                guardRequestTypes: new RequestType[](0),
                strategies: Arrays.toArray(address(strategyA), address(strategyB)),
                riskAppetite: 4,
                riskProvider: riskProvider,
                managementFeePct: 0
            });
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(65_00, 35_00))
            );
            smartVaultA = smartVaultFactory.deploySmartVault(specification);

            specification.smartVaultName = "SmartVaultB";
            specification.strategies = Arrays.toArray(address(strategyB), address(strategyC));
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(60_00, 40_00))
            );
            smartVaultB = smartVaultFactory.deploySmartVault(specification);
        }

        // setup initial state
        {
            // Alice deposits 100 TokenA into SmartVaultA and SmartVaultB
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 200 ether);
            DepositBag memory bag = DepositBag({
                smartVault: address(smartVaultA),
                assets: Arrays.toArray(100 ether),
                receiver: alice,
                referral: address(0),
                doFlush: false
            });
            uint256 depositNftA = smartVaultManager.deposit(bag);

            bag.smartVault = address(smartVaultB);
            uint256 depositNftB = smartVaultManager.deposit(bag);
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](3);
            dhwSwapInfo[0] = new SwapInfo[](0);
            dhwSwapInfo[1] = new SwapInfo[](0);
            dhwSwapInfo[2] = new SwapInfo[](0);
            strategyRegistry.doHardWork(Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)), dhwSwapInfo);

            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim SVTs
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftA), Arrays.toArray(NFT_MINTED_SHARES)
            );
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftB), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        console.log("token A", address(tokenA));
        console.log("smart vault A", address(smartVaultA));
        console.log("smart vault B", address(smartVaultB));
        console.log("strategy A", address(strategyA));
        console.log("strategy B", address(strategyB));
        console.log("strategy C", address(strategyC));

        // check initial state
        // - assets were routed to strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 65 ether);
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 95 ether);
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 40 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether);
        // - strategy tokens were minted
        assertEq(strategyA.totalSupply(), 65_000000000000000000000);
        assertEq(strategyB.totalSupply(), 95_000000000000000000000);
        assertEq(strategyC.totalSupply(), 40_000000000000000000000);
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 65_000000000000000000000);
        assertEq(strategyB.balanceOf(address(smartVaultA)), 35_000000000000000000000);
        assertEq(strategyB.balanceOf(address(smartVaultB)), 60_000000000000000000000);
        assertEq(strategyC.balanceOf(address(smartVaultB)), 40_000000000000000000000);
        // - smart vault tokens were minted
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000);
        assertEq(smartVaultB.totalSupply(), 100_000000000000000000000);
        // - smart vault tokens were distributed
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000);
        assertEq(smartVaultB.balanceOf(alice), 100_000000000000000000000);

        // mock changes in allocation
        vm.mockCall(
            address(riskManager),
            abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
            abi.encode(Arrays.toArray(50_00, 50_00))
        );

        // reallocate
        smartVaultManager.reallocate(Arrays.toArray(address(smartVaultA), address(smartVaultB)));

        // check final state
        // - assets were redistributed between strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 50 ether, "final tokenA balance strategyA");
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 100 ether, "final tokenA balance strategyB");
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 50 ether, "final tokenA balance strategyC");
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "final tokenA balance masterWallet");
        // - strategy tokens were minted and burned
        assertEq(strategyA.totalSupply(), 50_000000000000000000000, "final SSTA supply");
        assertEq(strategyB.totalSupply(), 100_000000000000000000000, "final SSTB supply");
        assertEq(strategyC.totalSupply(), 50_000000000000000000000, "final SSTC supply");
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 50_000000000000000000000, "final SSTA balance smartVaultA");
        assertEq(strategyB.balanceOf(address(smartVaultA)), 50_000000000000000000000, "final SSTB balance smartVaultA");
        assertEq(strategyB.balanceOf(address(smartVaultB)), 50_000000000000000000000, "final SSTB balance smartVaultB");
        assertEq(strategyC.balanceOf(address(smartVaultB)), 50_000000000000000000000, "final SSTC balance smartVaultB");
        // - smart vault tokens remain unchanged
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000, "final SVTA supply");
        assertEq(smartVaultB.totalSupply(), 100_000000000000000000000, "final SVTB supply");
        // - smart vault tokens distribution remains unchanged
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000, "final SVTA balance alice");
        assertEq(smartVaultB.balanceOf(alice), 100_000000000000000000000, "final SVTB balance alice");
    }

    function test_reallocate_07() public {
        // setup:
        // - tokens: A
        // - smart vaults: A, B
        //   - A strategies: A, B
        //   - B strategies: B, C
        // reallocation
        // - smart vault A
        //   - strategy A: withdraw 10
        //   - strategy B: deposit 10
        // - smart vault B
        //   - strategy B: withdraw 10
        //   - strategy C: deposit 10
        // [[ 0, 10,  0]
        //  [ 0,  0, 10]
        //  [ 0,  0,  0]]

        // setup asset group with TokenA
        uint256 assetGroupId;
        {
            assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(tokenA)));

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategy strategyA;
        MockStrategy strategyB;
        MockStrategy strategyC;
        {
            strategyA = new MockStrategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyA.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyA));

            strategyB = new MockStrategy("StratB", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyB.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyB));

            strategyC = new MockStrategy("StratC", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyC.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyC));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory specification = SmartVaultSpecification({
                smartVaultName: "SmartVaultA",
                assetGroupId: assetGroupId,
                actions: new IAction[](0),
                actionRequestTypes: new RequestType[](0),
                guards: new GuardDefinition[][](0),
                guardRequestTypes: new RequestType[](0),
                strategies: Arrays.toArray(address(strategyA), address(strategyB)),
                riskAppetite: 4,
                riskProvider: riskProvider,
                managementFeePct: 0
            });
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(60_00, 40_00))
            );
            smartVaultA = smartVaultFactory.deploySmartVault(specification);

            specification.smartVaultName = "SmartVaultB";
            specification.strategies = Arrays.toArray(address(strategyB), address(strategyC));
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(60_00, 40_00))
            );
            smartVaultB = smartVaultFactory.deploySmartVault(specification);
        }

        // setup initial state
        {
            // Alice deposits 100 TokenA into SmartVaultA and SmartVaultB
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 200 ether);
            DepositBag memory bag = DepositBag({
                smartVault: address(smartVaultA),
                assets: Arrays.toArray(100 ether),
                receiver: alice,
                referral: address(0),
                doFlush: false
            });
            uint256 depositNftA = smartVaultManager.deposit(bag);

            bag.smartVault = address(smartVaultB);
            uint256 depositNftB = smartVaultManager.deposit(bag);
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](3);
            dhwSwapInfo[0] = new SwapInfo[](0);
            dhwSwapInfo[1] = new SwapInfo[](0);
            dhwSwapInfo[2] = new SwapInfo[](0);
            strategyRegistry.doHardWork(Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)), dhwSwapInfo);

            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim SVTs
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftA), Arrays.toArray(NFT_MINTED_SHARES)
            );
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftB), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        console.log("token A", address(tokenA));
        console.log("smart vault A", address(smartVaultA));
        console.log("smart vault B", address(smartVaultB));
        console.log("strategy A", address(strategyA));
        console.log("strategy B", address(strategyB));
        console.log("strategy C", address(strategyC));

        // check initial state
        // - assets were routed to strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 60 ether);
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 100 ether);
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 40 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether);
        // - strategy tokens were minted
        assertEq(strategyA.totalSupply(), 60_000000000000000000000);
        assertEq(strategyB.totalSupply(), 100_000000000000000000000);
        assertEq(strategyC.totalSupply(), 40_000000000000000000000);
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 60_000000000000000000000);
        assertEq(strategyB.balanceOf(address(smartVaultA)), 40_000000000000000000000);
        assertEq(strategyB.balanceOf(address(smartVaultB)), 60_000000000000000000000);
        assertEq(strategyC.balanceOf(address(smartVaultB)), 40_000000000000000000000);
        // - smart vault tokens were minted
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000);
        assertEq(smartVaultB.totalSupply(), 100_000000000000000000000);
        // - smart vault tokens were distributed
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000);
        assertEq(smartVaultB.balanceOf(alice), 100_000000000000000000000);

        // mock changes in allocation
        vm.mockCall(
            address(riskManager),
            abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
            abi.encode(Arrays.toArray(50_00, 50_00))
        );

        // reallocate
        smartVaultManager.reallocate(Arrays.toArray(address(smartVaultA), address(smartVaultB)));

        // check final state
        // - assets were redistributed between strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 50 ether, "final tokenA balance strategyA");
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 100 ether, "final tokenA balance strategyB");
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 50 ether, "final tokenA balance strategyC");
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "final tokenA balance masterWallet");
        // - strategy tokens were minted and burned
        assertEq(strategyA.totalSupply(), 50_000000000000000000000, "final SSTA supply");
        assertEq(strategyB.totalSupply(), 100_000000000000000000000, "final SSTB supply");
        assertEq(strategyC.totalSupply(), 50_000000000000000000000, "final SSTC supply");
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 50_000000000000000000000, "final SSTA balance smartVaultA");
        assertEq(strategyB.balanceOf(address(smartVaultA)), 50_000000000000000000000, "final SSTB balance smartVaultA");
        assertEq(strategyB.balanceOf(address(smartVaultB)), 50_000000000000000000000, "final SSTB balance smartVaultB");
        assertEq(strategyC.balanceOf(address(smartVaultB)), 50_000000000000000000000, "final SSTC balance smartVaultB");
        // - smart vault tokens remain unchanged
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000, "final SVTA supply");
        assertEq(smartVaultB.totalSupply(), 100_000000000000000000000, "final SVTB supply");
        // - smart vault tokens distribution remains unchanged
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000, "final SVTA balance alice");
        assertEq(smartVaultB.balanceOf(alice), 100_000000000000000000000, "final SVTB balance alice");
    }

    function test_reallocate_08() public {
        // setup:
        // - tokens: A
        // - smart vaults: A, B
        //   - A strategies: A, B, C
        //   - B strategies: A, B, C
        // reallocation
        // - smart vault A
        //   - strategy A: withdraw 20
        //   - strategy B: deposit 15
        //   - strategy C: deposit 5
        // - smart vault B
        //   - strategy A: withdraw 15
        //   - strategy B: deposit 10
        //   - strategy C: deposit 5
        // [[ 0, 25, 10]
        //  [ 0,  0,  0]
        //  [ 0,  0,  0]]

        // setup asset group with TokenA
        uint256 assetGroupId;
        {
            assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(tokenA)));

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategy strategyA;
        MockStrategy strategyB;
        MockStrategy strategyC;
        {
            strategyA = new MockStrategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyA.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyA));

            strategyB = new MockStrategy("StratB", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyB.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyB));

            strategyC = new MockStrategy("StratC", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyC.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyC));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory specification = SmartVaultSpecification({
                smartVaultName: "SmartVaultA",
                assetGroupId: assetGroupId,
                actions: new IAction[](0),
                actionRequestTypes: new RequestType[](0),
                guards: new GuardDefinition[][](0),
                guardRequestTypes: new RequestType[](0),
                strategies: Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)),
                riskAppetite: 4,
                riskProvider: riskProvider,
                managementFeePct: 0
            });
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(60_00, 15_00, 25_00))
            );
            smartVaultA = smartVaultFactory.deploySmartVault(specification);

            specification.smartVaultName = "SmartVaultB";
            specification.strategies = Arrays.toArray(address(strategyA), address(strategyB), address(strategyC));
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(55_00, 20_00, 25_00))
            );
            smartVaultB = smartVaultFactory.deploySmartVault(specification);
        }

        // setup initial state
        {
            // Alice deposits 100 TokenA into SmartVaultA and SmartVaultB
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 200 ether);
            DepositBag memory bag = DepositBag({
                smartVault: address(smartVaultA),
                assets: Arrays.toArray(100 ether),
                receiver: alice,
                referral: address(0),
                doFlush: false
            });
            uint256 depositNftA = smartVaultManager.deposit(bag);

            bag.smartVault = address(smartVaultB);
            uint256 depositNftB = smartVaultManager.deposit(bag);
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](3);
            dhwSwapInfo[0] = new SwapInfo[](0);
            dhwSwapInfo[1] = new SwapInfo[](0);
            dhwSwapInfo[2] = new SwapInfo[](0);
            strategyRegistry.doHardWork(Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)), dhwSwapInfo);

            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim SVTs
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftA), Arrays.toArray(NFT_MINTED_SHARES)
            );
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftB), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        console.log("token A", address(tokenA));
        console.log("smart vault A", address(smartVaultA));
        console.log("smart vault B", address(smartVaultB));
        console.log("strategy A", address(strategyA));
        console.log("strategy B", address(strategyB));
        console.log("strategy C", address(strategyC));

        // check initial state
        // - assets were routed to strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 115 ether);
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 35 ether);
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 50 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether);
        // - strategy tokens were minted
        assertEq(strategyA.totalSupply(), 115_000000000000000000000);
        assertEq(strategyB.totalSupply(), 35_000000000000000000000);
        assertEq(strategyC.totalSupply(), 50_000000000000000000000);
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 60_000000000000000000000);
        assertEq(strategyB.balanceOf(address(smartVaultA)), 15_000000000000000000000);
        assertEq(strategyC.balanceOf(address(smartVaultA)), 25_000000000000000000000);
        assertEq(strategyA.balanceOf(address(smartVaultB)), 55_000000000000000000000);
        assertEq(strategyB.balanceOf(address(smartVaultB)), 20_000000000000000000000);
        assertEq(strategyC.balanceOf(address(smartVaultB)), 25_000000000000000000000);
        // - smart vault tokens were minted
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000);
        assertEq(smartVaultB.totalSupply(), 100_000000000000000000000);
        // - smart vault tokens were distributed
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000);
        assertEq(smartVaultB.balanceOf(alice), 100_000000000000000000000);

        // mock changes in allocation
        vm.mockCall(
            address(riskManager),
            abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
            abi.encode(Arrays.toArray(40_00, 30_00, 30_00))
        );

        // reallocate
        smartVaultManager.reallocate(Arrays.toArray(address(smartVaultA), address(smartVaultB)));

        // check final state
        // - assets were redistributed between strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 80 ether, "final tokenA balance strategyA");
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 60 ether, "final tokenA balance strategyB");
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 60 ether, "final tokenA balance strategyC");
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "final tokenA balance masterWallet");
        // - strategy tokens were minted and burned
        assertEq(strategyA.totalSupply(), 80_000000000000000000000, "final SSTA supply");
        assertEq(strategyB.totalSupply(), 60_000000000000000000000, "final SSTB supply");
        assertEq(strategyC.totalSupply(), 60_000000000000000000000, "final SSTC supply");
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 40_000000000000000000000, "final SSTA balance smartVaultA");
        assertEq(strategyB.balanceOf(address(smartVaultA)), 30_000000000000000000000, "final SSTB balance smartVaultA");
        assertEq(strategyC.balanceOf(address(smartVaultA)), 30_000000000000000000000, "final SSTC balance smartVaultA");
        assertEq(strategyA.balanceOf(address(smartVaultB)), 40_000000000000000000000, "final SSTA balance smartVaultB");
        assertEq(strategyB.balanceOf(address(smartVaultB)), 30_000000000000000000000, "final SSTB balance smartVaultB");
        assertEq(strategyC.balanceOf(address(smartVaultB)), 30_000000000000000000000, "final SSTC balance smartVaultB");
        // - smart vault tokens remain unchanged
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000, "final SVTA supply");
        assertEq(smartVaultB.totalSupply(), 100_000000000000000000000, "final SVTB supply");
        // - smart vault tokens distribution remains unchanged
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000, "final SVTA balance alice");
        assertEq(smartVaultB.balanceOf(alice), 100_000000000000000000000, "final SVTB balance alice");
    }

    function test_reallocate_09() public {
        // setup:
        // - tokens: A
        // - smart vaults: A, B
        //   - A strategies: A, B, C
        //   - B strategies: A, B, C
        // reallocation
        // - smart vault A
        //   - strategy A: withdraw 20
        //   - strategy B: deposit 15
        //   - strategy C: deposit 5
        // - smart vault B
        //   - strategy A: deposit 20
        //   - strategy B: withdraw 15
        //   - strategy C: withdraw 5
        // [[ 0, 15,  5]
        //  [15,  0,  0]
        //  [ 5,  0,  0]]

        // setup asset group with TokenA
        uint256 assetGroupId;
        {
            assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(tokenA)));

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategy strategyA;
        MockStrategy strategyB;
        MockStrategy strategyC;
        {
            strategyA = new MockStrategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyA.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyA));

            strategyB = new MockStrategy("StratB", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyB.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyB));

            strategyC = new MockStrategy("StratC", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyC.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyC));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory specification = SmartVaultSpecification({
                smartVaultName: "SmartVaultA",
                assetGroupId: assetGroupId,
                actions: new IAction[](0),
                actionRequestTypes: new RequestType[](0),
                guards: new GuardDefinition[][](0),
                guardRequestTypes: new RequestType[](0),
                strategies: Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)),
                riskAppetite: 4,
                riskProvider: riskProvider,
                managementFeePct: 0
            });
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(60_00, 15_00, 25_00))
            );
            smartVaultA = smartVaultFactory.deploySmartVault(specification);

            specification.smartVaultName = "SmartVaultB";
            specification.strategies = Arrays.toArray(address(strategyA), address(strategyB), address(strategyC));
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(20_00, 45_00, 35_00))
            );
            smartVaultB = smartVaultFactory.deploySmartVault(specification);
        }

        // setup initial state
        {
            // Alice deposits 100 TokenA into SmartVaultA and SmartVaultB
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 200 ether);
            DepositBag memory bag = DepositBag({
                smartVault: address(smartVaultA),
                assets: Arrays.toArray(100 ether),
                receiver: alice,
                referral: address(0),
                doFlush: false
            });
            uint256 depositNftA = smartVaultManager.deposit(bag);

            bag.smartVault = address(smartVaultB);
            uint256 depositNftB = smartVaultManager.deposit(bag);
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](3);
            dhwSwapInfo[0] = new SwapInfo[](0);
            dhwSwapInfo[1] = new SwapInfo[](0);
            dhwSwapInfo[2] = new SwapInfo[](0);
            strategyRegistry.doHardWork(Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)), dhwSwapInfo);

            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim SVTs
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftA), Arrays.toArray(NFT_MINTED_SHARES)
            );
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftB), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        console.log("token A", address(tokenA));
        console.log("smart vault A", address(smartVaultA));
        console.log("smart vault B", address(smartVaultB));
        console.log("strategy A", address(strategyA));
        console.log("strategy B", address(strategyB));
        console.log("strategy C", address(strategyC));

        // check initial state
        // - assets were routed to strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 80 ether);
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 60 ether);
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 60 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether);
        // - strategy tokens were minted
        assertEq(strategyA.totalSupply(), 80_000000000000000000000);
        assertEq(strategyB.totalSupply(), 60_000000000000000000000);
        assertEq(strategyC.totalSupply(), 60_000000000000000000000);
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 60_000000000000000000000);
        assertEq(strategyB.balanceOf(address(smartVaultA)), 15_000000000000000000000);
        assertEq(strategyC.balanceOf(address(smartVaultA)), 25_000000000000000000000);
        assertEq(strategyA.balanceOf(address(smartVaultB)), 20_000000000000000000000);
        assertEq(strategyB.balanceOf(address(smartVaultB)), 45_000000000000000000000);
        assertEq(strategyC.balanceOf(address(smartVaultB)), 35_000000000000000000000);
        // - smart vault tokens were minted
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000);
        assertEq(smartVaultB.totalSupply(), 100_000000000000000000000);
        // - smart vault tokens were distributed
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000);
        assertEq(smartVaultB.balanceOf(alice), 100_000000000000000000000);

        // mock changes in allocation
        vm.mockCall(
            address(riskManager),
            abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
            abi.encode(Arrays.toArray(40_00, 30_00, 30_00))
        );

        // reallocate
        smartVaultManager.reallocate(Arrays.toArray(address(smartVaultA), address(smartVaultB)));

        // check final state
        // - assets were redistributed between strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 80 ether, "final tokenA balance strategyA");
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 60 ether, "final tokenA balance strategyB");
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 60 ether, "final tokenA balance strategyC");
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "final tokenA balance masterWallet");
        // - strategy tokens were minted and burned
        assertEq(strategyA.totalSupply(), 80_000000000000000000000, "final SSTA supply");
        assertEq(strategyB.totalSupply(), 60_000000000000000000000, "final SSTB supply");
        assertEq(strategyC.totalSupply(), 60_000000000000000000000, "final SSTC supply");
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 40_000000000000000000000, "final SSTA balance smartVaultA");
        assertEq(strategyB.balanceOf(address(smartVaultA)), 30_000000000000000000000, "final SSTB balance smartVaultA");
        assertEq(strategyC.balanceOf(address(smartVaultA)), 30_000000000000000000000, "final SSTC balance smartVaultA");
        assertEq(strategyA.balanceOf(address(smartVaultB)), 40_000000000000000000000, "final SSTA balance smartVaultB");
        assertEq(strategyB.balanceOf(address(smartVaultB)), 30_000000000000000000000, "final SSTB balance smartVaultB");
        assertEq(strategyC.balanceOf(address(smartVaultB)), 30_000000000000000000000, "final SSTC balance smartVaultB");
        // - smart vault tokens remain unchanged
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000, "final SVTA supply");
        assertEq(smartVaultB.totalSupply(), 100_000000000000000000000, "final SVTB supply");
        // - smart vault tokens distribution remains unchanged
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000, "final SVTA balance alice");
        assertEq(smartVaultB.balanceOf(alice), 100_000000000000000000000, "final SVTB balance alice");
    }

    function test_reallocate_10() public {
        // setup:
        // - tokens: A
        // - smart vaults: A, B
        //   - A strategies: A, B, C
        //   - B strategies: A, B, C
        // reallocation
        // - smart vault A
        //   - strategy A: withdraw 20
        //   - strategy B: deposit 15
        //   - strategy C: deposit 5
        // - smart vault B
        //   - strategy A: deposit 15
        //   - strategy B: withdraw 5
        //   - strategy C: withdraw 10
        // [[ 0, 15,  5]
        //  [ 5,  0,  0]
        //  [10,  0,  0]]

        // setup asset group with TokenA
        uint256 assetGroupId;
        {
            assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(tokenA)));

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategy strategyA;
        MockStrategy strategyB;
        MockStrategy strategyC;
        {
            strategyA = new MockStrategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyA.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyA));

            strategyB = new MockStrategy("StratB", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyB.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyB));

            strategyC = new MockStrategy("StratC", strategyRegistry, assetGroupRegistry, accessControl, swapper);
            strategyC.initialize(assetGroupId, Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyC));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory specification = SmartVaultSpecification({
                smartVaultName: "SmartVaultA",
                assetGroupId: assetGroupId,
                actions: new IAction[](0),
                actionRequestTypes: new RequestType[](0),
                guards: new GuardDefinition[][](0),
                guardRequestTypes: new RequestType[](0),
                strategies: Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)),
                riskAppetite: 4,
                riskProvider: riskProvider,
                managementFeePct: 0
            });
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(60_00, 15_00, 25_00))
            );
            smartVaultA = smartVaultFactory.deploySmartVault(specification);

            specification.smartVaultName = "SmartVaultB";
            specification.strategies = Arrays.toArray(address(strategyA), address(strategyB), address(strategyC));
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(25_00, 35_00, 40_00))
            );
            smartVaultB = smartVaultFactory.deploySmartVault(specification);
        }

        // setup initial state
        {
            // Alice deposits 100 TokenA into SmartVaultA and SmartVaultB
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 200 ether);
            DepositBag memory bag = DepositBag({
                smartVault: address(smartVaultA),
                assets: Arrays.toArray(100 ether),
                receiver: alice,
                referral: address(0),
                doFlush: false
            });
            uint256 depositNftA = smartVaultManager.deposit(bag);

            bag.smartVault = address(smartVaultB);
            uint256 depositNftB = smartVaultManager.deposit(bag);
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](3);
            dhwSwapInfo[0] = new SwapInfo[](0);
            dhwSwapInfo[1] = new SwapInfo[](0);
            dhwSwapInfo[2] = new SwapInfo[](0);
            strategyRegistry.doHardWork(Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)), dhwSwapInfo);

            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim SVTs
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftA), Arrays.toArray(NFT_MINTED_SHARES)
            );
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftB), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        console.log("token A", address(tokenA));
        console.log("smart vault A", address(smartVaultA));
        console.log("smart vault B", address(smartVaultB));
        console.log("strategy A", address(strategyA));
        console.log("strategy B", address(strategyB));
        console.log("strategy C", address(strategyC));

        // check initial state
        // - assets were routed to strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 85 ether);
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 50 ether);
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 65 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether);
        // - strategy tokens were minted
        assertEq(strategyA.totalSupply(), 85_000000000000000000000);
        assertEq(strategyB.totalSupply(), 50_000000000000000000000);
        assertEq(strategyC.totalSupply(), 65_000000000000000000000);
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 60_000000000000000000000);
        assertEq(strategyB.balanceOf(address(smartVaultA)), 15_000000000000000000000);
        assertEq(strategyC.balanceOf(address(smartVaultA)), 25_000000000000000000000);
        assertEq(strategyA.balanceOf(address(smartVaultB)), 25_000000000000000000000);
        assertEq(strategyB.balanceOf(address(smartVaultB)), 35_000000000000000000000);
        assertEq(strategyC.balanceOf(address(smartVaultB)), 40_000000000000000000000);
        // - smart vault tokens were minted
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000);
        assertEq(smartVaultB.totalSupply(), 100_000000000000000000000);
        // - smart vault tokens were distributed
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000);
        assertEq(smartVaultB.balanceOf(alice), 100_000000000000000000000);

        // mock changes in allocation
        vm.mockCall(
            address(riskManager),
            abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
            abi.encode(Arrays.toArray(40_00, 30_00, 30_00))
        );

        // reallocate
        smartVaultManager.reallocate(Arrays.toArray(address(smartVaultA), address(smartVaultB)));

        // check final state
        // - assets were redistributed between strategies
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 80 ether, "final tokenA balance strategyA");
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 60 ether, "final tokenA balance strategyB");
        assertEq(tokenA.balanceOf(address(strategyC.protocol())), 60 ether, "final tokenA balance strategyC");
        assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "final tokenA balance masterWallet");
        // - strategy tokens were minted and burned
        assertEq(strategyA.totalSupply(), 80_000000000000000000000, "final SSTA supply");
        assertEq(strategyB.totalSupply(), 60_000000000000000000000, "final SSTB supply");
        assertEq(strategyC.totalSupply(), 60_000000000000000000000, "final SSTC supply");
        // - strategy tokens were distributed
        assertEq(strategyA.balanceOf(address(smartVaultA)), 40_000000000000000000000, "final SSTA balance smartVaultA");
        assertEq(strategyB.balanceOf(address(smartVaultA)), 30_000000000000000000000, "final SSTB balance smartVaultA");
        assertEq(strategyC.balanceOf(address(smartVaultA)), 30_000000000000000000000, "final SSTC balance smartVaultA");
        assertEq(strategyA.balanceOf(address(smartVaultB)), 40_000000000000000000000, "final SSTA balance smartVaultB");
        assertEq(strategyB.balanceOf(address(smartVaultB)), 30_000000000000000000000, "final SSTB balance smartVaultB");
        assertEq(strategyC.balanceOf(address(smartVaultB)), 30_000000000000000000000, "final SSTC balance smartVaultB");
        // - smart vault tokens remain unchanged
        assertEq(smartVaultA.totalSupply(), 100_000000000000000000000, "final SVTA supply");
        assertEq(smartVaultB.totalSupply(), 100_000000000000000000000, "final SVTB supply");
        // - smart vault tokens distribution remains unchanged
        assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000, "final SVTA balance alice");
        assertEq(smartVaultB.balanceOf(alice), 100_000000000000000000000, "final SVTB balance alice");
    }
}
