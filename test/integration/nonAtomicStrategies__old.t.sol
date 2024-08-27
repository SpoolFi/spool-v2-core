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
import "../mocks/MockStrategy2.sol";
import {
    MockStrategyNonAtomic,
    MockProtocolNonAtomic,
    ProtocolActionNotFinished
} from "../mocks/MockStrategyNonAtomic__old.sol";
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
                new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, FULLY_NON_ATOMIC_STRATEGY);
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
            //   - 0.000000001 to initial locked shares
            //   - 99.999999999 to smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether);
            assertEq(tokenA.balanceOf(address(bob)), 1000.0 ether);
            assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether);
            assertEq(strategyA.protocol().totalUnderlying(), 100.0 ether);

            assertEq(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0], 0.000000001 ether
            );
            assertEq(_getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0], 99.999999999 ether);
            assertEq(_getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0], 0 ether);
            assertEq(_getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0], 0 ether);

            assertEq(strategyA.totalSupply(), 100_000000000000000000000);
            assertEq(strategyA.balanceOf(INITIAL_LOCKED_SHARES_ADDRESS), 1000000000000);
            assertEq(strategyA.balanceOf(address(smartVaultA)), 99_999999999000000000000);
        }

        // round 2.1 - yield + more deposits than withdrawals
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 20 ether);
            // - base yield
            strategyA.protocol().donate(5 ether);
            // - compound yield
            strategyA.protocol().reward(15 ether, address(strategyA));
            vm.stopPrank();

            // deposits + withdrawals
            // - Alice withdraws 1/10th of strategy worth
            vm.startPrank(alice);
            withdrawalNftId = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: 10_000000000000000000000,
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
            // - 5 token A base yield was generated
            // - 15 token A compound yield was generated
            // - Alice withdrew 1/10th of strategy worth
            //   - including base yield, but not compound yield
            //   - 10.45 token A was withdrawn
            //     - 10 from base
            //     - 0.5 from base yield
            //     - -0.05 as fees on base yield -> "withdrawal fees"
            // - 90 token A remained in strategy
            //   - accrued 4.5 from base yield
            //   - accrued 10.45 from matched compound yield
            //   -> 104.95 remains for legacy users
            //     -> 1.495 marked for fees -> "deposit fees"
            //     -> 103.455 marked for users
            // - 100 token A was deposited into smart vault B
            //   - none was matched and all waits for continuation
            // - 4.55 token A from compound yield was unmatched and deposited into the protocol

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 900.0 ether, 1e7, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 900.0 ether, 1e7, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 10.45 ether, 1e7, "tokenA -> MasterWallet");
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 105.0 ether, 1e7, "protocol -> totalUnderlying");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyA.protocol())), 209.55 ether, 1e7, "tokenA -> protocol");

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(strategyA.withdrawalFeeShares(), address(strategyA))[0],
                0.05 ether,
                1e7,
                "strategyAssetBalance -> withdrawal fees"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(strategyA.depositFeeShares(), address(strategyA))[0],
                1.495 ether,
                1e7,
                "strategyAssetBalance -> deposit fees"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(strategyA.userDepositShares(), address(strategyA))[0],
                0 ether,
                1e7,
                "strategyAssetBalance -> user deposits"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                103.455 ether,
                1e7,
                "strategyAssetBalance -> smartVaultA"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                0 ether,
                1e7,
                "strategyAssetBalance -> smartVaultB"
            );
        }

        // round 2.2 - DHW continuation + yield
        {
            // generate yield
            vm.startPrank(charlie);
            // - base yield
            uint256 baseYield = strategyA.protocol().totalUnderlying() * 5 / 100;
            tokenA.approve(address(strategyA.protocol()), baseYield);
            strategyA.protocol().donate(baseYield);
            vm.stopPrank();

            // console.log("baseYield", baseYield);

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
            // - 5% token A base yield was generated
            //   - 5.25
            //     - 0.0025 to withdrawal fees
            //     - 5.2475 to legacy users
            // - 4.55 token A deposited compound yield was finalized
            // - 100 token A deposit was finalized
            // how to distribute
            // - 0.0525 token A as withdrawal fees
            // - 114.7475 token A as legacy users
            //   - 24.7475 as yield
            //     -> 2.47475 as fees
            //   -> 112.27275 remains for legacy users
            // - 100 token A as deposit
            // state
            // - 10.45 token A withdrawn to Alice
            // - 2.52725 token A for fees
            // - 112.27275 token A for legacy users
            // - 100 token A for smart vault B

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 910.45 ether, 1e7, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 900.0 ether, 1e7, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0 ether, 1e7, "tokenA -> MasterWallet");
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 214.8 ether, 1e7, "protocol -> totalUnderlying");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyA.protocol())), 214.8 ether, 1e7, "tokenA -> protocol");

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                112.27275 ether,
                2e7,
                "strategyAssetBalance -> smartVaultA"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                100 ether,
                2e7,
                "strategyAssetBalance -> smartVaultB"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                2.52725 ether,
                2e7,
                "strategyAssetBalance -> fees"
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
                new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, FULLY_NON_ATOMIC_STRATEGY);
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
            //   - 0.000000001 to initial locked shares
            //   - 99.999999999 to smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether);
            assertEq(tokenA.balanceOf(address(bob)), 1000.0 ether);
            assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether);
            assertEq(strategyA.protocol().totalUnderlying(), 100.0 ether);

            assertEq(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0], 0.000000001 ether
            );
            assertEq(_getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0], 99.999999999 ether);
            assertEq(_getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0], 0 ether);
            assertEq(_getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0], 0 ether);

            assertEq(strategyA.totalSupply(), 100_000000000000000000000);
            assertEq(strategyA.balanceOf(INITIAL_LOCKED_SHARES_ADDRESS), 1000000000000);
            assertEq(strategyA.balanceOf(address(smartVaultA)), 99_999999999000000000000);
        }

        // round 2.1 - yield + more deposits than withdrawals
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 20 ether);
            // - base yield
            strategyA.protocol().donate(5 ether);
            // - compound yield
            strategyA.protocol().reward(15 ether, address(strategyA));
            vm.stopPrank();

            // deposits + withdrawals
            // - Alice withdraws 1/2 of strategy worth
            vm.startPrank(alice);
            withdrawalNftId = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: 50_000000000000000000000,
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
            // - 5 token A base yield was generated
            // - 15 token A compound yield was generated
            // - Alice withdrew 1/2 of strategy worth
            //   - including base yield, but not compound yield
            //   - 52.25 token A was withdrawn
            //     - 50 from base
            //     - 2.5 from base yield
            //     - -0.25 as fees on base yield -> "withdrawal fees"
            // - 50 token A remained in strategy
            //   - accrued 2.5 from base yield
            //   - accrued 15 from matched compound yield
            //   -> 67.5 remains for legacy users
            //     -> 1.75 marked for fees -> "deposit fees"
            //     -> 65.75 marked for users
            // - 100 token A was deposited into smart vault B
            //   - 37.25 was matched
            //   - 62.75 was unmatched and deposited into the protocol
            // - all compound was matched

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 900.0 ether, 1e7, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 900.0 ether, 1e7, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 52.25 ether, 1e7, "tokenA -> MasterWallet");
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 105.0 ether, 1e7, "protocol -> totalUnderlying");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyA.protocol())), 167.75 ether, 1e7, "tokenA -> protocol");

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(strategyA.withdrawalFeeShares(), address(strategyA))[0],
                0.25 ether,
                1e7,
                "strategyAssetBalance -> withdrawal fees"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(strategyA.depositFeeShares(), address(strategyA))[0],
                1.75 ether,
                1e7,
                "strategyAssetBalance -> deposit fees"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(strategyA.userDepositShares(), address(strategyA))[0],
                37.25 ether,
                1e7,
                "strategyAssetBalance -> user deposits"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                65.75 ether,
                1e7,
                "strategyAssetBalance -> smartVaultA"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                0 ether,
                1e7,
                "strategyAssetBalance -> smartVaultB"
            );
        }

        // round 2.2 - DHW continuation + yield
        {
            // generate yield
            vm.startPrank(charlie);
            // - base yield
            uint256 baseYield = strategyA.protocol().totalUnderlying() * 5 / 100;
            tokenA.approve(address(strategyA.protocol()), baseYield);
            strategyA.protocol().donate(baseYield);
            vm.stopPrank();

            // console.log("baseYield", baseYield);

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
            // - 5% token A base yield was generated on 105.0 token A
            //   - 5.25
            //     - 0.0125 to withdrawal fees
            //     - 3.375 to legacy users
            //     - 1.8625 to matched deposits
            // - 62.75 token A deposit was finalized
            // how to distribute
            // - 0.2625 token A as withdrawal fees
            // - 70.875 token A as legacy users
            //   - 20.875 as yield
            //     -> 2.0875 as fees
            //   -> 68.7875 remains for legacy users
            // - 101.8625 token A as deposit
            //   - 1.8625 as yield
            //     -> 0.18625 as fees
            //   -> 101.67625 remains for users
            // state
            // - 52.25 token A withdrawn to Alice
            // - 2.53625 token A for fees
            // - 68.7875 token A for legacy users
            // - 101.67625 A for smart vault B

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 952.25 ether, 1e7, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 900.0 ether, 1e7, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0 ether, 1e7, "tokenA -> MasterWallet");
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 173.0 ether, 1e7, "protocol -> totalUnderlying");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyA.protocol())), 173.0 ether, 1e7, "tokenA -> protocol");

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                68.7875 ether,
                2e7,
                "strategyAssetBalance -> smartVaultA"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                101.67625 ether,
                2e7,
                "strategyAssetBalance -> smartVaultB"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                2.53625 ether,
                2e7,
                "strategyAssetBalance -> fees"
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
                new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, FULLY_NON_ATOMIC_STRATEGY);
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
            //   - 0.000000001 to initial locked shares
            //   - 99.999999999 to smart vault A

            assertEq(tokenA.balanceOf(address(alice)), 900.0 ether);
            assertEq(tokenA.balanceOf(address(bob)), 1000.0 ether);
            assertEq(tokenA.balanceOf(address(masterWallet)), 0 ether);
            assertEq(strategyA.protocol().totalUnderlying(), 100.0 ether);

            assertEq(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0], 0.000000001 ether
            );
            assertEq(_getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0], 99.999999999 ether);
            assertEq(_getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0], 0 ether);
            assertEq(_getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0], 0 ether);

            assertEq(strategyA.totalSupply(), 100_000000000000000000000);
            assertEq(strategyA.balanceOf(INITIAL_LOCKED_SHARES_ADDRESS), 1000000000000);
            assertEq(strategyA.balanceOf(address(smartVaultA)), 99_999999999000000000000);
        }

        // round 2.1 - yield + more withdrawals than deposits
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 20 ether);
            // - base yield
            strategyA.protocol().donate(5 ether);
            // - compound yield
            strategyA.protocol().reward(15 ether, address(strategyA));
            vm.stopPrank();

            // deposits + withdrawals
            // - Alice withdraws 1/2 of strategy worth
            vm.startPrank(alice);
            withdrawalNftId = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: 50_000000000000000000000,
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
            // - 5 token A base yield was generated
            // - 15 token A compound yield was generated
            // - Alice withdrew 1/2 of strategy worth
            //   - including base yield, but not compound yield
            //   - 52.25 token A should be withdrawn
            //     - 50 from base
            //     - 2.5 from base yield
            //     - -0.25 as fees on base yield -> "withdrawal fees"
            //   - 25 withdrawal is matched
            //   - 27.25 withdrawal is unmatched and is requested from the protocol
            // - 50 token A remained in strategy
            //   - accrued 2.5 from base yield
            //   - accrued 15 from matched compound yield
            //   -> 67.5 remains for legacy users
            //     -> 1.75 marked for fees -> "deposit fees"
            //     -> 65.75 marked for users
            // - 10 token A was deposited into smart vault B
            //   - all deposit was matched
            // - all compound was matched

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 900.0 ether, 1e7, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 990.0 ether, 1e7, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 25.0 ether, 1e7, "tokenA -> MasterWallet");
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 105.0 ether, 1e7, "protocol -> totalUnderlying");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyA.protocol())), 105.0 ether, 1e7, "tokenA -> protocol");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                77.75 ether,
                1e7,
                "protocolAssetBalance -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(strategyA.withdrawalFeeShares(), address(strategyA))[0],
                0.25 ether,
                1e7,
                "strategyAssetBalance -> withdrawal fees"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(strategyA.depositFeeShares(), address(strategyA))[0],
                1.75 ether,
                1e7,
                "strategyAssetBalance -> deposit fees"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(strategyA.userDepositShares(), address(strategyA))[0],
                10 ether,
                1e7,
                "strategyAssetBalance -> user deposits"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                65.75 ether,
                1e7,
                "strategyAssetBalance -> smartVaultA"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                0 ether,
                1e7,
                "strategyAssetBalance -> smartVaultB"
            );
        }

        // round 2.2 - DHW continuation + yield
        {
            // generate yield
            vm.startPrank(charlie);
            // - base yield
            uint256 baseYield = strategyA.protocol().totalUnderlying() * 5 / 100;
            tokenA.approve(address(strategyA.protocol()), baseYield);
            strategyA.protocol().donate(baseYield);
            vm.stopPrank();

            // console.log("baseYield", baseYield);

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
            // - 5% token A base yield was generated on 105.0 token A in the protocol
            //   - 5.25
            //     - 0.0125 to withdrawal fees
            //     - 3.375 to legacy users
            //     - 0.5 to matched deposits
            //     - 1.3625 to withdrawn withdrawals
            // - 27.25 token A withdrawal was finalized
            // how to distribute
            // - 0.2625 token A as withdrawal fees
            // - 70.875 token A as legacy users
            //   - 20.875 as yield
            //     -> 2.0875 as fees
            //   -> 68.7875 remains for legacy users
            // - 10.5 token A as deposit
            //   - 0.5 as yield
            //     -> 0.05 as fees
            //   -> 10.45 remains for users
            // - 28.6125 token A as withdrawn withdrawals
            //   - no additional fees are taken here
            // state
            // - 53.6125 token A withdrawn to Alice
            // - 2.4 token A for fees
            // - 68.7875 token A for legacy users
            // - 10.45 token A for smart vault B

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 953.6125 ether, 1e7, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 990.0 ether, 1e7, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0 ether, 1e7, "tokenA -> MasterWallet");
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 81.6375 ether, 1e7, "protocol -> totalUnderlying");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyA.protocol())), 81.6375 ether, 1e7, "tokenA -> protocol");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                81.6375 ether,
                1e7,
                "protocolAssetBalance -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                68.7875 ether,
                2e7,
                "strategyAssetBalance -> smartVaultA"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(smartVaultB), address(strategyA))[0],
                10.45 ether,
                2e7,
                "strategyAssetBalance -> smartVaultB"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                2.4 ether,
                2e7,
                "strategyAssetBalance -> fees"
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
                new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, FULLY_NON_ATOMIC_STRATEGY);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, FULLY_NON_ATOMIC_STRATEGY);

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

        // round 2 - generate some yield to get fee shares + deposit
        {
            // generate yield
            vm.startPrank(charlie);
            tokenA.approve(address(strategyA.protocol()), 10 ether);
            // - base yield
            strategyA.protocol().donate(10 ether);
            vm.stopPrank();

            // deposits
            // - Bob deposits 10 token A into smart vault A
            vm.startPrank(bob);
            tokenA.approve(address(smartVaultManager), 10 ether);
            depositNftId = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(10 ether),
                    receiver: bob,
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
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - round 1
            //   - Alice deposited 100 token A into smart vault A
            // - round 2
            //   - 10 token A base yield was generated
            //   - Bob deposited 10 token A into smart vault A
            // how to distribute
            // - smart vault A gets 100 token A from Alice's deposit
            // - 10 token A base yield
            //   - 1 token A as fees
            //   - 9 token A for smart vault A
            // - smart vault A gets 10 token A from Bob's deposit
            // state
            // - 120 token A in strategy A and protocol
            //   - 119 token A for smart vault A
            //   - 1 token A for fees
            //     - 0.6 token A as ecosystem fees
            //     - 0.4 token A as treasury fees

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 900.0 ether, 1e7, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 990.0 ether, 1e7, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0.0 ether, 1e7, "tokenA -> MasterWallet");
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 120.0 ether, 1e7, "protocol -> totalUnderlying");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyA.protocol())), 120.0 ether, 1e7, "tokenA -> protocol");
            assertApproxEqAbs(tokenA.balanceOf(ecosystemFeeRecipient), 0.0 ether, 1e7, "tokenA -> ecosystem fees");
            assertApproxEqAbs(tokenA.balanceOf(treasuryFeeRecipient), 0.0 ether, 1e7, "tokenA -> treasury fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                120.0 ether,
                1e7,
                "protocolAssetBalance -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                119.0 ether,
                1e7,
                "strategyAssetBalance -> smartVaultA"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0.6 ether,
                1e7,
                "strategyAssetBalance -> ecosystem fees"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.4 ether,
                1e7,
                "strategyAssetBalance -> treasury fees"
            );
        }

        // round 3 - redeem strategy shares + yield
        {
            // generate yield
            vm.startPrank(charlie);
            // - base yield
            uint256 baseYield = strategyA.protocol().totalUnderlying() * 10 / 100;
            tokenA.approve(address(strategyA.protocol()), baseYield);
            strategyA.protocol().donate(baseYield);
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
            console.log("strategyDhwIndex", strategyDhwIndex);

            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(strategies, assetGroup));
            strategyRegistry.doHardWorkContinue(_generateDhwContinuationParameterBag(strategies, assetGroup));
            vm.stopPrank();

            // claim
            // - ecosystem fee recipient claims their fees
            vm.startPrank(ecosystemFeeRecipient);
            strategyRegistry.claimStrategyShareWithdrawals(
                Arrays.toArray(address(strategyA)), Arrays.toArray(strategyDhwIndex), ecosystemFeeRecipient
            );
            vm.stopPrank();
            // - treasury fee recipient claims their fees
            vm.startPrank(treasuryFeeRecipient);
            strategyRegistry.claimStrategyShareWithdrawals(
                Arrays.toArray(address(strategyA)), Arrays.toArray(strategyDhwIndex), treasuryFeeRecipient
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - 10% base yield was generated on 120.0 token A in the protocol -> 12.0 token A
            //   - 1.2 token A as new fees
            //     - 0.72 token A for new ecosystem fees
            //     - 0.48 token A for new treasury fees
            //   - 10.8 for existing users
            //     - 10.71 (= 10.8 * 119 / 120) for smart vault A
            //     - 0.054 (= 10.8 * 0.6 / 120) for ecosystem fee recipient
            //     - 0.036 (= 10.8 * 0.4 / 120) for treasury fee recipient
            // - ecosystem fee recipient redeemed all their existing shares
            //   - 0.654 (= 0.6 + 0.054)
            // - treasury fee recipient redeemed all their existing shares
            //   - 0.436 (= 0.4 + 0.036)
            // state
            // - 130.91 token A in strategy A and protocol
            //   - 129.71 (= 119 + 10.71) token A for smart vault A
            //   - 1.2 token A for new fees
            //     - 0.72 token A for new ecosystem fees
            //     - 0.48 token A for new treasury fees
            // - 0.654 token A was withdrawn by ecosystem fee recipient
            // - 0.436 token A was withdrawn by treasury fee recipient

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 900.0 ether, 1e7, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 990.0 ether, 1e7, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0.0 ether, 1e7, "tokenA -> MasterWallet");
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 130.91 ether, 1e7, "protocol -> totalUnderlying");
            assertApproxEqAbs(tokenA.balanceOf(address(strategyA.protocol())), 130.91 ether, 1e7, "tokenA -> protocol");
            assertApproxEqAbs(tokenA.balanceOf(ecosystemFeeRecipient), 0.654 ether, 1e7, "tokenA -> ecosystem fees");
            assertApproxEqAbs(tokenA.balanceOf(treasuryFeeRecipient), 0.436 ether, 1e7, "tokenA -> treasury fees");

            assertApproxEqAbs(
                _getProtocolSharesAssetBalance(
                    strategyA.protocol().shares(address(strategyA)), address(strategyA.protocol())
                ),
                130.91 ether,
                1e7,
                "protocolAssetBalance -> strategyA"
            );

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                129.71 ether,
                1e7,
                "strategyAssetBalance -> smartVaultA"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0.72 ether,
                1e7,
                "strategyAssetBalance -> ecosystem fees"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.48 ether,
                1e7,
                "strategyAssetBalance -> treasury fees"
            );
        }
    }

    function test_nonAtomicStrategyFlow_redeemFast() public {
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
            // both deposits and withdrawals being non-atomic
            strategyA =
                new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, FULLY_NON_ATOMIC_STRATEGY);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, FULLY_NON_ATOMIC_STRATEGY);

            // strategy B implements non-atomic strategy with
            // non-atomic deposits and atomic withdrawals
            strategyB =
                new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, NON_ATOMIC_DEPOSIT_STRATEGY);
            strategyB.initialize("StratB");
            strategyRegistry.registerStrategy(address(strategyB), 0, NON_ATOMIC_DEPOSIT_STRATEGY);
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory spec = _getSmartVaultSpecification();
            spec.strategyAllocation = uint16a16.wrap(0).set(0, 100_00);
            spec.assetGroupId = assetGroupId;

            spec.strategies = Arrays.toArray(address(strategyA));
            spec.smartVaultName = "SmartVaultA";
            smartVaultA = smartVaultFactory.deploySmartVault(spec);

            spec.strategies = Arrays.toArray(address(strategyB));
            spec.smartVaultName = "SmartVaultB";
            smartVaultB = smartVaultFactory.deploySmartVault(spec);
        }

        uint256 depositNftIdA;
        uint256 depositNftIdB;

        // round 1 - initial deposit
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftIdA = smartVaultManager.deposit(
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
            depositNftIdB = smartVaultManager.deposit(
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
            strategyRegistry.doHardWork(
                _generateDhwParameterBag(Arrays.toArray(address(strategyA), address(strategyB)), assetGroup)
            );
            strategyRegistry.doHardWorkContinue(
                _generateDhwContinuationParameterBag(Arrays.toArray(address(strategyA), address(strategyB)), assetGroup)
            );
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftIdA), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftIdB), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // round 2 - failed withdrawals
        {
            // Alice deposits 10 token A into smart vault B
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 10 ether);
            depositNftIdB = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(10 ether),
                    receiver: alice,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW initial
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(Arrays.toArray(address(strategyB)), assetGroup));
            vm.stopPrank();

            // failed withdrawals
            // - Alice tries to redeem fast 25 token A from smart vault A
            vm.startPrank(alice);
            RedeemBag memory redeemBag = RedeemBag({
                smartVault: address(smartVaultA),
                shares: 25_000000000000000000000,
                nftIds: new uint256[](0),
                nftAmounts: new uint256[](0)
            });
            //   - should fail because smart vault A has a strategy with non-atomic withdrawal
            vm.expectRevert(ProtocolActionNotFinished.selector);
            smartVaultManager.redeemFast(redeemBag, new uint256[][](1));
            vm.stopPrank();
            // - Bob tries to redeem fast 25 token A from smart vault B
            vm.startPrank(bob);
            redeemBag.smartVault = address(smartVaultB);
            //   - should fail because smart vault B has a strategy with DHW in progress
            vm.expectRevert(StrategyNotReady.selector);
            smartVaultManager.redeemFast(redeemBag, new uint256[][](1));
            vm.stopPrank();

            // DHW continuation, sync
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWorkContinue(
                _generateDhwContinuationParameterBag(Arrays.toArray(address(strategyB)), assetGroup)
            );
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftIdB), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        uint256 withdrawalNftIdA;

        // round 3 - successful withdrawals
        {
            // successful withdrawals
            // - Alice redeems 20 token A from smart vault A
            vm.startPrank(alice);
            withdrawalNftIdA = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: 20_000000000000000000000,
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );
            vm.stopPrank();
            // - Bob redeems fast 20 token A from smart vault B
            vm.startPrank(bob);
            smartVaultManager.redeemFast(
                RedeemBag({
                    smartVault: address(smartVaultB),
                    shares: 20_000000000000000000000,
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                new uint256[][](1)
            );
            vm.stopPrank();

            // flush, DHW, sync
            smartVaultManager.flushSmartVault(address(smartVaultA));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(Arrays.toArray(address(strategyA)), assetGroup));
            strategyRegistry.doHardWorkContinue(
                _generateDhwContinuationParameterBag(Arrays.toArray(address(strategyA)), assetGroup)
            );
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            // - withdrawal by Alice
            vm.startPrank(alice);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftIdA), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - Alice deposited 100 token A into smart vault A
            //   - smart vault A routed 100 token A to strategy A
            // - Bob deposited 100 token A into smart vault B
            //   - smart vault B routed 100 token A to strategy B
            // - Alice deposited 10 token A into smart vault B
            //   - smart vault B routed 10 token A to strategy B
            // - Alice tried to redeem fast 25 token A from smart vault A
            //   - failed because smart vault A has a strategy with non-atomic withdrawal
            // - Bob tried to redeem fast 25 token A from smart vault B
            //   - failed because smart vault B had a strategy with DHW in progress
            // - Alice redeemed 20 token A from smart vault A
            // - Bob redeemed 20 token A from smart vault B
            // how to distribute
            // - Alice deposited 100 token A and withdrew 20 token A
            //   - 80 token A remains in smart vault A
            //     - 80 token A remains in strategy A
            //   - 20 token A was withdrawn
            // - Bob deposited 100 token A and withdrew 20 token A
            //   - 80 token A remains in smart vault B
            //     - 80 token A remains in strategy B
            //   - 20 token A was withdrawn
            // - Alice deposited 10 token A into smart vault B
            // state
            // - 80 token A in strategy A and protocol
            //   - 80 token A for smart vault A
            //     - 80 token A for Alice
            // - 90 token A in strategy B and protocol
            //   - 90 token A for smart vault B
            //     - 80 token A for Bob
            //     - 10 token A for Alice

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 910.0 ether, 1e7, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 920.0 ether, 1e7, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0.0 ether, 1e7, "tokenA -> MasterWallet");
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 80.0 ether, 1e7, "protocol A -> totalUnderlying");
            assertApproxEqAbs(strategyB.protocol().totalUnderlying(), 90.0 ether, 1e7, "protocol B -> totalUnderlying");

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                80.0 ether,
                1e7,
                "strategyAssetBalance -> smartVaultA"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyB))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultB), address(strategyB))[0],
                90.0 ether,
                1e7,
                "strategyAssetBalance -> smartVaultB"
            );
        }
    }

    function test_nonAtomicStrategyFlow_redeemStrategyShares() public {
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
            // both deposits and withdrawals being non-atomic
            strategyA =
                new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, FULLY_NON_ATOMIC_STRATEGY);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA), 0, FULLY_NON_ATOMIC_STRATEGY);

            // strategy B implements non-atomic strategy with
            // non-atomic deposits and atomic withdrawals
            strategyB =
                new MockStrategyNonAtomic(assetGroupRegistry, accessControl, assetGroupId, NON_ATOMIC_DEPOSIT_STRATEGY);
            strategyB.initialize("StratB");
            strategyRegistry.registerStrategy(address(strategyB), 0, NON_ATOMIC_DEPOSIT_STRATEGY);
        }

        // setup smart vaults
        ISmartVault smartVaultA;
        ISmartVault smartVaultB;
        {
            SmartVaultSpecification memory spec = _getSmartVaultSpecification();
            spec.strategyAllocation = uint16a16.wrap(0).set(0, 100_00);
            spec.assetGroupId = assetGroupId;

            spec.strategies = Arrays.toArray(address(strategyA));
            spec.smartVaultName = "SmartVaultA";
            smartVaultA = smartVaultFactory.deploySmartVault(spec);

            spec.strategies = Arrays.toArray(address(strategyB));
            spec.smartVaultName = "SmartVaultB";
            smartVaultB = smartVaultFactory.deploySmartVault(spec);
        }

        uint256 depositNftIdA;
        uint256 depositNftIdB;

        // round 1 - initial deposit
        {
            // Alice deposits 100 token A into smart vault A
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 100 ether);
            depositNftIdA = smartVaultManager.deposit(
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
            depositNftIdB = smartVaultManager.deposit(
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
            strategyRegistry.doHardWork(
                _generateDhwParameterBag(Arrays.toArray(address(strategyA), address(strategyB)), assetGroup)
            );
            strategyRegistry.doHardWorkContinue(
                _generateDhwContinuationParameterBag(Arrays.toArray(address(strategyA), address(strategyB)), assetGroup)
            );
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftIdA), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftIdB), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // round 2 - yield
        {
            // generate yield
            vm.startPrank(charlie);
            // - base yield for strategy A
            tokenA.approve(address(strategyA.protocol()), 10 ether);
            strategyA.protocol().donate(10 ether);
            // - base yield for strategy B
            tokenA.approve(address(strategyB.protocol()), 20 ether);
            strategyB.protocol().donate(20 ether);
            vm.stopPrank();

            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(Arrays.toArray(address(strategyA)), assetGroup));
            strategyRegistry.doHardWork(_generateDhwParameterBag(Arrays.toArray(address(strategyB)), assetGroup));
            vm.stopPrank();
        }

        // round 3 - failed withdrawals
        {
            // Alice deposits 10 token A into smart vault B
            vm.startPrank(alice);
            tokenA.approve(address(smartVaultManager), 10 ether);
            depositNftIdB = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(10 ether),
                    receiver: alice,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush, DHW initial
            smartVaultManager.flushSmartVault(address(smartVaultB));

            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(Arrays.toArray(address(strategyB)), assetGroup));
            vm.stopPrank();

            // failed withdrawals
            // - ecosystem fee recipient tries to redeem half their shares from strategy A
            vm.startPrank(ecosystemFeeRecipient);
            address[] memory strategies = Arrays.toArray(address(strategyA));
            uint256[] memory shares = Arrays.toArray(strategyA.balanceOf(ecosystemFeeRecipient) / 2);
            //   - should fail because smart vault A has a strategy with non-atomic withdrawal
            vm.expectRevert(ProtocolActionNotFinished.selector);
            strategyRegistry.redeemStrategyShares(strategies, shares, new uint256[][](1));
            vm.stopPrank();
            // - treasury fee recipient tries to redeem half their shares from strategy B
            vm.startPrank(treasuryFeeRecipient);
            strategies = Arrays.toArray(address(strategyB));
            shares = Arrays.toArray(strategyB.balanceOf(treasuryFeeRecipient) / 2);
            //   - should fail because smart vault B has a strategy with DHW in progress
            vm.expectRevert(StrategyNotReady.selector);
            strategyRegistry.redeemStrategyShares(strategies, shares, new uint256[][](1));
            vm.stopPrank();

            // DHW continuation, sync
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWorkContinue(
                _generateDhwContinuationParameterBag(Arrays.toArray(address(strategyB)), assetGroup)
            );
            vm.stopPrank();

            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftIdB), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // round 4 - successful withdrawals
        {
            // successful withdrawals
            // - ecosystem fee recipient redeems async 1/3 of their shares from strategy A
            vm.startPrank(ecosystemFeeRecipient);
            uint256 redeemIndex = strategyRegistry.currentIndex(Arrays.toArray(address(strategyA)))[0];
            strategyRegistry.redeemStrategySharesAsync(
                Arrays.toArray(address(strategyA)), Arrays.toArray(strategyA.balanceOf(ecosystemFeeRecipient) / 3)
            );
            // - treasury fee recipient redeems 1/4 of their shares from strategy B
            vm.startPrank(treasuryFeeRecipient);
            strategyRegistry.redeemStrategyShares(
                Arrays.toArray(address(strategyB)),
                Arrays.toArray(strategyB.balanceOf(treasuryFeeRecipient) / 4),
                new uint256[][](1)
            );
            vm.stopPrank();

            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(_generateDhwParameterBag(Arrays.toArray(address(strategyA)), assetGroup));
            strategyRegistry.doHardWorkContinue(
                _generateDhwContinuationParameterBag(Arrays.toArray(address(strategyA)), assetGroup)
            );
            vm.stopPrank();

            // claim
            vm.startPrank(ecosystemFeeRecipient);
            strategyRegistry.claimStrategyShareWithdrawals(
                Arrays.toArray(address(strategyA)), Arrays.toArray(redeemIndex), ecosystemFeeRecipient
            );
            vm.stopPrank();
        }

        // check state
        {
            // what happened
            // - Alice deposited 100 token A into smart vault A
            //   - smart vault A routed 100 token A to strategy A
            // - Bob deposited 100 token A into smart vault B
            //   - smart vault B routed 100 token A to strategy B
            // - 10 token A base yield was generated for strategy A
            //   - 1 as fees
            //     - 0.6 as ecosystem fees
            //     - 0.4 as treasury fees
            // - 20 token A base yield was generated for strategy B
            //   - 2 as fees
            //     - 1.2 as ecosystem fees
            //     - 0.8 as treasury fees
            // - Alice deposited 10 token A into smart vault B
            //   - smart vault B routed 10 token A to strategy B
            // - ecosystem fee recipient tried to redeem half their shares from strategy A
            //   - failed because smart vault A has a strategy with non-atomic withdrawal
            // - treasury fee recipient tried to redeem half their shares from strategy B
            //   - failed because smart vault B had a strategy with DHW in progress
            // - ecosystem fee recipient redeemed 1/3 of their shares from strategy A
            //   - 0.2 token A was withdrawn
            // - treasury fee recipient redeemed 1/4 of their shares from strategy B
            //   - 0.2 token A was withdrawn
            // how to distribute
            // - Alice deposited 100 token A
            //   - 100 token A remains in smart vault A
            //     - 100 token A remains in strategy A
            // - Bob deposited 100 token A
            //   - 100 token A remains in smart vault B
            //     - 100 token A remains in strategy B
            // - 10 token A base yield was generated for strategy A
            //   - 9 tokens attributed to smart vault A
            //   - 0.6 token A as ecosystem fees, 0.2 token A was withdrawn
            //   - 0.4 token A as treasury fees
            // - 20 token A base yield was generated for strategy B
            //   - 18 tokens attributed to smart vault B
            //   - 1.2 token A as ecosystem fees
            //   - 0.8 token A as treasury fees, 0.2 token A was withdrawn
            // - Alice deposited 10 token A
            //   - 10 token A remains in smart vault B
            //     - 10 token A remains in strategy B
            // state
            // - 109.8 token A in strategy A and protocol
            //   - 109 token A for smart vault A
            //   - 0.4 token A for ecosystem fees
            //   - 0.4 token A for treasury fees
            // - 129.8 token A in strategy B and protocol
            //   - 118 token A for smart vault B
            //   - 1.2 token A for ecosystem fees
            //   - 0.6 token A for treasury fees
            // - 0.2 token A for ecosystem fee recipient
            // - 0.2 token A for treasury fee recipient

            assertApproxEqAbs(tokenA.balanceOf(address(alice)), 890.0 ether, 1e7, "tokenA -> Alice");
            assertApproxEqAbs(tokenA.balanceOf(address(bob)), 900.0 ether, 1e7, "tokenA -> Bob");
            assertApproxEqAbs(tokenA.balanceOf(address(masterWallet)), 0.0 ether, 1e7, "tokenA -> MasterWallet");
            assertApproxEqAbs(strategyA.protocol().totalUnderlying(), 109.8 ether, 1e7, "protocol A -> totalUnderlying");
            assertApproxEqAbs(strategyB.protocol().totalUnderlying(), 129.8 ether, 1e7, "protocol B -> totalUnderlying");
            assertApproxEqAbs(tokenA.balanceOf(ecosystemFeeRecipient), 0.2 ether, 1e7, "tokenA -> ecosystem fees");
            assertApproxEqAbs(tokenA.balanceOf(treasuryFeeRecipient), 0.2 ether, 1e7, "tokenA -> treasury fees");

            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyA))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultA), address(strategyA))[0],
                109.0 ether,
                1e7,
                "strategyAssetBalance A -> smartVaultA"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyA))[0],
                0.4 ether,
                1e7,
                "strategyAssetBalance A -> ecosystem fees"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyA))[0],
                0.4 ether,
                1e7,
                "strategyAssetBalance A -> treasury fees"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(INITIAL_LOCKED_SHARES_ADDRESS, address(strategyB))[0]
                    + _getStrategySharesAssetBalances(address(smartVaultB), address(strategyB))[0],
                128.0 ether,
                1e7,
                "strategyAssetBalance B -> smartVaultB"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(ecosystemFeeRecipient), address(strategyB))[0],
                1.2 ether,
                1e7,
                "strategyAssetBalance B -> ecosystem fees"
            );
            assertApproxEqAbs(
                _getStrategySharesAssetBalances(address(treasuryFeeRecipient), address(strategyB))[0],
                0.6 ether,
                1e7,
                "strategyAssetBalance B -> treasury fees"
            );
        }
    }
}
