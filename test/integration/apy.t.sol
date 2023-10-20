// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/access/SpoolAccessControl.sol";
import "../../src/managers/ActionManager.sol";
import "../../src/managers/AssetGroupRegistry.sol";
import "../../src/managers/DepositManager.sol";
import "../../src/managers/GuardManager.sol";
import "../../src/managers/RiskManager.sol";
import "../../src/managers/SmartVaultManager.sol";
import "../../src/managers/StrategyRegistry.sol";
import "../../src/managers/UsdPriceFeedManager.sol";
import "../../src/managers/WithdrawalManager.sol";
import "../../src/strategies/GhostStrategy.sol";
import "../../src/MasterWallet.sol";
import "../../src/SmartVault.sol";
import "../../src/SmartVaultFactory.sol";
import "../../src/Swapper.sol";
import "../libraries/Arrays.sol";
import "../libraries/Constants.sol";
import "../mocks/MockExchange.sol";
import "../mocks/MockPriceFeedManager.sol";
import "../mocks/MockStrategy.sol";
import "../mocks/MockToken.sol";
import "../libraries/TimeUtils.sol";

contract ApyIntegrationTest is Test {
    address private alice;

    address private doHardWorker;
    address private riskProvider;

    MockToken private tokenA;

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

        address[] memory sorted =
            Arrays.sort(Arrays.toArray(address(new MockToken("Token", "T")), address(new MockToken("Token", "T"))));

        tokenA = MockToken(sorted[0]);

        accessControl = new SpoolAccessControl();
        accessControl.initialize();

        riskProvider = address(0x2);
        IStrategy ghostStrategy = new GhostStrategy();
        doHardWorker = address(0x3);
        accessControl.grantRole(ROLE_DO_HARD_WORKER, doHardWorker);

        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);

        masterWallet = new MasterWallet(accessControl);

        assetGroupRegistry = new AssetGroupRegistry(accessControl);
        assetGroupRegistry.initialize(Arrays.toArray(address(tokenA)));

        priceFeedManager = new MockPriceFeedManager();

        strategyRegistry = new StrategyRegistry(masterWallet, accessControl, priceFeedManager, address(ghostStrategy));
        strategyRegistry.initialize(0, 0, address(0xe), address(0xe), address(0xe));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY_REGISTRY, address(strategyRegistry));
        accessControl.grantRole(ADMIN_ROLE_STRATEGY, address(strategyRegistry));

        IActionManager actionManager = new ActionManager(accessControl);
        IGuardManager guardManager = new GuardManager(accessControl);

        riskManager = new RiskManager(accessControl, strategyRegistry, address(ghostStrategy));

        swapper = new Swapper(accessControl);

        DepositManager depositManager =
        new DepositManager(strategyRegistry, priceFeedManager, guardManager, actionManager, accessControl, masterWallet, address(ghostStrategy));
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(depositManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(depositManager));

        WithdrawalManager withdrawalManager =
            new WithdrawalManager(strategyRegistry, masterWallet, guardManager, actionManager, accessControl);
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(withdrawalManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(withdrawalManager));
        accessControl.grantRole(ROLE_ALLOCATION_PROVIDER, address(0xabc));

        smartVaultManager = new SmartVaultManager(
            accessControl,
            assetGroupRegistry,
            riskManager,
            depositManager,
            withdrawalManager,
            strategyRegistry,
            masterWallet,
            priceFeedManager,
            address(ghostStrategy)
        );
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(smartVaultManager));

        address smartVaultImplementation = address(new SmartVault(accessControl, guardManager));
        smartVaultFactory = new SmartVaultFactory(
            smartVaultImplementation,
            accessControl,
            actionManager,
            guardManager,
            smartVaultManager,
            assetGroupRegistry,
            riskManager
        );

        accessControl.grantRole(ROLE_SMART_VAULT_INTEGRATOR, address(smartVaultFactory));

        deal(address(tokenA), alice, 1000 ether, true);
    }

    function generateDhwParameterBag(address[] memory strategies, address[] memory assetGroup)
        private
        view
        returns (DoHardWorkParameterBag memory)
    {
        address[][] memory strategyGroups = new address[][](1);
        strategyGroups[0] = strategies;

        SwapInfo[][][] memory swapInfo = new SwapInfo[][][](1);
        swapInfo[0] = new SwapInfo[][](strategies.length);
        SwapInfo[][][] memory compoundSwapInfo = new SwapInfo[][][](1);
        compoundSwapInfo[0] = new SwapInfo[][](strategies.length);

        uint256[][][] memory strategySlippages = new uint256[][][](1);
        strategySlippages[0] = new uint256[][](strategies.length);

        for (uint256 i; i < strategies.length; ++i) {
            swapInfo[0][i] = new SwapInfo[](0);
            compoundSwapInfo[0][i] = new SwapInfo[](0);
            strategySlippages[0][i] = new uint256[](0);
        }

        uint256[2][] memory exchangeRateSlippages = new uint256[2][](assetGroup.length);

        for (uint256 i; i < assetGroup.length; ++i) {
            exchangeRateSlippages[i][0] = priceFeedManager.exchangeRates(assetGroup[i]);
            exchangeRateSlippages[i][1] = priceFeedManager.exchangeRates(assetGroup[i]);
        }

        int256[][] memory baseYields = new int256[][](1);
        baseYields[0] = new int256[](strategies.length);

        return DoHardWorkParameterBag({
            strategies: strategyGroups,
            swapInfo: swapInfo,
            compoundSwapInfo: compoundSwapInfo,
            strategySlippages: strategySlippages,
            tokens: assetGroup,
            exchangeRateSlippages: exchangeRateSlippages,
            baseYields: baseYields,
            validUntil: TimeUtils.getTimestampInInfiniteFuture()
        });
    }

    function _getSmartVaultSpecification() private pure returns (SmartVaultSpecification memory) {
        return SmartVaultSpecification({
            smartVaultName: "",
            svtSymbol: "MSV",
            baseURI: "https://token-cdn-domain/",
            assetGroupId: 0,
            actions: new IAction[](0),
            actionRequestTypes: new RequestType[](0),
            guards: new GuardDefinition[][](0),
            guardRequestTypes: new RequestType[](0),
            strategies: new address[](0),
            strategyAllocation: uint16a16.wrap(10_000),
            riskTolerance: 0,
            riskProvider: address(0x0),
            allocationProvider: address(0x0),
            managementFeePct: 0,
            depositFeePct: 0,
            performanceFeePct: 0,
            allowRedeemFor: false
        });
    }

    function test_update_apy_on_dhw() public {
        // setup asset group with TokenA
        uint256 assetGroupId;
        {
            assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(tokenA)));

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategy
        MockStrategy strategyA;
        {
            strategyA = new MockStrategy(assetGroupRegistry, accessControl, swapper, assetGroupId);
            strategyA.initialize("StratA", Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyA), YIELD_FULL_PERCENT_INT * 1 / 100);
        }

        address[] memory vaultStrategies = Arrays.toArray(address(strategyA));

        // setup smart vault
        ISmartVault smartVaultA;
        {
            SmartVaultSpecification memory specification = _getSmartVaultSpecification();
            specification.smartVaultName = "SmartVaultA";
            specification.assetGroupId = assetGroupId;
            specification.strategies = Arrays.toArray(address(strategyA));
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toUint16a16(100_00))
            );
            smartVaultA = smartVaultFactory.deploySmartVault(specification);
        }

        // check state
        uint256 currentIndex = strategyRegistry.currentIndex(vaultStrategies)[0];
        assertEq(currentIndex, 1);
        uint256 previousTimestamp = strategyRegistry.dhwTimestamps(vaultStrategies, uint16a16.wrap(currentIndex - 1))[0];
        uint256 currentTimestamp = strategyRegistry.dhwTimestamps(vaultStrategies, uint16a16.wrap(currentIndex))[0];
        assertEq(previousTimestamp, block.timestamp);
        assertEq(currentTimestamp, 0);
        assertEq(strategyRegistry.strategyAPYs(vaultStrategies)[0], YIELD_FULL_PERCENT_INT * 1 / 100);

        // deposit and dhw
        {
            // skip 1 year
            skip(SECONDS_IN_YEAR);

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

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            DoHardWorkParameterBag memory params =
                generateDhwParameterBag(vaultStrategies, assetGroupRegistry.listAssetGroup(assetGroupId));
            params.baseYields[0][0] = YIELD_FULL_PERCENT_INT * 2 / 100;

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(params);
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim SVTs
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNft), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        // - current DHW index increased
        currentIndex = strategyRegistry.currentIndex(vaultStrategies)[0];
        assertEq(currentIndex, 2);
        // - timestamp for previous DHW was updated
        previousTimestamp = strategyRegistry.dhwTimestamps(vaultStrategies, uint16a16.wrap(currentIndex - 1))[0];
        currentTimestamp = strategyRegistry.dhwTimestamps(vaultStrategies, uint16a16.wrap(currentIndex))[0];
        assertEq(previousTimestamp, block.timestamp);
        assertEq(currentTimestamp, 0);
        // - strategy APY was _not_ updated
        assertEq(strategyRegistry.strategyAPYs(vaultStrategies)[0], YIELD_FULL_PERCENT_INT * 1 / 100);

        // deposit and dhw
        {
            // skip 1 year
            skip(SECONDS_IN_YEAR);

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

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            DoHardWorkParameterBag memory params =
                generateDhwParameterBag(vaultStrategies, assetGroupRegistry.listAssetGroup(assetGroupId));
            params.baseYields[0][0] = YIELD_FULL_PERCENT_INT * 4 / 100;

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(params);
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim SVTs
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNft), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        // - current DHW index increased
        currentIndex = strategyRegistry.currentIndex(vaultStrategies)[0];
        assertEq(currentIndex, 3);
        // - timestamp for previous DHW was updated
        previousTimestamp = strategyRegistry.dhwTimestamps(vaultStrategies, uint16a16.wrap(currentIndex - 1))[0];
        currentTimestamp = strategyRegistry.dhwTimestamps(vaultStrategies, uint16a16.wrap(currentIndex))[0];
        assertEq(previousTimestamp, block.timestamp);
        assertEq(currentTimestamp, 0);
        // - strategy APY was updated
        assertEq(strategyRegistry.strategyAPYs(vaultStrategies)[0], YIELD_FULL_PERCENT_INT * 4 / 100);
    }
}
