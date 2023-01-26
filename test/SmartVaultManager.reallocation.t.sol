// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/managers/ActionManager.sol";
import "../src/managers/AssetGroupRegistry.sol";
import "../src/managers/DepositManager.sol";
import "../src/managers/GuardManager.sol";
import "../src/managers/RewardManager.sol";
import "../src/managers/RiskManager.sol";
import "../src/managers/SmartVaultManager.sol";
import "../src/managers/StrategyRegistry.sol";
import "../src/managers/UsdPriceFeedManager.sol";
import "../src/managers/WithdrawalManager.sol";
import "../src/MasterWallet.sol";
import "../src/SmartVault.sol";
import "../src/SmartVaultFactory.sol";
import "../src/Swapper.sol";
import "./libraries/Arrays.sol";
import "./libraries/Constants.sol";
import "./mocks/MockStrategy.sol";
import "./mocks/MockToken.sol";
import "./mocks/MockPriceFeedManager.sol";

contract SmartVaultManagerHarness is SmartVaultManager {
    using ArrayMapping for mapping(uint256 => address);

    constructor(
        ISpoolAccessControl accessControl_,
        IAssetGroupRegistry assetGroupRegistry_,
        IRiskManager riskManager_,
        IDepositManager depositManager_,
        IWithdrawalManager withdrawalManager_,
        IStrategyRegistry strategyRegistry_,
        IMasterWallet masterWallet_,
        IRewardManager rewardManager_,
        IUsdPriceFeedManager priceFeedManager_
    ) SmartVaultManager(
        accessControl_,
        assetGroupRegistry_,
        riskManager_,
        depositManager_,
        withdrawalManager_,
        strategyRegistry_,
        masterWallet_,
        rewardManager_,
        priceFeedManager_)
    {}

    function exposed_reallocationMapStrategies(address[] calldata smartVaults) external returns (uint256[][] memory, uint256) {
        return _reallocationMapStrategies(smartVaults);
    }

    function exposed_reallocationStrategies(uint256 numStrategies) external view returns (address[] memory) {
        return _reallocationStrategies.toArray(numStrategies);
    }

    function exposed_reallocationCalculateReallocation(address smartVault) external returns (uint256[][] memory) {
        return _reallocationCalculateReallocation(smartVault);
    }

    function exposed_reallocationBuildReallocationTable(
        uint256[][] memory strategyMapping,
        uint256 numStrategies,
        uint256[][][] memory reallocations
    ) external pure returns (uint256[][][] memory) {
        return _reallocationBuildReallocationTable(strategyMapping, numStrategies, reallocations);
    }
}


