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
        accessControl.grantRole(ROLE_DO_HARD_WORKER, doHardWorker);
        ecosystemFeeRecipient = address(0x3);
        treasuryFeeRecipient = address(0x4);
        emergencyWithdrawalRecipient = address(0x5);

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
                new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, ATOMIC_STRATEGY, 2_00);
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
                new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, ATOMIC_STRATEGY, 2_00);
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
                new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, ATOMIC_STRATEGY, 2_00);
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
            //   - 24.7 token A is matched withd deposits
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
            new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, FULLY_NON_ATOMIC_STRATEGY, 2_00);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, FULLY_NON_ATOMIC_STRATEGY);

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
            new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, FULLY_NON_ATOMIC_STRATEGY, 2_00);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, FULLY_NON_ATOMIC_STRATEGY);

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
            new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, FULLY_NON_ATOMIC_STRATEGY, 2_00);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, FULLY_NON_ATOMIC_STRATEGY);

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
            // - how to process
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
}
