// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../../src/access/SpoolAccessControl.sol";
import "../../src/managers/ActionManager.sol";
import "../../src/managers/AssetGroupRegistry.sol";
import "../../src/managers/DepositManager.sol";
import "../../src/managers/GuardManager.sol";
import "../../src/managers/RiskManager.sol";
import "../../src/managers/SmartVaultManager.sol";
import "../../src/managers/StrategyRegistry.sol";
import "../../src/managers/WithdrawalManager.sol";
import "../../src/strategies/GhostStrategy.sol";
import "../../src/MasterWallet.sol";
import "../../src/SpoolLens.sol";
import "../../src/SmartVaultFactory.sol";
import "../../src/Swapper.sol";
import "../libraries/Arrays.sol";
import "../libraries/Constants.sol";
import "../libraries/TimeUtils.sol";
import "../mocks/MockPriceFeedManager.sol";
import {
    MockStrategyNonAtomic, MockProtocolNonAtomic, ProtocolActionNotFinished
} from "../mocks/MockStrategyNonAtomic.sol";
import "../mocks/MockToken.sol";

contract NonAtomicStrategiesTest is Test {
    using uint16a16Lib for uint16a16;

    address private alice;
    address private bob;
    address private charlie;

    address private doHardWorker;
    address private ecosystemFeeRecipient;
    address private treasuryFeeRecipient;
    address private emergencyWithdrawalRecipient;
    address private riskProvider;
    address private allocationProvider;
    address private reallocator;

    MockToken private tokenA;

    SpoolAccessControl private accessControl;
    AssetGroupRegistry private assetGroupRegistry;
    MasterWallet private masterWallet;
    MockPriceFeedManager private priceFeedManager;
    IRiskManager private riskManager;
    SmartVaultFactory private smartVaultFactory;
    SmartVaultManager private smartVaultManager;
    SpoolLens private spoolLens;
    StrategyRegistry private strategyRegistry;
    Swapper private swapper;

    function setUp() public {
        alice = address(0xa);
        bob = address(0xb);
        charlie = address(0xc);

        accessControl = new SpoolAccessControl();
        accessControl.initialize();

        doHardWorker = address(0x1);
        ecosystemFeeRecipient = address(0x3);
        treasuryFeeRecipient = address(0x4);
        emergencyWithdrawalRecipient = address(0x5);
        riskProvider = address(0x6);
        allocationProvider = address(0x7);
        reallocator = address(0x8);

        accessControl.grantRole(ROLE_DO_HARD_WORKER, doHardWorker);
        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
        accessControl.grantRole(ROLE_ALLOCATION_PROVIDER, allocationProvider);
        accessControl.grantRole(ROLE_REALLOCATOR, reallocator);

        masterWallet = new MasterWallet(accessControl);

        address[] memory tokens = Arrays.sort(Arrays.toArray(address(new MockToken("Token", "T"))));
        tokenA = MockToken(tokens[0]);

        assetGroupRegistry = new AssetGroupRegistry(accessControl);
        assetGroupRegistry.initialize(tokens);

        priceFeedManager = new MockPriceFeedManager();

        IStrategy ghostStrategy = new GhostStrategy();
        strategyRegistry = new StrategyRegistry(masterWallet, accessControl, priceFeedManager, address(ghostStrategy));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY_REGISTRY, address(strategyRegistry));
        accessControl.grantRole(ADMIN_ROLE_STRATEGY, address(strategyRegistry));
        strategyRegistry.initialize(
            uint96(6_00), uint96(4_00), ecosystemFeeRecipient, treasuryFeeRecipient, emergencyWithdrawalRecipient
        );
        strategyRegistry.setEcosystemFee(uint96(6_00));
        strategyRegistry.setTreasuryFee(uint96(4_00));

        riskManager = new RiskManager(accessControl, strategyRegistry, address(ghostStrategy));

        swapper = new Swapper(accessControl);

        IActionManager actionManager = new ActionManager(accessControl);
        IGuardManager guardManager = new GuardManager(accessControl);

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

        spoolLens = new SpoolLens(
            accessControl,
            assetGroupRegistry,
            riskManager,
            depositManager,
            withdrawalManager,
            strategyRegistry,
            masterWallet,
            priceFeedManager,
            smartVaultManager,
            address(ghostStrategy)
        );

        deal(address(tokenA), alice, 1000 ether, true);
        deal(address(tokenA), bob, 1000 ether, true);
        deal(address(tokenA), charlie, 1000 ether, true);
    }

    function _generateDhwParameterBag(address[] memory strategies, address[] memory assetGroup)
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

    function _generateDhwContinuationParameterBag(address[] memory strategies, address[] memory assetGroup)
        private
        view
        returns (DoHardWorkContinuationParameterBag memory)
    {
        address[][] memory strategyGroups = new address[][](1);
        strategyGroups[0] = strategies;

        int256[][] memory baseYields = new int256[][](1);
        baseYields[0] = new int256[](strategies.length);

        bytes[][] memory continuationData = new bytes[][](1);
        continuationData[0] = new bytes[](strategies.length);

        uint256[2][] memory exchangeRateSlippages = new uint256[2][](assetGroup.length);

        for (uint256 i; i < assetGroup.length; ++i) {
            exchangeRateSlippages[i][0] = priceFeedManager.exchangeRates(assetGroup[i]);
            exchangeRateSlippages[i][1] = priceFeedManager.exchangeRates(assetGroup[i]);
        }

        return DoHardWorkContinuationParameterBag({
            strategies: strategyGroups,
            baseYields: baseYields,
            continuationData: continuationData,
            tokens: assetGroup,
            exchangeRateSlippages: exchangeRateSlippages,
            validUntil: TimeUtils.getTimestampInInfiniteFuture()
        });
    }

    function _generateReallocateParamBag(
        address[] memory smartVaults,
        address[] memory strategies,
        address[] memory assetGroup
    ) private view returns (ReallocateParamBag memory) {
        SwapInfo[][] memory reallocationSwapInfo = new SwapInfo[][](strategies.length);
        uint256[][] memory depositSlippages = new uint256[][](strategies.length);
        uint256[][] memory withdrawalSlippages = new uint256[][](strategies.length);

        for (uint256 i; i < strategies.length; ++i) {
            reallocationSwapInfo[i] = new SwapInfo[](0);

            depositSlippages[i] = new uint256[](0);
            withdrawalSlippages[i] = new uint256[](0);
        }

        uint256[2][] memory exchangeRateSlippages = new uint256[2][](assetGroup.length);
        for (uint256 i; i < assetGroup.length; ++i) {
            exchangeRateSlippages[i][0] = priceFeedManager.exchangeRates(assetGroup[i]);
            exchangeRateSlippages[i][1] = priceFeedManager.exchangeRates(assetGroup[i]);
        }

        return ReallocateParamBag({
            smartVaults: smartVaults,
            strategies: strategies,
            swapInfo: reallocationSwapInfo,
            depositSlippages: depositSlippages,
            withdrawalSlippages: withdrawalSlippages,
            exchangeRateSlippages: exchangeRateSlippages,
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
            strategyAllocation: uint16a16.wrap(0),
            riskTolerance: 0,
            riskProvider: address(0),
            allocationProvider: address(0),
            managementFeePct: 0,
            depositFeePct: 0,
            performanceFeePct: 0,
            allowRedeemFor: false
        });
    }

    function _getStrategySharesAssetBalances(address user, address strategy)
        public
        view
        returns (uint256[] memory assetBalances)
    {
        address[] memory assets = IStrategy(strategy).assets();

        uint256[] memory underlyingAssets = IStrategy(strategy).getUnderlyingAssetAmounts();
        uint256 totalSupply = IStrategy(strategy).totalSupply();
        uint256 userBalance = IStrategy(strategy).balanceOf(user);

        assetBalances = new uint256[](assets.length);
        for (uint256 i; i < assets.length; ++i) {
            assetBalances[i] = underlyingAssets[i] * userBalance / totalSupply;
        }
    }

    function _getStrategySharesAssetBalances(uint256 shares, address strategy)
        public
        view
        returns (uint256[] memory assetBalances)
    {
        address[] memory assets = IStrategy(strategy).assets();

        uint256[] memory underlyingAssets = IStrategy(strategy).getUnderlyingAssetAmounts();
        uint256 totalSupply = IStrategy(strategy).totalSupply();

        assetBalances = new uint256[](assets.length);
        for (uint256 i; i < assets.length; ++i) {
            assetBalances[i] = underlyingAssets[i] * shares / totalSupply;
        }
    }

    function _getProtocolSharesAssetBalance(uint256 shares, address protocol)
        public
        view
        returns (uint256 assetBalance)
    {
        MockProtocolNonAtomic protocol_ = MockProtocolNonAtomic(protocol);

        return protocol_.totalUnderlying() * shares / protocol_.totalShares();
    }

    function test_nonAtomicStrategyFlow_atomic_moreDeposits1() public {
        // setup asset group with token A
        uint256 assetGroupId;
        address[] memory assetGroup;
        {
            assetGroup = Arrays.toArray(address(tokenA));
            assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategyNonAtomic strategyA;
        address[] memory strategies;
        {
            // strategy A implements non-atomic strategy with
            // both deposits and withdrawals being atomic
            strategyA =
                new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, ATOMIC_STRATEGY, 2_00, true);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, ATOMIC_STRATEGY);

            strategies = Arrays.toArray(address(strategyA));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory spec = _getSmartVaultSpecification();
            spec.strategies = strategies;
            spec.strategyAllocation = uint16a16.wrap(0).set(0, 100_00);
            spec.assetGroupId = assetGroupId;

            spec.smartVaultName = "SmartVaultA";
            smartVaultA = smartVaultFactory.deploySmartVault(spec);

            spec.smartVaultName = "SmartVaultB";
            smartVaultB = smartVaultFactory.deploySmartVault(spec);
        }

        uint256 depositNftId;
        uint256 withdrawalNftId;

        // round 1 - initial deposit
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
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

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - Alice deposited 100 token A into smart vault A
            //   - 2 token A taken as fees on the protocol level
            //   - 0.000000001 to initial locked shares
            //   - 97.999999999 to smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 1000.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 100.0 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 98.0 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2.0 ether, "protocolA -> fees");

            assertEq(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0],
                0.000000001 ether,
                "strategyA asset balance -> initial locked shares"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                97.999999999 ether,
                "strategyA asset balance -> smart vault A"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> treasury fee recipient"
            );
        }

        // round 2 - yield + more deposits than withdrawals
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 19.6 ether);
            // - base yield
            strategyA.protocol().donate(4.9 ether);
            // - compound yield
            strategyA.protocol().reward(14.7 ether, address(strategyA));
            vm.stopPrank();

            // deposits + withdrawals
            // - Alice withdraws 1/10th of the strategy worth
            vm.startPrank(alice);
            withdrawalNftId = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: 9_800000000000000000000,
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );
            vm.stopPrank();
            // - Bob deposits 100 token A into smart vault B
            vm.startPrank(bob);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(100 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim
            // - withdrawal by Alice
            vm.startPrank(alice);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
            // - deposit by Bob
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 4.9 token A base yield was generated
            //   - 0.49 as fees
            //   - 4.41 to existing shares
            // - 14.7 token A compound yield was generated
            // - Alice withdrew 10% of the strategy worth
            //   - 10.241 token A (= 9.8 + 0.441)
            // - Bob deposited 100 token A into smart vault B
            // how to process
            // - compound yield
            //   - 10.241 token A is matched with withdrawal
            //   - 4.459 token A is deposited into protocol
            // - deposit
            //   - 100 token A (full amount) is deposited into protocol
            // - protocol deposit
            //   - 104.459 token A is deposited into protocol
            //     - 2.08918 is taken as protocol fees
            //     - 102.36982 is counted to strategy A
            //       - 4.36982 for compound yield
            //       - 98 for deposit
            // - compound yield
            //   - 14.61082 token A (= 10.241 + 4.36982)
            //     - 1.461082 as fees
            //     - 13.149738 to legacy users
            // how to distribute
            // - 10.241 token A as Alice's withdrawal
            // - 98 token A as smart vault B's deposit
            // - 2.08918 token A is taken as protocol fees
            // - 1.951082 token A (= 0.49 + 1.461082) as fees
            //   - 1.1706492 to ecosystem fee recipient
            //   - 0.7804328 to treasury fee recipient
            // - 105.318738 token A (= 98 + 4.41 - 10.241 + 13.149738) for smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 910.241 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 900.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 209.359 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 205.26982 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 4.08918 ether, "protocolA -> fees");

            assertEq(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                205.26982 ether,
                "protocolA asset balance -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                105.318738 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                98.0 ether,
                1e7,
                "strategyA asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                1.1706492 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.7804328 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }
    }

    function test_nonAtomicStrategyFlow_atomic_moreDeposits2() public {
        // setup asset group with token A
        uint256 assetGroupId;
        address[] memory assetGroup;
        {
            assetGroup = Arrays.toArray(address(tokenA));
            assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategyNonAtomic strategyA;
        address[] memory strategies;
        {
            // strategy A implements non-atomic strategy with
            // both deposits and withdrawals being atomic
            strategyA =
                new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, ATOMIC_STRATEGY, 2_00, true);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, ATOMIC_STRATEGY);

            strategies = Arrays.toArray(address(strategyA));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory spec = _getSmartVaultSpecification();
            spec.strategies = strategies;
            spec.strategyAllocation = uint16a16.wrap(0).set(0, 100_00);
            spec.assetGroupId = assetGroupId;

            spec.smartVaultName = "SmartVaultA";
            smartVaultA = smartVaultFactory.deploySmartVault(spec);

            spec.smartVaultName = "SmartVaultB";
            smartVaultB = smartVaultFactory.deploySmartVault(spec);
        }

        uint256 depositNftId;
        uint256 withdrawalNftId;

        // round 1 - initial deposit
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
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

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - Alice deposited 100 token A into smart vault A
            //   - 2 token A taken as fees on the protocol level
            //   - 0.000000001 to initial locked shares
            //   - 97.999999999 to smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 1000.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 100.0 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 98.0 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2.0 ether, "protocolA -> fees");

            assertEq(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0],
                0.000000001 ether,
                "strategyA asset balance -> initial locked shares"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                97.999999999 ether,
                "strategyA asset balance -> smart vault A"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> treasury fee recipient"
            );
        }

        // round 2 - yield + more deposits than withdrawals
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 19.6 ether);
            // - base yield
            strategyA.protocol().donate(4.9 ether);
            // - compound yield
            strategyA.protocol().reward(14.7 ether, address(strategyA));
            vm.stopPrank();

            // deposits + withdrawals
            // - Alice withdraws 1/2 of the strategy worth
            vm.startPrank(alice);
            withdrawalNftId = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: 49_000000000000000000000,
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );
            vm.stopPrank();
            // - Bob deposits 100 token A into smart vault B
            vm.startPrank(bob);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(100 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim
            // - withdrawal by Alice
            vm.startPrank(alice);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
            // - deposit by Bob
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 4.9 token A base yield was generated
            //   - 0.49 as fees
            //   - 4.41 to existing shares
            // - 14.7 token A compound yield was generated
            // - Alice withdrew 50% of the strategy worth
            //   - 51.205 token A (= 49 + 2.205)
            // - Bob deposited 100 token A into smart vault B
            // how to process
            // - compound yield
            //   - 14.7 token A (full amount) is matched with withdrawal
            //     - 1.47 as fees
            //     - 13.23 to legacy users
            // - deposit
            //   - 36.505 token A is matched with withdrawal
            //   - 63.495 token A is deposited into protocol
            // - protocol deposit
            //   - 63.495 token A is deposited into protocol
            //     - 1.2699 is taken as protocol fees
            //     - 62.2251 is counted to strategy A for deposit
            // how to distribute
            // - 51.205 token A as Alice's withdrawal
            // - 98.7301 token A (= 36.505 + 62.2251) as smart vault B's deposit
            // - 1.2699 token A is taken as protocol fees
            // - 1.96 token A (= 0.49 + 1.47) as fees
            //   - 1.176 to ecosystem fee recipient
            //   - 0.784 to treasury fee recipient
            // - 64.435 token A (= 98 + 4.41 - 51.205 + 13.23) for smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 951.205 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 900.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 168.395 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 165.1251 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 3.2699 ether, "protocolA -> fees");

            assertEq(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                165.1251 ether,
                "protocolA asset balance -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                64.435 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                98.7301 ether,
                1e7,
                "strategyA asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                1.176 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.784 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }
    }

    function test_nonAtomicStrategyFlow_atomic_moreWithdrawals1() public {
        // setup asset group with token A
        uint256 assetGroupId;
        address[] memory assetGroup;
        {
            assetGroup = Arrays.toArray(address(tokenA));
            assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategyNonAtomic strategyA;
        address[] memory strategies;
        {
            // strategy A implements non-atomic strategy with
            // both deposits and withdrawals being atomic
            strategyA =
                new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, ATOMIC_STRATEGY, 2_00, true);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, ATOMIC_STRATEGY);

            strategies = Arrays.toArray(address(strategyA));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory spec = _getSmartVaultSpecification();
            spec.strategies = strategies;
            spec.strategyAllocation = uint16a16.wrap(0).set(0, 100_00);
            spec.assetGroupId = assetGroupId;

            spec.smartVaultName = "SmartVaultA";
            smartVaultA = smartVaultFactory.deploySmartVault(spec);

            spec.smartVaultName = "SmartVaultB";
            smartVaultB = smartVaultFactory.deploySmartVault(spec);
        }

        uint256 depositNftId;
        uint256 withdrawalNftId;

        // round 1 - initial deposit
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
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

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - Alice deposited 100 token A into smart vault A
            //   - 2 token A taken as fees on the protocol level
            //   - 0.000000001 to initial locked shares
            //   - 97.999999999 to smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 1000.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 100.0 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 98.0 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2.0 ether, "protocolA -> fees");

            assertEq(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0],
                0.000000001 ether,
                "strategyA asset balance -> initial locked shares"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                97.999999999 ether,
                "strategyA asset balance -> smart vault A"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> treasury fee recipient"
            );
        }

        // round 2 - yield + more withdrawals that deposits
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 19.6 ether);
            // - base yield
            strategyA.protocol().donate(4.9 ether);
            // - compound yield
            strategyA.protocol().reward(14.7 ether, address(strategyA));
            vm.stopPrank();

            // deposits + withdrawals
            // - Alice withdraws 1/2 of the strategy worth
            vm.startPrank(alice);
            withdrawalNftId = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: 49_000000000000000000000,
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );
            vm.stopPrank();
            // - Bob deposits 10 token A into smart vault B
            vm.startPrank(bob);
            tokenA.approve(address(smartVaultManager), 10 ether);
            depositNftId = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(10 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim
            // - withdrawal by Alice
            vm.startPrank(alice);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
            // - deposit by Bob
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 4.9 token A base yield was generated
            //   - 0.49 as fees
            //   - 4.41 to existing shares
            // - 14.7 token A compound yield was generated
            // - Alice withdrew 50% of the strategy worth
            //   - 51.205 token A (= 49 + 2.205)
            // - Bob deposited 10 token A into smart vault B
            // how to process
            // - compound yield
            //   - 14.7 token A (full amount) is matched with withdrawal
            //     - 1.47 as fees
            //     - 13.23 to legacy users
            // - deposit
            //   - 10 token A (full amount) is matched with withdrawal
            // - withdrawal
            //   - 24.7 token A is matched with deposits
            //   - 26.505 token A is withdrawn from protocol
            //     - 0.5301 is taken as protocol fees
            //     - 25.9749 is withdrawn to strategy A
            // how to distribute
            // - 50.6749 token A (= 24.7 + 25.9749) as Alice's withdrawal
            // - 10 token A as smart vault B's deposit
            // - 0.5301 token A is taken as protocol fees
            // - 1.96 token A (= 0.49 + 1.47) as fees
            //   - 1.176 to ecosystem fee recipient
            //   - 0.784 to treasury fee recipient
            // - 64.435 token A (= 98 + 4.41 - 51.205 + 13.23) for smart vault A

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 950.6749 ether, 1, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 990.0 ether, 1, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0 ether, 1, "tokenA -> MasterWallet");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyA.protocol())), 78.9251 ether, 1, "tokenA -> protocolA");
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 76.395 ether, 1, "protocolA -> totalUnderlying");
            assertApproxEqAbs(strategyA.protocol().fees(), 2.5301 ether, 1, "protocolA -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                76.395 ether,
                1,
                "protocolA asset balance -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                64.435 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                10.0 ether,
                1e7,
                "strategyA asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                1.176 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.784 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }
    }

    function test_nonAtomicStrategyFlow_atomic_equal1() public {
        // setup asset group with token A
        uint256 assetGroupId;
        address[] memory assetGroup;
        {
            assetGroup = Arrays.toArray(address(tokenA));
            assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategyNonAtomic strategyA;
        address[] memory strategies;
        {
            // strategy A implements non-atomic strategy with
            // both deposits and withdrawals being atomic
            strategyA =
                new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, ATOMIC_STRATEGY, 2_00, true);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, ATOMIC_STRATEGY);

            strategies = Arrays.toArray(address(strategyA));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory spec = _getSmartVaultSpecification();
            spec.strategies = strategies;
            spec.strategyAllocation = uint16a16.wrap(0).set(0, 100_00);
            spec.assetGroupId = assetGroupId;

            spec.smartVaultName = "SmartVaultA";
            smartVaultA = smartVaultFactory.deploySmartVault(spec);

            spec.smartVaultName = "SmartVaultB";
            smartVaultB = smartVaultFactory.deploySmartVault(spec);
        }

        uint256 depositNftId;
        uint256 withdrawalNftId;

        // round 1 - initial deposit
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
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

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - Alice deposited 100 token A into smart vault A
            //   - 2 token A taken as fees on the protocol level
            //   - 0.000000001 to initial locked shares
            //   - 97.999999999 to smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 1000.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 100.0 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 98.0 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2.0 ether, "protocolA -> fees");

            assertEq(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0],
                0.000000001 ether,
                "strategyA asset balance -> initial locked shares"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                97.999999999 ether,
                "strategyA asset balance -> smart vault A"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> treasury fee recipient"
            );
        }

        // round 2 - yield + equal deposits and withdrawals
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 19.6 ether);
            // - base yield
            strategyA.protocol().donate(4.9 ether);
            // - compound yield
            strategyA.protocol().reward(14.7 ether, address(strategyA));
            vm.stopPrank();

            // deposits + withdrawals
            // - Alice withdraws 1/2 of the strategy worth
            vm.startPrank(alice);
            withdrawalNftId = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: 49_000000000000000000000,
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );
            // Bob deposits 36.505 token A into smart vault B
            vm.startPrank(bob);
            tokenA.approve(address(smartVaultManager), 36.505 ether);
            depositNftId = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(36.505 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();

            // claim
            // - withdrawal by Alice
            vm.startPrank(alice);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
            // - deposit by Bob
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 4.9 token A base yield was generated
            //   - 0.49 as fees
            //   - 4.41 to existing shares
            // - 14.7 token A compound yield was generated
            // - Alice withdrew 50% of the strategy worth
            //   - 51.205 token A (= 49 + 2.205)
            // - Bob deposited 36.505 token A into smart vault B
            // how to process
            // - compound yield
            //   - 14.7 token A (full amount) is matched with withdrawal
            //     - 1.47 as fees
            //     - 13.23 to legacy users
            // - deposit
            //   - 36.505 token A (full amount) is matched with withdrawal
            // - withdrawal
            //   - 51.205 token A (full amount) is matched with deposits
            // how to distribute
            // - 51.205 token A as Alice's withdrawal
            // - 36.505 token A as smart vault B's deposit
            // - 0 token A as protocol fees
            // - 1.96 token A (= 0.49 + 1.47) as fees
            //   - 1.176 to ecosystem fee recipient
            //   - 0.784 to treasury fee recipient
            // - 64.435 token A (= 98 + 4.41 - 51.205 + 13.23) for smart vault A
            // - 36.505 token A for smart vault B

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 951.205 ether, 1, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 963.495 ether, 1, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0 ether, 1, "tokenA -> MasterWallet");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyA.protocol())), 104.9 ether, 1, "tokenA -> protocolA");
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 102.9 ether, 1, "protocolA -> totalUnderlying");
            assertApproxEqAbs(strategyA.protocol().fees(), 2.0 ether, 1, "protocolA -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                102.9 ether,
                1,
                "protocolA asset balance -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                64.435 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                36.505 ether,
                1e7,
                "strategyA asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                1.176 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.784 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }

        // round 3 - base yield only
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 5.145 ether);
            // - base yield
            strategyA.protocol().donate(5.145 ether);
            vm.stopPrank();

            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 5.145 token A base yield was generated
            //   - 0.098 to fees recipients
            //   - 3.22175 for smart vault A
            //     - 0.322175 to fees
            //     - 2.899575 to smart vault A
            //   - 1.82525 for smart vault B
            //     - 0.182525 to fees
            //     - 1.642725 to smart vault B
            // new state
            // - 2.5627 token A (= 1.96 + 0.098 + 0.322175 + 0.182525) as fees
            //   - 1.53762 to ecosystem fee recipient
            //   - 1.02508 to treasury fee recipient
            // - 67.334575 token A (= 64.435 + 2.899575) for smart vault A
            // - 38.147725 token A (= 36.505 + 1.642725) for smart vault B

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 951.205 ether, 1, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 963.495 ether, 1, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0 ether, 1, "tokenA -> MasterWallet");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyA.protocol())), 110.045 ether, 1, "tokenA -> protocolA");
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 108.045 ether, 1, "protocolA -> totalUnderlying");
            assertApproxEqAbs(strategyA.protocol().fees(), 2.0 ether, 1, "protocolA -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                108.045 ether,
                1,
                "protocolA asset balance -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                67.334575 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                38.147725 ether,
                1e7,
                "strategyA asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                1.53762 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                1.02508 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }
    }

    function test_nonAtomicStrategyFlow_nonAtomic_moreDeposits1() public {
        // setup asset group with token A
        uint256 assetGroupId;
        address[] memory assetGroup;
        {
            assetGroup = Arrays.toArray(address(tokenA));
            assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategyNonAtomic strategyA;
        address[] memory strategies;
        {
            // strategy A implements non-atomic strategy with
            // both deposits and withdrawals being non-atomic
            strategyA =
            new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, NON_ATOMIC_STRATEGY, 2_00, true);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, NON_ATOMIC_STRATEGY);

            strategies = Arrays.toArray(address(strategyA));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory spec = _getSmartVaultSpecification();
            spec.strategies = strategies;
            spec.strategyAllocation = uint16a16.wrap(0).set(0, 100_00);
            spec.assetGroupId = assetGroupId;

            spec.smartVaultName = "SmartVaultA";
            smartVaultA = smartVaultFactory.deploySmartVault(spec);

            spec.smartVaultName = "SmartVaultB";
            smartVaultB = smartVaultFactory.deploySmartVault(spec);
        }

        uint256 depositNftId;
        uint256 withdrawalNftId;

        // round 1 - initial deposit
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
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

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - Alice deposited 100 token A into smart vault A
            //   - 2 token A taken as fees on the protocol level
            //   - 0.000000001 to initial locked shares
            //   - 97.999999999 to smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 1000.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 100.0 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 98.0 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2.0 ether, "protocolA -> fees");

            assertEq(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0],
                0.000000001 ether,
                "strategyA asset balance -> initial locked shares"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                97.999999999 ether,
                "strategyA asset balance -> smart vault A"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> treasury fee recipient"
            );
        }

        // round 2.1 - yield + more deposits than withdrawals
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 19.6 ether);
            // - base yield
            strategyA.protocol().donate(4.9 ether);
            // - compound yield
            strategyA.protocol().reward(14.7 ether, address(strategyA));
            vm.stopPrank();

            // deposits + withdrawals
            // - Alice withdraws 1/10th of the strategy worth
            vm.startPrank(alice);
            withdrawalNftId = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: 9_800000000000000000000,
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );
            vm.stopPrank();
            // - Bob deposits 100 token A into smart vault B
            vm.startPrank(bob);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(100 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 4.9 token A base yield was generated
            //   - 0.49 for withdrawal
            //     - 0.049 as fees
            //     - 0.441 for withdrawal
            //   - 4.41 to legacy users
            //     - 0.441 as fees
            //     - 3.969 to legacy users
            // - 14.7 token A compound yield was generated
            // - Alice withdrew 10% of the strategy worth
            //   - 10.241 token A (= 9.8 + 0.441)
            // - Bob deposited 100 token A into smart vault B
            // how to process
            // - compound yield
            //   - 10.241 token A is matched with withdrawal
            //     - 1.0241 as fees
            //     - 9.2169 to legacy users
            //   - 4.459 token A is deposited into protocol
            //     - waits for continuation
            // - deposit
            //   - 100 token A (full amount) is deposited into protocol
            // how to distribute
            // - 10.241 token A as Alice's withdrawal on master wallet
            // - 104.459 token A (= 100 + 4.459) is deposited into protocol
            // - 1.5141 token A for strategy A
            //   - 0.049 is reserved for withdrawal fees
            //   - 1.4651 (= 0.441 + 1.0241) is reserved as legacy fees
            // - 101.3859 token A (= 98 - 9.8 + 3.969 + 9.2169) for smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 900.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 10.241 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 209.359 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 102.9 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2 ether, "protocolA -> fees");

            assertEq(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                102.9 ether,
                "protocolA asset balance -> strategyA"
            );
            assertEq(
                strategyA.protocol().pendingInvestments(address(strategyA)),
                104.459 ether,
                "protocolA pending investments -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                101.3859 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                1.5141 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }

        // round 2.2 - DHW continuation + yield
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 5.145 ether);
            // - base yield
            strategyA.protocol().donate(5.145 ether);
            vm.stopPrank();

            // DHW, sync
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim
            // - withdrawal by Alice
            vm.startPrank(alice);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
            // - deposit by Bob
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 5.145 token A base yield was generated
            //   - 5.069295 for legacy users
            //   - 0.00245 for withdrawal fees
            //   - 0.073255 for legacy fees
            // - 104.459 token A deposit into protocol finished
            //   - 2.08918 is taken as protocol fees
            //   - 102.36982 for strategy A
            //     - 98.0 for deposited deposit
            //     - 4.36982 for deposited compound
            // how to process
            // - legacy users
            //   - 88.2 token A base
            //   - 24.16337 token A yield
            //     - 4.41 base yield on DHW
            //     - 10.241 matched compound yield
            //     - 5.14255 (= 5.069295 + 0.073255) base yield on continuation
            //     - 4.36982 matched compound yield
            //   - 2.416337 token A is taken as legacy fees
            // - deposits
            //   - 98.0 token A is deposited into protocol on continuation
            // - fees
            //   - 2.416337 token A as legacy fees
            //   - 0.05145 token A as withdrawal fees
            //     - 0.049 on DHW
            //     - 0.00245 base yield on continuation
            // - fees on protool level
            //   - 2 token A in step 1
            //   - 2.08918 token A in step 2
            // how to distribute
            // - 109.947033 token A for smart vault A
            // - 2.467787 token A for fees
            //   - 1.4806722 to ecosystem fee recipient
            //   - 0.9871148 to treasury fee recipient
            // - 98 token A for smart vault B
            // - 4.08918 token A for fees on protocol level
            // - 10.241 token A for Alice's withdrawal

            assertEq(tokenA.balanceOf(address(alice)), 910.241 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 900.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0.0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 214.504 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 210.41482 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 4.08918 ether, "protocolA -> fees");

            assertEq(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                210.41482 ether,
                "protocolA asset balance -> strategyA"
            );
            assertEq(
                strategyA.protocol().pendingInvestments(address(strategyA)),
                0.0 ether,
                "protocolA pending investments -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                109.947033 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                98 ether,
                1e7,
                "strategyA asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                1.4806722 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.9871148 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }
    }

    function test_nonAtomicStrategyFlow_nonAtomic_moreDeposits2() public {
        // setup asset group with token A
        uint256 assetGroupId;
        address[] memory assetGroup;
        {
            assetGroup = Arrays.toArray(address(tokenA));
            assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategyNonAtomic strategyA;
        address[] memory strategies;
        {
            // strategy A implements non-atomic strategy with
            // both deposits and withdrawals being non-atomic
            strategyA =
            new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, NON_ATOMIC_STRATEGY, 2_00, true);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, NON_ATOMIC_STRATEGY);

            strategies = Arrays.toArray(address(strategyA));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory spec = _getSmartVaultSpecification();
            spec.strategies = strategies;
            spec.strategyAllocation = uint16a16.wrap(0).set(0, 100_00);
            spec.assetGroupId = assetGroupId;

            spec.smartVaultName = "SmartVaultA";
            smartVaultA = smartVaultFactory.deploySmartVault(spec);

            spec.smartVaultName = "SmartVaultB";
            smartVaultB = smartVaultFactory.deploySmartVault(spec);
        }

        uint256 depositNftId;
        uint256 withdrawalNftId;

        // round 1 - initial deposit
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
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

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - Alice deposited 100 token A into smart vault A
            //   - 2 token A taken as fees on the protocol level
            //   - 0.000000001 to initial locked shares
            //   - 97.999999999 to smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 1000.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 100.0 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 98.0 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2.0 ether, "protocolA -> fees");

            assertEq(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0],
                0.000000001 ether,
                "strategyA asset balance -> initial locked shares"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                97.999999999 ether,
                "strategyA asset balance -> smart vault A"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> treasury fee recipient"
            );
        }

        // round 2.1 - yield + more deposits than withdrawals
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 19.6 ether);
            // - base yield
            strategyA.protocol().donate(4.9 ether);
            // - compound yield
            strategyA.protocol().reward(14.7 ether, address(strategyA));
            vm.stopPrank();

            // deposits + withdrawals
            // - Alice withdraws 1/2 of the strategy worth
            vm.startPrank(alice);
            withdrawalNftId = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: 49_000000000000000000000,
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );
            vm.stopPrank();
            // - Bob deposits 100 token A into smart vault B
            vm.startPrank(bob);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(100 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 4.9 token A base yield was generated
            //   - 2.45 for withdrawal
            //     - 0.245 as fees
            //     - 2.205 for withdrawal
            //   - 2.45 to legacy users
            //     - 0.245 as fees
            //     - 2.205 to legacy users
            // - 14.7 token A compound yield was generated
            // - Alice withdrew 50% of the strategy worth
            //   - 51.205 token A (= 49 + 2.205)
            // - Bob deposited 100 token A into smart vault B
            // how to process
            // - compound yield
            //   - 14.7 token A is matched with withdrawal
            //     - 1.47 as fees
            //     - 13.23 to legacy users
            // - deposit
            //   - 36.505 token A is matched with withdrawal
            //   - 63.495 token A is deposited into protocol
            //     - waits for continuation
            // how to distribute
            // - 51.205 token A as Alice's withdrawal on master wallet
            // - 63.495 token A is deposited into protocol
            // - 38.465 token A for strategy A
            //   - 36.505 is reserved for matched deposits
            //   - 0.245 is reserved for withdrawal fees
            //   - 1.715 token A (= 0.245 + 1.47) is reserved as legacy fees
            // - 64.435 token A (= 98 - 49 + 2.205 + 13.23) for smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 900.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 51.205 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 168.395 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 102.9 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2 ether, "protocolA -> fees");

            assertEq(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                102.9 ether,
                "protocolA asset balance -> strategyA"
            );
            assertEq(
                strategyA.protocol().pendingInvestments(address(strategyA)),
                63.495 ether,
                "protocolA pending investments -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                64.435 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                38.465 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }

        // round 2.2 - DHW continuation + yield
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 5.145 ether);
            // - base yield
            strategyA.protocol().donate(5.145 ether);
            vm.stopPrank();

            // DHW, sync
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim
            // - withdrawal by Alice
            vm.startPrank(alice);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
            // - deposit by Bob
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 5.145 token A base yield was generated
            //   - 3.22175 for legacy users
            //   - 1.82525 for matched deposits
            //   - 0.01225 for withdrawal fees
            //   - 0.08575 for legacy fees
            // - 63.495 token A deposit into protocol finished
            //   - 1.2699 is taken as protocol fees
            //   - 62.2251 for strategy A
            //     - 62.2251 for deposited deposits
            // how to process
            // - legacy users
            //   - 49 token A base
            //   - 20.4575 token A yield
            //     - 2.45 base yield on DHW
            //     - 14.7 matched compound yield
            //     - 3.3075 (= 3.22175 + 0.08575) base yield on continuation
            //   - 2.04575 token A is taken as legacy fees
            // - deposits
            //   - 36.505 token A is matched with withdrawal
            //   - 62.2251 token A is deposited into protocol on continuation
            //   - 1.82525 token A base yield on continuation
            //   - 0.182525 token A is taken as deposit fees
            // - fees
            //   - 2.04575 token A as legacy fees
            //   - 0.25725 token A as withdrawal fees
            //     - 0.245 on DHW
            //     - 0.01225 base yield on continuation
            //   - 0.182525 token A as deposit fees
            // - fees on protocol level
            //   - 2 token A in step 1
            //   - 1.2699 token A in step 2
            // how to distribute
            // - 67.41175 token A for smart vault A
            // - 100.372825 token A for smart vault B
            // - 2.485525 token A for fees
            //   - 1.491315 to ecosystem fee recipient
            //   - 0.99421 to treasury fee recipient
            // - 3.2699 token A for fees on protocol level
            // - 51.205 token A for Alice's withdrawal

            assertEq(tokenA.balanceOf(address(alice)), 951.205 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 900.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0.0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 173.54 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 170.2701 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 3.2699 ether, "protocolA -> fees");

            assertEq(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                170.2701 ether,
                "protocolA asset balance -> strategyA"
            );
            assertEq(
                strategyA.protocol().pendingInvestments(address(strategyA)),
                0 ether,
                "protocolA pending investments -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                67.41175 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                100.372825 ether,
                1e7,
                "strategyA asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                1.491315 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.99421 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }
    }

    function test_nonAtomicStrategyFlow_nonAtomic_moreWithdrawals1() public {
        // setup asset group with token A
        uint256 assetGroupId;
        address[] memory assetGroup;
        {
            assetGroup = Arrays.toArray(address(tokenA));
            assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategyNonAtomic strategyA;
        address[] memory strategies;
        {
            // strategy A implements non-atomic strategy with
            // both deposits and withdrawals being non-atomic
            strategyA =
            new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, NON_ATOMIC_STRATEGY, 2_00, true);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, NON_ATOMIC_STRATEGY);

            strategies = Arrays.toArray(address(strategyA));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory spec = _getSmartVaultSpecification();
            spec.strategies = strategies;
            spec.strategyAllocation = uint16a16.wrap(0).set(0, 100_00);
            spec.assetGroupId = assetGroupId;

            spec.smartVaultName = "SmartVaultA";
            smartVaultA = smartVaultFactory.deploySmartVault(spec);

            spec.smartVaultName = "SmartVaultB";
            smartVaultB = smartVaultFactory.deploySmartVault(spec);
        }

        uint256 depositNftId;
        uint256 withdrawalNftId;

        // round 1 - initial deposit
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
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

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - Alice deposited 100 token A into smart vault A
            //   - 2 token A taken as fees on the protocol level
            //   - 0.000000001 to initial locked shares
            //   - 97.999999999 to smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 1000.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 100.0 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 98.0 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2.0 ether, "protocolA -> fees");

            assertEq(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0],
                0.000000001 ether,
                "strategyA asset balance -> initial locked shares"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                97.999999999 ether,
                "strategyA asset balance -> smart vault A"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> treasury fee recipient"
            );
        }

        // round 2.1 - yield + more withdrawals than deposits
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 19.6 ether);
            // - base yield
            strategyA.protocol().donate(4.9 ether);
            // - compound yield
            strategyA.protocol().reward(14.7 ether, address(strategyA));
            vm.stopPrank();

            // deposits + withdrawals
            // - Alice withdraws 1/2 of the strategy worth
            vm.startPrank(alice);
            withdrawalNftId = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: 49_000000000000000000000,
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );
            vm.stopPrank();
            // - Bob deposits 10 token A into smart vault B
            vm.startPrank(bob);
            tokenA.approve(address(smartVaultManager), 10 ether);
            depositNftId = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(10 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 4.9 token A base yield was generated
            //   - 2.45 for withdrawal
            //     - 0.245 as fees
            //     - 2.205 for withdrawal
            //   - 2.45 to legacy users
            //     - 0.245 as fees
            //     - 2.205 to legacy users
            // - 14.7 token A compound yield was generated
            // - Alice withdrew 50% of the strategy worth
            //   - 51.205 token A (= 49 + 2.205)
            // - Bob deposited 10 token A into smart vault B
            // how to process
            // - compound yield
            //   - 14.7 token A is matched with withdrawal
            //     - 1.47 as fees
            //     - 13.23 to legacy users
            // - deposit
            //   - 10 token A is matched with withdrawal
            // - withdrawal
            //   - 24.7 token A is matched with deposits
            //   - 26.505 token A is withdrawn from protocol
            //     - waits for continuation
            // how to distribute
            // - 24.7 token A as Alice's withdrawal on master wallet
            // - 26.505 token A is withdrawn from protocol
            // - 11.96 token A for strategy A
            //   - 10 is reserved for matched deposits
            //   - 0.245 is reserved for withdrawal fees
            //   - 1.715 token A (= 0.245 + 1.47) is reserved as legacy fees
            // - 64.435 token A (= 98 - 49 + 2.205 + 13.23) for smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 990.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 24.7 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 104.9 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 102.9 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2 ether, "protocolA -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                76.395 ether,
                1e7,
                "protocolA asset balance -> strategyA"
            );
            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().pendingDivestments(address(strategyA)), address(strategyA.protocol())
                ),
                26.505 ether,
                1e7,
                "protocolA pending divestment -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                64.435 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                11.96 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }

        // round 2.2 - DHW continuation + yield
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 5.145 ether);
            // - base yield
            strategyA.protocol().donate(5.145 ether);
            vm.stopPrank();

            // DHW, sync
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim
            // - withdrawal by Alice
            vm.startPrank(alice);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
            // - deposit by Bob
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 5.145 token A base yield was generated
            //   - 3.22175 for legacy users
            //   - 1.32525 for withdrawn withdrawals
            //   - 0.5 for matched deposits
            //   - 0.01225 for withdrawal fees
            //   - 0.08575 for legacy fees
            // - 27.273645 token A withdrawal from protocol finished
            //   - 26.505 is withdrawn from protocol
            //   - 1.32525 base yield on continuation
            //   - 0.556605 is taken as protocol fees
            //   - no fees are taken for yield
            // how to process
            //   - legacy users
            //     - 49 token A base
            //     - 20.4575 token A yield
            //       - 2.45 base yield on DHW
            //       - 14.7 matched compound yield
            //       - 3.3075 (= 3.22175 + 0.08575) base yield on continuation
            //     - 2.04575 token A is taken as legacy fees
            // - deposits
            //   - 10 token A is matched with withdrawal
            //   - 0.5 token A base yield on continuation
            //   - 0.05 token A is taken as deposit fees
            // - fees
            //   - 2.04575 token A as legacy fees
            //   - 0.25725 token A as withdrawal fees
            //     - 0.245 on DHW
            //     - 0.01225 base yield on continuation
            //   - 0.05 token A as deposit fees
            // - fees on protocol level
            //   - 2 token A in step 1
            //   - 0.556605 token A in step 2
            // - withdrawal
            //   - 24.7 token A is matched with deposits
            //   - 27.273645 token A is withdrawn from protocol
            // how to distribute
            // - 67.41175 token A for smart vault A
            // - 10.45 token A for smart vault B
            // - 2.353 token A for fees
            //   - 1.4118 to ecosystem fee recipient
            //   - 0.9412 to treasury fee recipient
            // - 2.556605 token A for fees on protocol level
            // - 51.973645 token A for Alice's withdrawal

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 951.973645 ether, 1, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 990.0 ether, 1, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0.0 ether, 1, "tokenA -> MasterWallet");
            assertApproxEqAbs(
                tokenA.balanceOf(address(strategyA.protocol())), 82.771355 ether, 1, "tokenA -> protocolA"
            );
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 80.21475 ether, 1, "protocolA -> totalUnderlying");
            assertApproxEqAbs(strategyA.protocol().fees(), 2.556605 ether, 1, "protocolA -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                80.21475 ether,
                1,
                "protocolA asset balance -> strategyA"
            );
            assertApproxEqAbs(
                strategyA.protocol().pendingInvestments(address(strategyA)),
                0 ether,
                1,
                "protocolA pending investments -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                67.41175 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                10.45 ether,
                1e7,
                "strategyA asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                1.4118 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.9412 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }
    }

    function test_nonAtomicStrategyFlow_nonAtomic_moreWithdrawals2() public {
        // setup asset group with token A
        uint256 assetGroupId;
        address[] memory assetGroup;
        {
            assetGroup = Arrays.toArray(address(tokenA));
            assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategyNonAtomic strategyA;
        address[] memory strategies;
        {
            // strategy A implements non-atomic strategy with
            // both deposits and withdrawals being non-atomic
            // protocol does not deduct shares immediately on withdrawal
            strategyA =
            new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, NON_ATOMIC_STRATEGY, 2_00, false);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, NON_ATOMIC_STRATEGY);

            strategies = Arrays.toArray(address(strategyA));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory spec = _getSmartVaultSpecification();
            spec.strategies = strategies;
            spec.strategyAllocation = uint16a16.wrap(0).set(0, 100_00);
            spec.assetGroupId = assetGroupId;

            spec.smartVaultName = "SmartVaultA";
            smartVaultA = smartVaultFactory.deploySmartVault(spec);

            spec.smartVaultName = "SmartVaultB";
            smartVaultB = smartVaultFactory.deploySmartVault(spec);
        }

        uint256 depositNftId;
        uint256 withdrawalNftId;

        // round 1 - initial deposit
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
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

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - Alice deposited 100 token A into smart vault A
            //   - 2 token A taken as fees on the protocol level
            //   - 0.000000001 to initial locked shares
            //   - 97.999999999 to smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 1000.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 100.0 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 98.0 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2.0 ether, "protocolA -> fees");

            assertEq(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0],
                0.000000001 ether,
                "strategyA asset balance -> initial locked shares"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                97.999999999 ether,
                "strategyA asset balance -> smart vault A"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> treasury fee recipient"
            );
        }

        // round 2.1 - yield + more withdrawals than deposits
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 19.6 ether);
            // - base yield
            strategyA.protocol().donate(4.9 ether);
            // - compound yield
            strategyA.protocol().reward(14.7 ether, address(strategyA));
            vm.stopPrank();

            // deposits + withdrawals
            // - Alice withdraws 1/2 of the strategy worth
            vm.startPrank(alice);
            withdrawalNftId = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: 49_000000000000000000000,
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );
            vm.stopPrank();
            // - Bob deposits 10 token A into smart vault B
            vm.startPrank(bob);
            tokenA.approve(address(smartVaultManager), 10 ether);
            depositNftId = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(10 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 4.9 token A base yield was generated
            //   - 2.45 for withdrawal
            //     - 0.245 as fees
            //     - 2.205 for withdrawal
            //   - 2.45 to legacy users
            //     - 0.245 as fees
            //     - 2.205 to legacy users
            // - 14.7 token A compound yield was generated
            // - Alice withdrew 50% of the strategy worth
            //   - 51.205 token A (= 49 + 2.205)
            // - Bob deposited 10 token A into smart vault B
            // how to process
            // - compound yield
            //   - 14.7 token A is matched with withdrawal
            //     - 1.47 as fees
            //     - 13.23 to legacy users
            // - deposit
            //   - 10 token A is matched with withdrawal
            // - withdrawal
            //   - 24.7 token A is matched with deposits
            //   - 26.505 token A is withdrawn from protocol
            //     - waits for continuation
            //     - still attributed to the strategy
            // how to distribute
            // - 24.7 token A as Alice's withdrawal on master wallet
            // - 38.465 token A for strategy A
            //   - 10 is reserved for matched deposits
            //   - 0.245 is reserved for withdrawal fees
            //   - 1.715 (= 0.245 + 1.47) is reserved as legacy fees
            //   - 26.505 as pending divestment
            // - 64.435 token A (= 98 - 49 + 2.205 + 13.23) for smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 990.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 24.7 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 104.9 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 102.9 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2 ether, "protocolA -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                102.9 ether,
                1e7,
                "protocolA asset balance -> strategyA"
            );
            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().pendingDivestments(address(strategyA)), address(strategyA.protocol())
                ),
                26.505 ether,
                1e7,
                "protocolA pending divestment -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                64.435 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                38.465 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }

        // round 2.2 - DHW continuation + yield
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 5.145 ether);
            // - base yield
            strategyA.protocol().donate(5.145 ether);
            vm.stopPrank();

            // DHW, sync
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim
            // - withdrawal by Alice
            vm.startPrank(alice);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
            // - deposit by Bob
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 5.145 token A base yield was generated
            //   - 3.22175 for legacy users
            //   - 1.32525 for withdrawn withdrawals
            //   - 0.5 for matched deposits
            //   - 0.01225 for withdrawal fees
            //   - 0.08575 for legacy fees
            // - 27.273645 token A withdrawal from protocol finished
            //   - 26.505 is withdrawn from protocol
            //   - 1.32525 base yield on continuation
            //   - 0.556605 is taken as protocol fees
            //   - no fees are taken for yield
            // how to process
            //   - legacy users
            //     - 49 token A base
            //     - 20.4575 token A yield
            //       - 2.45 base yield on DHW
            //       - 14.7 matched compound yield
            //       - 3.3075 (= 3.22175 + 0.08575) base yield on continuation
            //     - 2.04575 token A is taken as legacy fees
            // - deposits
            //   - 10 token A is matched with withdrawal
            //   - 0.5 token A base yield on continuation
            //   - 0.05 token A is taken as deposit fees
            // - fees
            //   - 2.04575 token A as legacy fees
            //   - 0.25725 token A as withdrawal fees
            //     - 0.245 on DHW
            //     - 0.01225 base yield on continuation
            //   - 0.05 token A as deposit fees
            // - fees on protocol level
            //   - 2 token A in step 1
            //   - 0.556605 token A in step 2
            // - withdrawal
            //   - 24.7 token A is matched with deposits
            //   - 27.273645 token A is withdrawn from protocol
            // how to distribute
            // - 67.41175 token A for smart vault A
            // - 10.45 token A for smart vault B
            // - 2.353 token A for fees
            //   - 1.4118 to ecosystem fee recipient
            //   - 0.9412 to treasury fee recipient
            // - 2.556605 token A for fees on protocol level
            // - 51.973645 token A for Alice's withdrawal

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 951.973645 ether, 1, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 990.0 ether, 1, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0.0 ether, 1, "tokenA -> MasterWallet");
            assertApproxEqAbs(
                tokenA.balanceOf(address(strategyA.protocol())), 82.771355 ether, 1, "tokenA -> protocolA"
            );
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 80.21475 ether, 1, "protocolA -> totalUnderlying");
            assertApproxEqAbs(strategyA.protocol().fees(), 2.556605 ether, 1, "protocolA -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                80.21475 ether,
                1,
                "protocolA asset balance -> strategyA"
            );
            assertApproxEqAbs(
                strategyA.protocol().pendingInvestments(address(strategyA)),
                0 ether,
                1,
                "protocolA pending investments -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                67.41175 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                10.45 ether,
                1e7,
                "strategyA asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                1.4118 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.9412 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }
    }

    function test_nonAtomicStrategyFlow_nonAtomic_equal1() public {
        // setup asset group with token A
        uint256 assetGroupId;
        address[] memory assetGroup;
        {
            assetGroup = Arrays.toArray(address(tokenA));
            assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategyNonAtomic strategyA;
        address[] memory strategies;
        {
            // strategy A implements non-atomic strategy with
            // both deposits and withdrawals being non-atomic
            strategyA =
            new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, NON_ATOMIC_STRATEGY, 2_00, true);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, NON_ATOMIC_STRATEGY);

            strategies = Arrays.toArray(address(strategyA));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory spec = _getSmartVaultSpecification();
            spec.strategies = strategies;
            spec.strategyAllocation = uint16a16.wrap(0).set(0, 100_00);
            spec.assetGroupId = assetGroupId;

            spec.smartVaultName = "SmartVaultA";
            smartVaultA = smartVaultFactory.deploySmartVault(spec);

            spec.smartVaultName = "SmartVaultB";
            smartVaultB = smartVaultFactory.deploySmartVault(spec);
        }

        uint256 depositNftId;
        uint256 withdrawalNftId;

        // round 1 - initial deposit
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
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

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - Alice deposited 100 token A into smart vault A
            //   - 2 token A taken as fees on the protocol level
            //   - 0.000000001 to initial locked shares
            //   - 97.999999999 to smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 1000.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 100.0 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 98.0 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2.0 ether, "protocolA -> fees");

            assertEq(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0],
                0.000000001 ether,
                "strategyA asset balance -> initial locked shares"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                97.999999999 ether,
                "strategyA asset balance -> smart vault A"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> treasury fee recipient"
            );
        }

        // round 2 - yield + equal deposits and withdrawals
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 19.6 ether);
            // - base yield
            strategyA.protocol().donate(4.9 ether);
            // - compound yield
            strategyA.protocol().reward(14.7 ether, address(strategyA));
            vm.stopPrank();

            // deposits + withdrawals
            // - Alice withdraws 1/2 of the strategy worth
            vm.startPrank(alice);
            withdrawalNftId = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: 49_000000000000000000000,
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );
            // Bob deposits 36.505 token A into smart vault B
            vm.startPrank(bob);
            tokenA.approve(address(smartVaultManager), 36.505 ether);
            depositNftId = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(36.505 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();

            // claim
            // - withdrawal by Alice
            vm.startPrank(alice);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
            // - deposit by Bob
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 4.9 token A base yield was generated
            //   - 0.49 as fees
            //   - 4.41 to existing shares
            // - 14.7 token A compound yield was generated
            // - Alice withdrew 50% of the strategy worth
            //   - 51.205 token A (= 49 + 2.205)
            // - Bob deposited 36.505 token A into smart vault B
            // how to process
            // - compound yield
            //   - 14.7 token A (full amount) is matched with withdrawal
            //     - 1.47 as fees
            //     - 13.23 to legacy users
            // - deposit
            //   - 36.505 token A (full amount) is matched with withdrawal
            // - withdrawal
            //   - 51.205 token A (full amount) is matched with deposits
            // how to distribute
            // - 51.205 token A as Alice's withdrawal
            // - 36.505 token A as smart vault B's deposit
            // - 0 token A as protocol fees
            // - 1.96 token A (= 0.49 + 1.47) as fees
            //   - 1.176 to ecosystem fee recipient
            //   - 0.784 to treasury fee recipient
            // - 64.435 token A (= 98 + 4.41 - 51.205 + 13.23) for smart vault A
            // - 36.505 token A for smart vault B

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 951.205 ether, 1, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 963.495 ether, 1, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0 ether, 1, "tokenA -> MasterWallet");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyA.protocol())), 104.9 ether, 1, "tokenA -> protocolA");
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 102.9 ether, 1, "protocolA -> totalUnderlying");
            assertApproxEqAbs(strategyA.protocol().fees(), 2.0 ether, 1, "protocolA -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                102.9 ether,
                1,
                "protocolA asset balance -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                64.435 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                36.505 ether,
                1e7,
                "strategyA asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                1.176 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.784 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }

        // round 3 - base yield only
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 5.145 ether);
            // - base yield
            strategyA.protocol().donate(5.145 ether);
            vm.stopPrank();

            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 5.145 token A base yield was generated
            //   - 0.098 to fees recipients
            //   - 3.22175 for smart vault A
            //     - 0.322175 to fees
            //     - 2.899575 to smart vault A
            //   - 1.82525 for smart vault B
            //     - 0.182525 to fees
            //     - 1.642725 to smart vault B
            // new state
            // - 2.5627 token A (= 1.96 + 0.098 + 0.322175 + 0.182525) as fees
            //   - 1.53762 to ecosystem fee recipient
            //   - 1.02508 to treasury fee recipient
            // - 67.334575 token A (= 64.435 + 2.899575) for smart vault A
            // - 38.147725 token A (= 36.505 + 1.642725) for smart vault B

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 951.205 ether, 1, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 963.495 ether, 1, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0 ether, 1, "tokenA -> MasterWallet");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyA.protocol())), 110.045 ether, 1, "tokenA -> protocolA");
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 108.045 ether, 1, "protocolA -> totalUnderlying");
            assertApproxEqAbs(strategyA.protocol().fees(), 2.0 ether, 1, "protocolA -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                108.045 ether,
                1,
                "protocolA asset balance -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                67.334575 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                38.147725 ether,
                1e7,
                "strategyA asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                1.53762 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                1.02508 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }
    }

    function test_nonAtomicStrategyFlow_nonAtomic_equal2() public {
        // setup asset group with token A
        uint256 assetGroupId;
        address[] memory assetGroup;
        {
            assetGroup = Arrays.toArray(address(tokenA));
            assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategyNonAtomic strategyA;
        address[] memory strategies;
        {
            // strategy A implements non-atomic strategy with
            // both deposits and withdrawals being non-atomic
            strategyA =
            new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, NON_ATOMIC_STRATEGY, 2_00, true);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, NON_ATOMIC_STRATEGY);

            strategies = Arrays.toArray(address(strategyA));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory spec = _getSmartVaultSpecification();
            spec.strategies = strategies;
            spec.strategyAllocation = uint16a16.wrap(0).set(0, 100_00);
            spec.assetGroupId = assetGroupId;

            spec.smartVaultName = "SmartVaultA";
            smartVaultA = smartVaultFactory.deploySmartVault(spec);

            spec.smartVaultName = "SmartVaultB";
            smartVaultB = smartVaultFactory.deploySmartVault(spec);
        }

        uint256 depositNftId1;
        uint256 depositNftId2;
        uint256 withdrawalNftId;

        // round 1 - initial deposit + second deposit flushed
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId1 = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(100 ether),
                    receiver: alice,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW
            smartVaultManager.flushSmartVault(address(smartVaultA));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();

            // Bob deposits 36.505 token A into smart vault B
            vm.startPrank(bob);
            tokenA.approve(address(smartVaultManager), 36.505 ether);
            depositNftId2 = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(36.505 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultB));

            // continue DHW, sync
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId1), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - Alice deposited 100 token A into smart vault A
            //   - 2 token A taken as fees on the protocol level
            //   - 0.000000001 to initial locked shares
            //   - 97.999999999 to smart vault A
            // - Bob deposited 36.505 token A into smart vault B
            //   - 36.505 should be on master wallet

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 963.495 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 36.505 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 100.0 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 98.0 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2.0 ether, "protocolA -> fees");

            assertEq(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0],
                0.000000001 ether,
                "strategyA asset balance -> initial locked shares"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                97.999999999 ether,
                "strategyA asset balance -> smart vault A"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> treasury fee recipient"
            );
        }

        // round 2 - yield + withdrawal equal to deposits
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 19.6 ether);
            // - base yield
            strategyA.protocol().donate(4.9 ether);
            // - compound yield
            strategyA.protocol().reward(14.7 ether, address(strategyA));
            vm.stopPrank();

            // deposits + withdrawals
            // - Alice withdraws 1/2 of the strategy worth
            vm.startPrank(alice);
            withdrawalNftId = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: 49_000000000000000000000,
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();

            // claim
            // - withdrawal by Alice
            vm.startPrank(alice);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
            // - deposit by Bob
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftId2), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 4.9 token A base yield was generated
            //   - 0.49 as fees
            //   - 4.41 to existing shares
            // - 14.7 token A compound yield was generated
            // - Alice withdrew 50% of the strategy worth
            //   - 51.205 token A (= 49 + 2.205)
            // - Bob deposited 36.505 token A into smart vault B
            //   - went into effect from previous round
            // how to process
            // - compound yield
            //   - 14.7 token A (full amount) is matched with withdrawal
            //     - 1.47 as fees
            //     - 13.23 to legacy users
            // - deposit
            //   - 36.505 token A (full amount) is matched with withdrawal
            // - withdrawal
            //   - 51.205 token A (full amount) is matched with deposits
            // how to distribute
            // - 51.205 token A as Alice's withdrawal
            // - 36.505 token A as smart vault B's deposit
            // - 0 token A as protocol fees
            // - 1.96 token A (= 0.49 + 1.47) as fees
            //   - 1.176 to ecosystem fee recipient
            //   - 0.784 to treasury fee recipient
            // - 64.435 token A (= 98 + 4.41 - 51.205 + 13.23) for smart vault A
            // - 36.505 token A for smart vault B

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 951.205 ether, 1, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 963.495 ether, 1, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0 ether, 1, "tokenA -> MasterWallet");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyA.protocol())), 104.9 ether, 1, "tokenA -> protocolA");
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 102.9 ether, 1, "protocolA -> totalUnderlying");
            assertApproxEqAbs(strategyA.protocol().fees(), 2.0 ether, 1, "protocolA -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                102.9 ether,
                1,
                "protocolA asset balance -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                64.435 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                36.505 ether,
                1e7,
                "strategyA asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                1.176 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.784 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }
    }

    function test_nonAtomicStrategyFlow_nonAtomic_redeemStrategySharesAsync() public {
        // setup asset group with token A
        uint256 assetGroupId;
        address[] memory assetGroup;
        {
            assetGroup = Arrays.toArray(address(tokenA));
            assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategyNonAtomic strategyA;
        address[] memory strategies;
        {
            // strategy A implements non-atomic strategy with
            // both deposits and withdrawals being non-atomic
            strategyA =
            new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, NON_ATOMIC_STRATEGY, 2_00, true);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, NON_ATOMIC_STRATEGY);

            strategies = Arrays.toArray(address(strategyA));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        {
            SmartVaultSpecification memory spec = _getSmartVaultSpecification();
            spec.strategies = strategies;
            spec.strategyAllocation = uint16a16.wrap(0).set(0, 100_00);
            spec.assetGroupId = assetGroupId;

            spec.smartVaultName = "SmartVaultA";
            smartVaultA = smartVaultFactory.deploySmartVault(spec);
        }

        uint256 depositNftId;

        // round 1 - initial deposit
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
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

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // round 2 - yield
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 4.9 ether);
            // - base yield
            strategyA.protocol().donate(4.9 ether);
            vm.stopPrank();

            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - round 1
            //   - Alice deposited 100 token A into smart vault A
            // - round 2
            //   - 4.9 token A base yield was generated
            // how to process
            //   - 100 token A deposit
            //     - 2 token A as fees on protocol level
            //     - 98 token A to smart vault A
            //   - 4.9 token A base yield
            //     - 4.41 token A to smart vault A
            //     - 0.49 token A as fees
            // how to distribute
            //   - 2 token A as fees on protocol level
            //   - 102.41 token A for smart vault A
            //   - 0.49 token A for fees
            //     - 0.294 to ecosystem fee recipient
            //     - 0.196 to treasury fee recipient

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0.0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 104.9 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 102.9 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2.0 ether, "protocolA -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                102.9 ether,
                1e7,
                "protocolA asset balance -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                102.41 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0.294 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.196 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }

        // round 3 - redeem strategy shares + yield
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 5.145 ether);
            // - base yield
            strategyA.protocol().donate(5.145 ether);
            vm.stopPrank();

            // redeem strategy shares
            // - ecosystem fee recipient redeems all their current shares
            vm.startPrank(ecosystemFeeRecipient);
            strategyRegistry.redeemStrategySharesAsync(
                Arrays.toArray(address(strategyA)), Arrays.toArray(strategyA.balanceOf(ecosystemFeeRecipient))
            );
            vm.stopPrank();
            // - treasury fee recipient redeems all their current shares
            vm.startPrank(treasuryFeeRecipient);
            strategyRegistry.redeemStrategySharesAsync(
                Arrays.toArray(address(strategyA)), Arrays.toArray(strategyA.balanceOf(treasuryFeeRecipient))
            );
            vm.stopPrank();

            uint256 strategyDhwIndex = strategyRegistry.currentIndex(Arrays.toArray(address(strategyA)))[0];

            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategies, assetGroup));
            vm.stopPrank();

            // claim
            // - ecosystem fee recipient claims their rewards
            vm.startPrank(ecosystemFeeRecipient);
            strategyRegistry.claimStrategyShareWithdrawals(
                Arrays.toArray(address(strategyA)), Arrays.toArray(strategyDhwIndex), ecosystemFeeRecipient
            );
            vm.stopPrank();
            // - treasury fee recipient claims their rewards
            vm.startPrank(treasuryFeeRecipient);
            strategyRegistry.claimStrategyShareWithdrawals(
                Arrays.toArray(address(strategyA)), Arrays.toArray(strategyDhwIndex), treasuryFeeRecipient
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 5.145 token A base yield was generated
            // - ecosystem fee recipient redeemed all their shares
            // - treasury fee recipient redeemed all their shares
            // how to process
            // - 5.145 token A base yield
            //   - 4.6305 to current users
            //     - 4.60845 to smart vault A
            //     - 0.01323 to ecosystem fee recipient
            //     - 0.00882 to treasury fee recipient
            //   - 0.5145 for fees
            //     - 0.3087 to ecosystem fee recipient
            //     - 0.2058 to treasury fee recipient
            // - 0.51205 token A is withdrawn from protocol
            //   - 0.30723 (= 0.294 + 0.01323) by ecosystem fee recipient
            //   - 0.20482 (= 0.196 + 0.00882) by treasury fee recipient
            //   - 0.010241 as fees on protocol level
            //   - 0.501809 for withdrawals
            //     - 0.3010854 for ecosystem fee recipient
            //     - 0.2007236 for treasury fee recipient
            // how to distribute
            // - 107.01845 token A (= 102.41 + 4.60845) for smart vault A
            // - 0.5145 token A for fees
            //   - 0.3087 to ecosystem fee recipient
            //   - 0.2058 to treasury fee recipient
            // - 0.3010854 token A withdrawn by ecosystem fee recipient
            // - 0.2007236 token A withdrawn by treasury fee recipient
            // - 2.010241 token A as fees on protocol level

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 900.0 ether, 1, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0.0 ether, 1, "tokenA -> MasterWallet");
            assertApproxEqAbs(
                tokenA.balanceOf(address(strategyA.protocol())), 109.543191 ether, 1, "tokenA -> protocolA"
            );
            assertApproxEqAbs(
                tokenA.balanceOf(ecosystemFeeRecipient), 0.3010854 ether, 1, "tokenA -> ecosystemFeeRecipient"
            );
            assertApproxEqAbs(
                tokenA.balanceOf(treasuryFeeRecipient), 0.2007236 ether, 1, "tokenA -> treasuryFeeRecipient"
            );
            assertApproxEqAbs(
                strategyA.protocol().totalUnderlying(), 107.53295 ether, 1, "protocolA -> totalUnderlying"
            );
            assertApproxEqAbs(strategyA.protocol().fees(), 2.010241 ether, 1, "protocolA -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                107.53295 ether,
                1e7,
                "protocolA asset balance -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                107.01845 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0.3087 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.2058 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }

        uint256 strategyDhwIndex;

        // round 4 - deposit + redeem strategy shares start - no yield
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(100 ether),
                    receiver: alice,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW
            smartVaultManager.flushSmartVault(address(smartVaultA));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();

            // redeem strategy shares
            // - ecosystem fee recipient redeems all their current shares
            strategyDhwIndex = strategyRegistry.currentIndex(Arrays.toArray(address(strategyA)))[0];
            vm.startPrank(ecosystemFeeRecipient);
            strategyRegistry.redeemStrategySharesAsync(
                Arrays.toArray(address(strategyA)), Arrays.toArray(strategyA.balanceOf(ecosystemFeeRecipient))
            );
            vm.stopPrank();

            // DHW continue, sync
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategies, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - Alice deposited 100 token A into smart vault A
            // - ecosystem fee recipient redeemed all their shares
            // how to process
            // - deposit
            //   - 100 token A deposited
            //     - 2 token A taken as fees on protocol level
            //     - 98 token A to smart vault A
            // - redeemal
            //   - 0.3087 token A worth
            //     - waits as shares on strategy level

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 800.0 ether, 1, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0.0 ether, 1, "tokenA -> MasterWallet");
            assertApproxEqAbs(
                tokenA.balanceOf(address(strategyA.protocol())), 209.543191 ether, 1, "tokenA -> protocolA"
            );
            assertApproxEqAbs(
                tokenA.balanceOf(ecosystemFeeRecipient), 0.3010854 ether, 1, "tokenA -> ecosystemFeeRecipient"
            );
            assertApproxEqAbs(
                tokenA.balanceOf(treasuryFeeRecipient), 0.2007236 ether, 1, "tokenA -> treasuryFeeRecipient"
            );
            assertApproxEqAbs(
                strategyA.protocol().totalUnderlying(), 205.53295 ether, 1, "protocolA -> totalUnderlying"
            );
            assertApproxEqAbs(strategyA.protocol().fees(), 4.010241 ether, 1, "protocolA -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                205.53295 ether,
                1e7,
                "protocolA asset balance -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                205.01845 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.2058 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0.3087 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }

        // round 5 - finish redeem strategy shares - no yield
        {
            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategies, assetGroup));
            vm.stopPrank();

            // claim
            // - ecosystem fee recipient claims their rewards
            vm.startPrank(ecosystemFeeRecipient);
            strategyRegistry.claimStrategyShareWithdrawals(
                Arrays.toArray(address(strategyA)), Arrays.toArray(strategyDhwIndex), ecosystemFeeRecipient
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - ecosystem fee recipient redeemed all their shares - finished
            //   - 0.3087 token A worth
            // how to process
            // - redeemal
            //   - 0.3087 token A withdrawn
            //     - 0.006174 for fees on protocol level
            //     - 0.302526 for ecosystem fee recipient

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 800.0 ether, 3, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0.0 ether, 3, "tokenA -> MasterWallet");
            assertApproxEqAbs(
                tokenA.balanceOf(address(strategyA.protocol())), 209.240665 ether, 3, "tokenA -> protocolA"
            );
            assertApproxEqAbs(
                tokenA.balanceOf(ecosystemFeeRecipient), 0.6036114 ether, 3, "tokenA -> ecosystemFeeRecipient"
            );
            assertApproxEqAbs(
                tokenA.balanceOf(treasuryFeeRecipient), 0.2007236 ether, 3, "tokenA -> treasuryFeeRecipient"
            );
            assertApproxEqAbs(
                strategyA.protocol().totalUnderlying(), 205.22425 ether, 3, "protocolA -> totalUnderlying"
            );
            assertApproxEqAbs(strategyA.protocol().fees(), 4.016415 ether, 3, "protocolA -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                205.22425 ether,
                1e7,
                "protocolA asset balance -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                205.01845 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.2058 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0.0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
        }
    }

    function test_nonAtomicStrategyFlow_nonAtomic_redeemStrategyShares() public {
        // setup asset group with token A
        uint256 assetGroupId;
        address[] memory assetGroup;
        {
            assetGroup = Arrays.toArray(address(tokenA));
            assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategyNonAtomic strategyA;
        MockStrategyNonAtomic strategyB;
        {
            // strategy A implements non-atomic strategy with
            // atomic deposits and non-atomic withdrawals
            strategyA =
            new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, NON_ATOMIC_WITHDRAWAL_STRATEGY, 2_00, true);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, NON_ATOMIC_STRATEGY);
            // strategy B implements non-atomic strategy with
            // non-atomic deposits and atomic withdrawals
            strategyB =
            new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, NON_ATOMIC_DEPOSIT_STRATEGY, 2_00, true);
            strategyB.initialize("StratB");
            strategyRegistry.registerStrategy(address(strategyB), 0, NON_ATOMIC_STRATEGY);
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        address[] memory strategiesA;
        address[] memory strategiesB;
        {
            SmartVaultSpecification memory spec = _getSmartVaultSpecification();
            spec.strategyAllocation = uint16a16.wrap(0).set(0, 100_00);
            spec.assetGroupId = assetGroupId;

            spec.strategies = Arrays.toArray(address(strategyA));
            spec.smartVaultName = "SmartVaultA";
            smartVaultA = smartVaultFactory.deploySmartVault(spec);
            strategiesA = spec.strategies;

            spec.strategies = Arrays.toArray(address(strategyB));
            spec.smartVaultName = "SmartVaultB";
            smartVaultB = smartVaultFactory.deploySmartVault(spec);
            strategiesB = spec.strategies;
        }

        uint256 depositNftId1;
        uint256 depositNftId2;

        // round 1 - initial deposit
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId1 = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(100 ether),
                    receiver: alice,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();
            // Bob deposits 100 token A into smart vault B
            vm.startPrank(bob);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId2 = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(100 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategiesA, assetGroup));
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategiesB, assetGroup));
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategiesB, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            // - by Alice
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId1), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
            // - by Bob
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftId2), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // round 2 - yield
        {
            // generate yield
            vm.startPrank(charlie);
            // - strategy A base yield
            tokenA.approve(address(strategyA.protocol()), 4.9 ether);
            strategyA.protocol().donate(4.9 ether);
            // - strategy B base yield
            tokenA.approve(address(strategyB.protocol()), 4.9 ether);
            strategyB.protocol().donate(4.9 ether);
            vm.stopPrank();

            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategiesA, assetGroup));
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategiesB, assetGroup));
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - round 1
            //   - Alice deposited 100 token A into smart vault A
            // - round 2
            //   - 4.9 token A base yield was generated
            // how to process
            //   - 100 token A deposit
            //     - 2 token A as fees on protocol level
            //     - 98 token A to smart vault A
            //   - 4.9 token A base yield to strategy A
            //     - 4.41 token A to smart vault A
            //     - 0.49 token A as fees
            //   - 4.9 token A base yield to strategy B
            //     - 4.41 token A to smart vault B
            //     - 0.49 token A as fees
            // how to distribute
            //   - 2 token A as fees on protocol level
            //   - 2 token B as fees on protocol level
            //   - 102.41 token A for smart vault A
            //   - 102.41 token A for smart vault B
            //   - 0.49 token A for fees on strategy A
            //     - 0.294 to ecosystem fee recipient
            //     - 0.196 to treasury fee recipient
            //   - 0.49 token A for fees on strategy B
            //     - 0.294 to ecosystem fee recipient
            //     - 0.196 to treasury fee recipient

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 900.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0.0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 104.9 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 102.9 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2.0 ether, "protocolA -> fees");
            assertEq(tokenA.balanceOf(address(strategyB.protocol())), 104.9 ether, "tokenA -> protocolB");
            assertEq(strategyB.protocol().totalUnderlying(), 102.9 ether, "protocolB -> totalUnderlying");
            assertEq(strategyB.protocol().fees(), 2.0 ether, "protocolB -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                102.9 ether,
                1e7,
                "protocolA asset balance -> strategyA"
            );
            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyB.protocol().shares(address(strategyB)), address(strategyB.protocol())
                ),
                102.9 ether,
                1e7,
                "protocolB asset balance -> strategyB"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                102.41 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0.294 ether,
                1e7,
                "strategyA asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.196 ether,
                1e7,
                "strategyA asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyB))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultB), address(strategyB))[0],
                102.41 ether,
                1e7,
                "strategyB asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyB))[0],
                0.294 ether,
                1e7,
                "strategyB asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyB))[0],
                0.196 ether,
                1e7,
                "strategyB asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyB), address(strategyB))[0],
                0 ether,
                1e7,
                "strategyB asset balance -> strategyB"
            );
        }

        address[] memory strategies;
        uint256[] memory shares;
        uint256[][] memory withdrawalSlippages;

        // round 3 - redeem strategy shares
        {
            // ecosystem recipient from strategy A
            strategies = strategiesA;
            shares = Arrays.toArray(strategyA.balanceOf(ecosystemFeeRecipient));
            withdrawalSlippages = new uint256[][](1);
            // - should revert due to non-atomic withdrawal
            vm.startPrank(ecosystemFeeRecipient);
            vm.expectRevert(abi.encodeWithSelector(ProtocolActionNotFinished.selector));
            strategyRegistry.redeemStrategyShares(strategies, shares, withdrawalSlippages);
            vm.stopPrank();

            // ecosystem recipient from strategy B
            strategies = strategiesB;
            shares = Arrays.toArray(strategyB.balanceOf(ecosystemFeeRecipient));
            withdrawalSlippages = new uint256[][](1);
            vm.startPrank(ecosystemFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategies, shares, withdrawalSlippages);
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - ecosystem fee recipient withdrew all their shares from strategy B
            //   - 0.294 token A
            // how to distribute
            // - 0.294 token A withdrawn from protocol B
            //   - 0.00588 as fees on protocol level
            //   - 0.28812 for ecosystem fee recipient

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0.0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 104.9 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 102.9 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2.0 ether, "protocolA -> fees");
            assertEq(tokenA.balanceOf(address(strategyB.protocol())), 104.61188 ether, "tokenA -> protocolB");
            assertApproxEqAbs(strategyB.protocol().totalUnderlying(), 102.606 ether, 1, "protocolB -> totalUnderlying");
            assertApproxEqAbs(strategyB.protocol().fees(), 2.00588 ether, 1, "protocolB -> fees");
            assertApproxEqAbs(
                tokenA.balanceOf(ecosystemFeeRecipient), 0.28812 ether, 1, "tokenA -> ecosystemFeeRecipient"
            );

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyB.protocol().shares(address(strategyB)), address(strategyB.protocol())
                ),
                102.606 ether,
                1e7,
                "protocolB asset balance -> strategyB"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyB))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultB), address(strategyB))[0],
                102.41 ether,
                1e7,
                "strategyB asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyB))[0],
                0.0 ether,
                1e7,
                "strategyB asset balance -> ecosystem fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyB))[0],
                0.196 ether,
                1e7,
                "strategyB asset balance -> treasury fee recipient"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyB), address(strategyB))[0],
                0 ether,
                1e7,
                "strategyB asset balance -> strategyB"
            );
        }

        // round 4 - deposit + redeem strategy shares
        {
            // Alice deposits 100 token A into smart vault B
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId1 = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(100 ether),
                    receiver: alice,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategiesB, assetGroup));
            vm.stopPrank();

            // redeem strategy shares
            // - treasury fee recipient from strategy B
            strategies = strategiesB;
            shares = Arrays.toArray(strategyB.balanceOf(treasuryFeeRecipient));
            withdrawalSlippages = new uint256[][](1);
            //   - should revert due to unfinished DHW
            vm.startPrank(treasuryFeeRecipient);
            vm.expectRevert(abi.encodeWithSelector(StrategyNotReady.selector, address(strategyB)));
            strategyRegistry.redeemStrategyShares(strategies, shares, withdrawalSlippages);
            vm.stopPrank();
        }
    }

    function test_nonAtomicStrategyFlow_nonAtomic_redeemFast() public {
        // setup asset group with token A
        uint256 assetGroupId;
        address[] memory assetGroup;
        {
            assetGroup = Arrays.toArray(address(tokenA));
            assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategyNonAtomic strategyA;
        MockStrategyNonAtomic strategyB;
        {
            // strategy A implements non-atomic strategy with
            // atomic deposits and non-atomic withdrawals
            strategyA =
            new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, NON_ATOMIC_WITHDRAWAL_STRATEGY, 2_00, true);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, NON_ATOMIC_STRATEGY);
            // strategy B implements non-atomic strategy with
            // non-atomic deposits and atomic withdrawals
            strategyB =
            new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, NON_ATOMIC_DEPOSIT_STRATEGY, 2_00, true);
            strategyB.initialize("StratB");
            strategyRegistry.registerStrategy(address(strategyB), 0, NON_ATOMIC_STRATEGY);
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        address[] memory strategiesA;
        address[] memory strategiesB;
        {
            SmartVaultSpecification memory spec = _getSmartVaultSpecification();
            spec.strategyAllocation = uint16a16.wrap(0).set(0, 100_00);
            spec.assetGroupId = assetGroupId;

            spec.strategies = Arrays.toArray(address(strategyA));
            spec.smartVaultName = "SmartVaultA";
            smartVaultA = smartVaultFactory.deploySmartVault(spec);
            strategiesA = spec.strategies;

            spec.strategies = Arrays.toArray(address(strategyB));
            spec.smartVaultName = "SmartVaultB";
            smartVaultB = smartVaultFactory.deploySmartVault(spec);
            strategiesB = spec.strategies;
        }

        uint256 depositNftId1;
        uint256 depositNftId2;

        // round 1 - initial deposit
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId1 = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(100 ether),
                    receiver: alice,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();
            // Bob deposits 100 token A into smart vault B
            vm.startPrank(bob);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId2 = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(100 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategiesA, assetGroup));
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategiesB, assetGroup));
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategiesB, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            // - by Alice
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId1), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
            // - by Bob
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftId2), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - Alice deposited 100 token A into smart vault A
            // how to process
            //   - 100 token A deposit
            //     - 2 token A as fees on protocol level
            //     - 98 token A to smart vault A
            // how to distribute
            //   - 2 token A as fees on protocol level
            //   - 2 token B as fees on protocol level
            //   - 98 token A for smart vault A
            //   - 98 token A for smart vault B

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 900.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0.0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 100.0 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 98.0 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2.0 ether, "protocolA -> fees");
            assertEq(tokenA.balanceOf(address(strategyB.protocol())), 100.0 ether, "tokenA -> protocolB");
            assertEq(strategyB.protocol().totalUnderlying(), 98.0 ether, "protocolB -> totalUnderlying");
            assertEq(strategyB.protocol().fees(), 2.0 ether, "protocolB -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                98.0 ether,
                1e7,
                "protocolA asset balance -> strategyA"
            );
            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyB.protocol().shares(address(strategyB)), address(strategyB.protocol())
                ),
                98.0 ether,
                1e7,
                "protocolB asset balance -> strategyB"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                98.0 ether,
                1e7,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0 ether,
                1e7,
                "strategyA asset balance -> strategyA"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyB))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultB), address(strategyB))[0],
                98 ether,
                1e7,
                "strategyB asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyB), address(strategyB))[0],
                0 ether,
                1e7,
                "strategyB asset balance -> strategyB"
            );
        }

        RedeemBag memory redeemBag;
        uint256[][] memory withdrawalSlippages = new uint256[][](1);

        // round 2 - redeem fast
        {
            // Alice withdraws 1/2 of the strategy worth from smart vault A
            redeemBag = RedeemBag({
                smartVault: address(smartVaultA),
                shares: 49_000000000000000000000,
                nftIds: new uint256[](0),
                nftAmounts: new uint256[](0)
            });
            // - should revert due to non-atomic withdrawal
            vm.startPrank(alice);
            vm.expectRevert(abi.encodeWithSelector(ProtocolActionNotFinished.selector));
            smartVaultManager.redeemFast(redeemBag, withdrawalSlippages);
            vm.stopPrank();
            // Bob withdraws 1/2 of the strategy worth from smart vault B
            redeemBag = RedeemBag({
                smartVault: address(smartVaultB),
                shares: 49_000000000000000000000,
                nftIds: new uint256[](0),
                nftAmounts: new uint256[](0)
            });
            vm.startPrank(bob);
            smartVaultManager.redeemFast(redeemBag, withdrawalSlippages);
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - Bob withdrew 49 token A from smart vault B
            // how to distribute
            // - 49 token A withdrawn from protocol B
            //   - 0.98 as fees on protocol level
            //   - 48.02 for Bob

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 948.02 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0.0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 100.0 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 98.0 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 2.0 ether, "protocolA -> fees");
            assertEq(tokenA.balanceOf(address(strategyB.protocol())), 51.98 ether, "tokenA -> protocolB");
            assertEq(strategyB.protocol().totalUnderlying(), 49.0 ether, "protocolB -> totalUnderlying");
            assertEq(strategyB.protocol().fees(), 2.98 ether, "protocolB -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyB.protocol().shares(address(strategyB)), address(strategyB.protocol())
                ),
                49.0 ether,
                1e7,
                "protocolB asset balance -> strategyB"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyB))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultB), address(strategyB))[0],
                49 ether,
                1e7,
                "strategyB asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyB), address(strategyB))[0],
                0 ether,
                1e7,
                "strategyB asset balance -> strategyB"
            );
        }

        // round 3 - deposit + redeem fast
        {
            // Alice deposits 100 token A into smart vault B
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId1 = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(100 ether),
                    receiver: alice,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategiesB, assetGroup));
            vm.stopPrank();

            // redeem fast
            // - Bob withdraws 1/2 of the strategy worth from smart vault B
            redeemBag = RedeemBag({
                smartVault: address(smartVaultB),
                shares: 24_500000000000000000000,
                nftIds: new uint256[](0),
                nftAmounts: new uint256[](0)
            });
            //   - should revert due to unfinished DHW
            vm.startPrank(bob);
            vm.expectRevert(abi.encodeWithSelector(StrategyNotReady.selector, address(strategyB)));
            smartVaultManager.redeemFast(redeemBag, withdrawalSlippages);
            vm.stopPrank();
        }
    }

    function test_nonAtomicStrategyFlow_nonAtomic_reallocation() public {
        // setup asset group with token A
        uint256 assetGroupId;
        address[] memory assetGroup;
        {
            assetGroup = Arrays.toArray(address(tokenA));
            assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        }

        // setup strategies
        MockStrategyNonAtomic strategyA;
        MockStrategyNonAtomic strategyB;
        MockStrategyNonAtomic strategyC;

        address[] memory strategiesAC;
        address[] memory strategiesCB;
        {
            // strategy A implements non-atomic strategy with
            // atomic deposits and non-atomic withdrawals
            strategyA =
            new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, NON_ATOMIC_WITHDRAWAL_STRATEGY, 2_00, true);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, NON_ATOMIC_WITHDRAWAL_STRATEGY);

            // strategy B implements non-atomic strategy with
            // non-atomic deposits and atomic withdrawals
            strategyB =
            new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, NON_ATOMIC_DEPOSIT_STRATEGY, 2_00, true);
            strategyB.initialize("StratB");
            strategyRegistry.registerStrategy(address(strategyB), 0, NON_ATOMIC_DEPOSIT_STRATEGY);

            // strategy C implements non-atomic strategy with
            // atomic deposits and atomic withdrawals
            strategyC =
                new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, ATOMIC_STRATEGY, 2_00, true);
            strategyC.initialize("StratC");
            strategyRegistry.registerStrategy(address(strategyC), 0, ATOMIC_STRATEGY);

            strategiesAC = Arrays.toArray(address(strategyA), address(strategyC));
            strategiesCB = Arrays.toArray(address(strategyC), address(strategyB));
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory spec = _getSmartVaultSpecification();
            spec.assetGroupId = assetGroupId;
            spec.riskTolerance = 4;
            spec.riskProvider = riskProvider;
            spec.allocationProvider = allocationProvider;

            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toUint16a16(60_00, 40_00))
            );

            spec.smartVaultName = "SmartVaultA";
            spec.strategies = strategiesAC;
            smartVaultA = smartVaultFactory.deploySmartVault(spec);

            spec.smartVaultName = "SmartVaultB";
            spec.strategies = strategiesCB;
            smartVaultB = smartVaultFactory.deploySmartVault(spec);
        }

        uint256 depositNftId;

        // round 1 - deposits
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
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

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategiesAC, assetGroup));
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();

            // Bob deposits 100 token A into smart vault B
            vm.startPrank(bob);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(100 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategiesCB, assetGroup));
            strategyRegistry.doHardWorkContinue(
                _generateDhwContinuationParameterBag(Arrays.toArray(address(strategyB)), assetGroup)
            );
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - Alice deposits 100 token A into smart vault A
            //   - 60 to strategy A
            //     - 1.2 as fees on protocol levels
            //   - 40 to strategy B
            //     - 0.8 as fees on protocol levels

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 900.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0.0 ether, "tokenA -> MasterWallet");
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 60.0 ether, "tokenA -> protocolA");
            assertEq(strategyA.protocol().totalUnderlying(), 58.8 ether, "protocolA -> totalUnderlying");
            assertEq(strategyA.protocol().fees(), 1.2 ether, "protocolA -> fees");
            assertEq(tokenA.balanceOf(address(strategyB.protocol())), 40.0 ether, "tokenA -> protocolB");
            assertEq(strategyB.protocol().totalUnderlying(), 39.2 ether, "protocolB -> totalUnderlying");
            assertEq(strategyB.protocol().fees(), 0.8 ether, "protocolB -> fees");
            assertEq(tokenA.balanceOf(address(strategyC.protocol())), 100.0 ether, "tokenA -> protocolC");
            assertEq(strategyC.protocol().totalUnderlying(), 98.0 ether, "protocolC -> totalUnderlying");
            assertEq(strategyC.protocol().fees(), 2.0 ether, "protocolC -> fees");

            assertEq(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                58.8 ether,
                "protocolA asset balance -> strategyA"
            );
            assertEq(
                _getProtocolSharesAssetBalance(
                    strategyB.protocol().shares(address(strategyB)), address(strategyB.protocol())
                ),
                39.2 ether,
                "protocolB asset balance -> strategyB"
            );
            assertEq(
                _getProtocolSharesAssetBalance(
                    strategyC.protocol().shares(address(strategyC)), address(strategyC.protocol())
                ),
                98.0 ether,
                "protocolC asset balance -> strategyC"
            );

            assertEq(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                58.8 ether,
                "strategyA asset balance -> smart vault A"
            );
            assertEq(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyC))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyC))[0],
                39.2 ether,
                "strategyC asset balance -> smart vault A"
            );
            assertEq(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyB))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultB), address(strategyB))[0],
                39.2 ether,
                "strategyB asset balance -> smart vault B"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyC))[0],
                58.8 ether,
                "strategyC asset balance -> smart vault B"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0 ether,
                "strategyA asset balance -> strategyA"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(strategyB), address(strategyB))[0],
                0 ether,
                "strategyB asset balance -> strategyB"
            );
            assertEq(
                _getStrategySharesAssetBalances(address(strategyC), address(strategyC))[0],
                0 ether,
                "strategyC asset balance -> strategyC"
            );
        }

        ReallocateParamBag memory reallocateParamBag;

        // round 2 - reallocation
        {
            // - strategy A: non-atomic withdrawals, atomic deposits
            // - strategy B: non-atomic deposits, atomic withdrawals
            // - strategy C: atomic deposits and withdrawals

            // - smart vault A
            //   - current allocation: 60% to strategy A, 40% to strategy C
            //   - new allocation: 50% to strategy A, 50% to strategy C
            //   -> withdraw from strategy A, deposit to strategy C
            //   -> should revert due to non-atomic withdrawal
            // - smart vault B
            //   - current allocation: 60% to strategy C, 40% to strategy B
            //   - new allocation: 50% to strategy C, 50% to strategy B
            //   -> withdraw from strategy C, deposit to strategy B
            //   -> should revert due to non-atomic deposit
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toUint16a16(50_00, 50_00))
            );

            // - reallocate smart vault A
            reallocateParamBag =
                _generateReallocateParamBag(Arrays.toArray(address(smartVaultA)), strategiesAC, assetGroup);
            vm.startPrank(reallocator);
            vm.expectRevert(abi.encodeWithSelector(ProtocolActionNotFinished.selector));
            smartVaultManager.reallocate(reallocateParamBag);
            vm.stopPrank();

            // - reallocate smart vault B
            reallocateParamBag =
                _generateReallocateParamBag(Arrays.toArray(address(smartVaultB)), strategiesCB, assetGroup);
            vm.startPrank(reallocator);
            vm.expectRevert(abi.encodeWithSelector(ProtocolActionNotFinished.selector));
            smartVaultManager.reallocate(reallocateParamBag);
            vm.stopPrank();

            // - smart vault A
            //   - current allocation: 60% to strategy A, 40% to strategy C
            //   - new allocation: 70% to strategy A, 30% to strategy C
            //   -> withdraw from strategy C, deposit to strategy A
            //   -> should pass
            // - smart vault B
            //   - current allocation: 60% to strategy C, 40% to strategy B
            //   - new allocation: 70% to strategy C, 30% to strategy B
            //   -> withdraw from strategy B, deposit to strategy C
            //   -> should pass
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toUint16a16(70_00, 30_00))
            );

            // - reallocate smart vault A
            reallocateParamBag =
                _generateReallocateParamBag(Arrays.toArray(address(smartVaultA)), strategiesAC, assetGroup);
            vm.startPrank(reallocator);
            smartVaultManager.reallocate(reallocateParamBag);
            vm.stopPrank();

            // - reallocate smart vault B
            reallocateParamBag =
                _generateReallocateParamBag(Arrays.toArray(address(smartVaultB)), strategiesCB, assetGroup);
            vm.startPrank(reallocator);
            smartVaultManager.reallocate(reallocateParamBag);
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - smart vault A was reallocated
            //   - A:C = 60:40 -> 70:30
            // - smart vault B was reallocated
            //   - C:B = 60:40 -> 70:30
            // how to process
            //   - smart vault A had
            //     - 58.8 token A in strategy A
            //     - 39.2 token A in strategy C
            //     -> 98 token A in total
            //   - smart vault B had
            //     - 58.8 token A in strategy C
            //     - 39.2 token A in strategy B
            //   - smart vault A should have
            //     - 68.6 token A in strategy A
            //     - 29.4 token A in strategy C
            //     -> withdraw 9.8 token A from strategy C, deposit 9.8 token A to strategy A
            //   - smart vault B should have
            //     - 68.6 token A in strategy C
            //     - 29.4 token A in strategy B
            //     -> withdraw 9.8 token A from strategy B, deposit 9.8 token A to strategy C
            //   - withdrawal and deposit incur 2% fees on protocol level
            //     - 9.8 token A withdrawal -> 0.196 for fees, 9.604 withdrawn
            //     - 9.212 token A deposit -> 0.19208 for fees, 9.41192 deposited
            // how to distribute
            //   - smart vault A
            //     - 68.21192 token A (= 58.8 + 9.41192) in strategy A
            //     - 29.4 (= 39.2 - 9.8) token A in strategy C
            //     - 0.19208 token A as fees for protocol A
            //     - 0.196 token A as fees for protocol C
            //   - smart vault B
            //     - 68.21192 token A (= 58.8 + 9.41192) in strategy C
            //     - 29.4 (= 39.2 - 9.8) token A in strategy B
            //     - 0.19208 token A as fees for protocol C
            //     - 0.196 token A as fees for protocol B
            //   - protocol A
            //     - 68.21192 token A for strategy A
            //     - 1.39208 token A (= 1.2 + 0.19208) for fees
            //     -> 69.604 token A in total
            //   - protocol B
            //     - 29.4 token A for strategy B
            //     - 0.996 token A (= 0.8 + 0.196) for fees
            //     -> 30.396 token A in total
            //   - protocol C
            //     - 97.61192 token A (= 29.4 + 68.21192) for strategy C
            //     - 2.38808 token A (= 2 + 0.196 + 0.19208) for fees
            //     -> 100 token A in total

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether, "tokenA -> Alice");
            assertEq(tokenA.balanceOf(address(bob)), 900.0 ether, "tokenA -> Bob");
            assertEq(tokenA.balanceOf(address(masterWallet)), 0.0 ether, "tokenA -> MasterWallet");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyA.protocol())), 69.604 ether, 1e9, "tokenA -> protocolA");
            assertApproxEqAbs(
                strategyA.protocol().totalUnderlying(), 68.21192 ether, 1e9, "protocolA -> totalUnderlying"
            );
            assertApproxEqAbs(strategyA.protocol().fees(), 1.39208 ether, 1e9, "protocolA -> fees");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyB.protocol())), 30.396 ether, 1e9, "tokenA -> protocolB");
            assertApproxEqAbs(strategyB.protocol().totalUnderlying(), 29.4 ether, 1e9, "protocolB -> totalUnderlying");
            assertApproxEqAbs(strategyB.protocol().fees(), 0.996 ether, 1e9, "protocolB -> fees");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyC.protocol())), 100.0 ether, 1e9, "tokenA -> protocolC");
            assertApproxEqAbs(
                strategyC.protocol().totalUnderlying(), 97.61192 ether, 1e9, "protocolC -> totalUnderlying"
            );
            assertApproxEqAbs(strategyC.protocol().fees(), 2.38808 ether, 1e9, "protocolC -> fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                68.21192 ether,
                1e9,
                "protocolA asset balance -> strategyA"
            );
            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyB.protocol().shares(address(strategyB)), address(strategyB.protocol())
                ),
                29.4 ether,
                1e9,
                "protocolB asset balance -> strategyB"
            );
            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyC.protocol().shares(address(strategyC)), address(strategyC.protocol())
                ),
                97.61192 ether,
                1e9,
                "protocolC asset balance -> strategyC"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                68.21192 ether,
                1e9,
                "strategyA asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyC))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyC))[0],
                29.4 ether,
                1e9,
                "strategyC asset balance -> smart vault A"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyB))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultB), address(strategyB))[0],
                29.4 ether,
                1e9,
                "strategyB asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyC))[0],
                68.21192 ether,
                1e9,
                "strategyC asset balance -> smart vault B"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyA), address(strategyA))[0],
                0 ether,
                1e9,
                "strategyA asset balance -> strategyA"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyB), address(strategyB))[0],
                0 ether,
                1e9,
                "strategyB asset balance -> strategyB"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(strategyC), address(strategyC))[0],
                0 ether,
                1e9,
                "strategyC asset balance -> strategyC"
            );
        }

        // round 3 - deposit + reallocation
        {
            // Alice deposits 100 token A into smart vault B
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftId = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(100 ether),
                    receiver: alice,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategiesCB, assetGroup));
            vm.stopPrank();

            // try to reallocate smart vault B
            // - should fail due to DHW not being finished
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toUint16a16(80_00, 20_00))
            );

            reallocateParamBag =
                _generateReallocateParamBag(Arrays.toArray(address(smartVaultB)), strategiesCB, assetGroup);
            vm.startPrank(reallocator);
            vm.expectRevert(abi.encodeWithSelector(StrategyNotReady.selector, address(strategyB)));
            smartVaultManager.reallocate(reallocateParamBag);
            vm.stopPrank();
        }
    }
}