contract SmartVaultManagerReallocationTest is Test {
    address private alice;

    address riskProvider;

    MockToken tokenA;

    SmartVaultManagerHarness private smartVaultManager;
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

        accessControl = new SpoolAccessControl();
        accessControl.initialize();

        riskProvider = address(0x1);
        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);

        masterWallet = new MasterWallet(accessControl);

        assetGroupRegistry = new AssetGroupRegistry(accessControl);
        assetGroupRegistry.initialize(Arrays.toArray(address(tokenA)));

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

        smartVaultManager = new SmartVaultManagerHarness(
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
    }

    function test_reallocationMapStrategies_shouldMapStrategies() public {
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
        ISmartVault smartVaultC;
        {
            SmartVaultSpecification memory specification = SmartVaultSpecification({
                smartVaultName: "SmartVaultA",
                assetGroupId: assetGroupId,
                actions: new IAction[](0),
                actionRequestTypes: new RequestType[](0),
                guards: new GuardDefinition[][](0),
                guardRequestTypes: new RequestType[](0),
                strategies: Arrays.toArray(address(strategyA)),
                riskAppetite: 4,
                riskProvider: riskProvider,
                managementFeePct: 0
            });
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(100_00))
            );
            smartVaultA = smartVaultFactory.deploySmartVault(specification);

            specification.smartVaultName = "SmartVaultB";
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(60_00, 40_00))
            );
            specification.strategies = Arrays.toArray(address(strategyA), address(strategyB));
            smartVaultB = smartVaultFactory.deploySmartVault(specification);

            specification.smartVaultName = "SmartVaultC";
            specification.strategies = Arrays.toArray(address(strategyB), address(strategyC));
            smartVaultC = smartVaultFactory.deploySmartVault(specification);
        }

        // check strategy mapping for smart vaults: A
        uint256[][] memory strategyMapping;
        uint256 numStrategies;
        address[] memory strategies;

        (strategyMapping, numStrategies) = smartVaultManager.exposed_reallocationMapStrategies(
            Arrays.toArray(address(smartVaultA))
        );
        assertEq(numStrategies, 1);
        assertEq(strategyMapping.length, 1);
        assertEq(strategyMapping[0], Arrays.toArray(0));

        strategies = smartVaultManager.exposed_reallocationStrategies(numStrategies);
        assertEq(strategies, Arrays.toArray(address(strategyA)));

        // check strategy mapping for smart vaults: A, B
        (strategyMapping, numStrategies) = smartVaultManager.exposed_reallocationMapStrategies(
            Arrays.toArray(address(smartVaultA), address(smartVaultB))
        );
        assertEq(numStrategies, 2);
        assertEq(strategyMapping.length, 2);
        assertEq(strategyMapping[0], Arrays.toArray(0));
        assertEq(strategyMapping[1], Arrays.toArray(0, 1));

        strategies = smartVaultManager.exposed_reallocationStrategies(numStrategies);
        assertEq(strategies, Arrays.toArray(address(strategyA), address(strategyB)));

        // check strategy mapping for smart vaults: A, C
        (strategyMapping, numStrategies) = smartVaultManager.exposed_reallocationMapStrategies(
            Arrays.toArray(address(smartVaultA), address(smartVaultC))
        );
        assertEq(numStrategies, 3);
        assertEq(strategyMapping.length, 2);
        assertEq(strategyMapping[0], Arrays.toArray(0));
        assertEq(strategyMapping[1], Arrays.toArray(1, 2));

        strategies = smartVaultManager.exposed_reallocationStrategies(numStrategies);
        assertEq(strategies, Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)));

        // check strategy mapping for smart vaults: B, C
        (strategyMapping, numStrategies) = smartVaultManager.exposed_reallocationMapStrategies(
            Arrays.toArray(address(smartVaultB), address(smartVaultC))
        );
        assertEq(numStrategies, 3);
        assertEq(strategyMapping.length, 2);
        assertEq(strategyMapping[0], Arrays.toArray(0, 1));
        assertEq(strategyMapping[1], Arrays.toArray(1, 2));

        strategies = smartVaultManager.exposed_reallocationStrategies(numStrategies);
        assertEq(strategies, Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)));

        // check strategy mapping for smart vaults: A, B, C
        (strategyMapping, numStrategies) = smartVaultManager.exposed_reallocationMapStrategies(
            Arrays.toArray(address(smartVaultA), address(smartVaultB), address(smartVaultC))
        );
        assertEq(numStrategies, 3);
        assertEq(strategyMapping.length, 3);
        assertEq(strategyMapping[0], Arrays.toArray(0));
        assertEq(strategyMapping[1], Arrays.toArray(0, 1));
        assertEq(strategyMapping[2], Arrays.toArray(1, 2));

        strategies = smartVaultManager.exposed_reallocationStrategies(numStrategies);
        assertEq(strategies, Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)));
    }

    function test_reallocationCalculateReallocation_shouldCalculateReallocation() public {
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
        ISmartVault smartVaultC;
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
                abi.encode(Arrays.toArray(60_00, 30_00, 10_00))
            );
            smartVaultA = smartVaultFactory.deploySmartVault(specification);

            specification.smartVaultName = "SmartVaultB";
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(60_00, 25_00, 15_00))
            );
            smartVaultB = smartVaultFactory.deploySmartVault(specification);

            specification.smartVaultName = "SmartVaultC";
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(50_00, 35_00, 15_00))
            );
            smartVaultC = smartVaultFactory.deploySmartVault(specification);
        }

        // setup initial state
        {
            // Alice deposits 100 TokenA into smart vaults A, B and C
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 300 ether);
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
            bag.smartVault = address(smartVaultC);
            uint256 depositNftC = smartVaultManager.deposit(bag);
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));
            smartVaultManager.flushSmartVault(address(smartVaultC));

            SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](3);
            dhwSwapInfo[0] = new SwapInfo[](0);
            dhwSwapInfo[1] = new SwapInfo[](0);
            dhwSwapInfo[2] = new SwapInfo[](0);
            strategyRegistry.doHardWork(Arrays.toArray(address(strategyA), address(strategyB), address(strategyC)), dhwSwapInfo);

            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);
            smartVaultManager.syncSmartVault(address(smartVaultC), true);

            // claim SVTs
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftA), Arrays.toArray(NFT_MINTED_SHARES)
            );
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftB), Arrays.toArray(NFT_MINTED_SHARES)
            );
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultC), Arrays.toArray(depositNftC), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // set final allocation for all smart vaults
        uint256[] memory finalAllocation = Arrays.toArray(40_00, 30_00, 30_00);
        vm.mockCall(
            address(riskManager),
            abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
            abi.encode(finalAllocation)
        );

        // check reallocation calculation for smart vault A
        uint256[][] memory result = smartVaultManager.exposed_reallocationCalculateReallocation(address(smartVaultA));
        assertEq(result.length, 2);
        assertEq(result[0], Arrays.toArray(20000000000000000000, 0, 0));
        assertEq(result[1], Arrays.toArray(0, 0, 20000000000000000000, 20000000000000000000));
        assertEq(smartVaultManager.allocations(address(smartVaultA)), finalAllocation);

        // check reallocation calculation for smart vault B
        result = smartVaultManager.exposed_reallocationCalculateReallocation(address(smartVaultB));
        assertEq(result.length, 2);
        assertEq(result[0], Arrays.toArray(20000000000000000000, 0, 0));
        assertEq(result[1], Arrays.toArray(0, 5000000000000000000, 15000000000000000000, 20000000000000000000));
        assertEq(smartVaultManager.allocations(address(smartVaultB)), finalAllocation);

        // check reallocation calculation for smart vault C
        result = smartVaultManager.exposed_reallocationCalculateReallocation(address(smartVaultC));
        assertEq(result.length, 2);
        assertEq(result[0], Arrays.toArray(10000000000000000000, 5000000000000000000, 0));
        assertEq(result[1], Arrays.toArray(0, 0, 15000000000000000000, 15000000000000000000));
        assertEq(smartVaultManager.allocations(address(smartVaultC)), finalAllocation);
    }

    function test_reallocationBuildReallocationTable_shouldBuildReallocationTable() public {
        uint256[][] memory strategyMapping;
        uint256 numStrategies;
        uint256[][][] memory reallocations;
        uint256[][][] memory reallocationTable;

        {
            // smart vault A
            // - strategies A, B and C
            strategyMapping = new uint256[][](1);
            strategyMapping[0] = Arrays.toArray(0, 1, 2); // smart vault A
            numStrategies = 3;
            reallocations = new uint256[][][](1);
            reallocations[0] = new uint256[][](2); // smart vault A

            // - A withdraws 10; 0 -> 2
            // - B withdraws 5; 1 -> 2
            // - C deposits 15
            reallocations[0][0] = Arrays.toArray(10000000000000000000, 5000000000000000000, 0); // withdrawals
            reallocations[0][1] = Arrays.toArray(0, 0, 15000000000000000000, 15000000000000000000); // deposits

            reallocationTable = smartVaultManager.exposed_reallocationBuildReallocationTable(
                strategyMapping,
                numStrategies,
                reallocations
            );
            // A -> x
            assertEq(reallocationTable[0][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[0][1], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[0][2], Arrays.toArray(10000000000000000000, 0, 0));
            // B -> x
            assertEq(reallocationTable[1][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[1][1], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[1][2], Arrays.toArray(5000000000000000000, 0, 0));
            // C -> x
            assertEq(reallocationTable[2][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[2][1], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[2][2], Arrays.toArray(0, 0, 0));

            // smart vault A
            // strategies A, B and C
            // - A withdraws 20; 0 -> 1, 0 -> 2
            // - B deposits 5
            // - C deposits 15
            reallocations[0][0] = Arrays.toArray(20000000000000000000, 0, 0); // withdrawals
            reallocations[0][1] = Arrays.toArray(0, 5000000000000000000, 15000000000000000000, 20000000000000000000); // deposits

            reallocationTable = smartVaultManager.exposed_reallocationBuildReallocationTable(
                strategyMapping,
                numStrategies,
                reallocations
            );
            // A -> x
            assertEq(reallocationTable[0][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[0][1], Arrays.toArray(5000000000000000000, 0, 0));
            assertEq(reallocationTable[0][2], Arrays.toArray(15000000000000000000, 0, 0));
            // B -> x
            assertEq(reallocationTable[1][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[1][1], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[1][2], Arrays.toArray(0, 0, 0));
            // C -> x
            assertEq(reallocationTable[2][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[2][1], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[2][2], Arrays.toArray(0, 0, 0));
        }

        {
            // smart vault A
            // - strategies A and B
            // smart vault B
            // - strategies B and C
            strategyMapping = new uint256[][](2);
            strategyMapping[0] = Arrays.toArray(0, 1); // smart vault A
            strategyMapping[1] = Arrays.toArray(1, 2); // smart vault B
            numStrategies = 3;
            reallocations = new uint256[][][](2);
            reallocations[0] = new uint256[][](2); // smart vault A
            reallocations[1] = new uint256[][](2); // smart vault B

            // smart vault A
            // - A withdraws 10; 0 -> 1
            // - B deposits 10
            reallocations[0][0] = Arrays.toArray(10000000000000000000, 0); // withdrawals
            reallocations[0][1] = Arrays.toArray(0, 10000000000000000000, 10000000000000000000); // deposits
            // smart vault B
            // - B withdraws 15; 1 -> 2
            // - C deposits 15
            reallocations[1][0] = Arrays.toArray(15000000000000000000, 0); // withdrawals
            reallocations[1][1] = Arrays.toArray(0, 15000000000000000000, 15000000000000000000); // deposits

            reallocationTable = smartVaultManager.exposed_reallocationBuildReallocationTable(
                strategyMapping,
                numStrategies,
                reallocations
            );
            // A -> x
            assertEq(reallocationTable[0][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[0][1], Arrays.toArray(10000000000000000000, 0, 0));
            assertEq(reallocationTable[0][2], Arrays.toArray(0, 0, 0));
            // B -> x
            assertEq(reallocationTable[1][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[1][1], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[1][2], Arrays.toArray(15000000000000000000, 0, 0));
            // C -> x
            assertEq(reallocationTable[2][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[2][1], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[2][2], Arrays.toArray(0, 0, 0));

            // smart vault A
            // - A withdraws 10; 0 -> 1
            // - B deposits 10
            reallocations[0][0] = Arrays.toArray(10000000000000000000, 0); // withdrawals
            reallocations[0][1] = Arrays.toArray(0, 10000000000000000000, 10000000000000000000); // deposits
            // smart vault B
            // - B deposits 15
            // - C withdraws 15; 2 -> 1
            reallocations[1][0] = Arrays.toArray(0, 15000000000000000000); // withdrawals
            reallocations[1][1] = Arrays.toArray(15000000000000000000, 0, 15000000000000000000); // deposits

            reallocationTable = smartVaultManager.exposed_reallocationBuildReallocationTable(
                strategyMapping,
                numStrategies,
                reallocations
            );
            // A -> x
            assertEq(reallocationTable[0][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[0][1], Arrays.toArray(10000000000000000000, 0, 0));
            assertEq(reallocationTable[0][2], Arrays.toArray(0, 0, 0));
            // B -> x
            assertEq(reallocationTable[1][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[1][1], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[1][2], Arrays.toArray(0, 0, 0));
            // C -> x
            assertEq(reallocationTable[2][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[2][1], Arrays.toArray(15000000000000000000, 0, 0));
            assertEq(reallocationTable[2][2], Arrays.toArray(0, 0, 0));

            // smart vault A
            // - A deposits 10;
            // - B withdraws 10; 1 -> 0
            reallocations[0][0] = Arrays.toArray(0, 10000000000000000000); // withdrawals
            reallocations[0][1] = Arrays.toArray(10000000000000000000, 0, 10000000000000000000); // deposits
            // smart vault B
            // - B withdraws 15; 1 -> 2
            // - C deposits 15
            reallocations[1][0] = Arrays.toArray(15000000000000000000, 0); // withdrawals
            reallocations[1][1] = Arrays.toArray(0, 15000000000000000000, 15000000000000000000); // deposits

            reallocationTable = smartVaultManager.exposed_reallocationBuildReallocationTable(
                strategyMapping,
                numStrategies,
                reallocations
            );
            // A -> x
            assertEq(reallocationTable[0][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[0][1], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[0][2], Arrays.toArray(0, 0, 0));
            // B -> x
            assertEq(reallocationTable[1][0], Arrays.toArray(10000000000000000000, 0, 0));
            assertEq(reallocationTable[1][1], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[1][2], Arrays.toArray(15000000000000000000, 0, 0));
            // C -> x
            assertEq(reallocationTable[2][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[2][1], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[2][2], Arrays.toArray(0, 0, 0));
        }

        {
            // smart vault A
            // - strategies A, B and C
            // smart vault B
            // - strategies A, B and C
            strategyMapping = new uint256[][](2);
            strategyMapping[0] = Arrays.toArray(0, 1, 2); // smart vault A
            strategyMapping[1] = Arrays.toArray(0, 1, 2); // smart vault B
            numStrategies = 3;
            reallocations = new uint256[][][](2);
            reallocations[0] = new uint256[][](3); // smart vault A
            reallocations[1] = new uint256[][](3); // smart vault B

            // smart vault A
            // - A withdraws 20; 0 -> 1, 0 -> 2
            // - B deposits 5
            // - C deposits 15
            reallocations[0][0] = Arrays.toArray(20000000000000000000, 0, 0); // withdrawals
            reallocations[0][1] = Arrays.toArray(0, 5000000000000000000, 15000000000000000000, 20000000000000000000); // deposits
            // smart vault B
            // - A withdraws 10; 0 -> 1
            // - B deposits 15;
            // - C withdraws 5; 2 -> 1
            reallocations[1][0] = Arrays.toArray(10000000000000000000, 0, 5000000000000000000); // withdrawals
            reallocations[1][1] = Arrays.toArray(0, 15000000000000000000, 0, 15000000000000000000); // deposits

            reallocationTable = smartVaultManager.exposed_reallocationBuildReallocationTable(
                strategyMapping,
                numStrategies,
                reallocations
            );
            // A -> x
            assertEq(reallocationTable[0][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[0][1], Arrays.toArray(15000000000000000000, 0, 0));
            assertEq(reallocationTable[0][2], Arrays.toArray(15000000000000000000, 0, 0));
            // B -> x
            assertEq(reallocationTable[1][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[1][1], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[1][2], Arrays.toArray(0, 0, 0));
            // C -> x
            assertEq(reallocationTable[2][0], Arrays.toArray(0, 0, 0));
            assertEq(reallocationTable[2][1], Arrays.toArray(5000000000000000000, 0, 0));
            assertEq(reallocationTable[2][2], Arrays.toArray(0, 0, 0));
        }
    }
}
