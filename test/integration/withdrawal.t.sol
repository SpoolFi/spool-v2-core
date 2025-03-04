// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/access/SpoolAccessControl.sol";
import "../../src/managers/ActionManager.sol";
import "../../src/managers/AssetGroupRegistry.sol";
import "../../src/managers/GuardManager.sol";
import "../../src/managers/RiskManager.sol";
import "../../src/managers/SmartVaultManager.sol";
import "../../src/managers/StrategyRegistry.sol";
import "../../src/managers/UsdPriceFeedManager.sol";
import "../../src/MasterWallet.sol";
import "../../src/SmartVault.sol";
import "../../src/SmartVaultFactory.sol";
import "../../src/Swapper.sol";
import "../libraries/Arrays.sol";
import "../mocks/MockStrategy.sol";
import "../mocks/MockToken.sol";
import "../mocks/MockPriceFeedManager.sol";
import "../../src/managers/WithdrawalManager.sol";
import "../../src/managers/DepositManager.sol";
import "../../src/rewards/RewardManager.sol";
import "../../src/strategies/GhostStrategy.sol";
import "../libraries/TimeUtils.sol";

contract WithdrawalIntegrationTest is Test {
    event StrategySharesFastRedeemed(address indexed strategy, uint256 shares, uint256[] assetsWithdrawn);

    address private alice;
    address private bob;

    address doHardWorker;
    address emergencyWithdrawalWallet;

    MockToken tokenA;
    MockToken tokenB;
    address[] assetGroup;

    MockStrategy strategyA;
    MockStrategy strategyB;
    IStrategy ghostStrategy;
    address[] mySmartVaultStrategies;

    Swapper private swapper;
    ISmartVault private mySmartVault;
    SmartVaultManager private smartVaultManager;
    StrategyRegistry private strategyRegistry;
    MasterWallet private masterWallet;
    AssetGroupRegistry private assetGroupRegistry;
    SpoolAccessControl accessControl;
    IDepositManager depositManager;
    IWithdrawalManager withdrawalManager;
    MockPriceFeedManager priceFeedManager;

    function setUp() public {
        alice = address(0xa);
        bob = address(0xb);

        address riskProvider = address(0x1);
        doHardWorker = address(0x2);
        emergencyWithdrawalWallet = address(0x3);

        assetGroup =
            Arrays.sort(Arrays.toArray(address(new MockToken("Token", "T")), address(new MockToken("Token", "T"))));

        tokenA = MockToken(assetGroup[0]);
        tokenB = MockToken(assetGroup[1]);

        accessControl = new SpoolAccessControl();
        accessControl.initialize();
        masterWallet = new MasterWallet(accessControl);

        swapper = new Swapper(accessControl);

        assetGroupRegistry = new AssetGroupRegistry(accessControl);
        assetGroupRegistry.initialize(assetGroup);
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        ghostStrategy = new GhostStrategy();
        priceFeedManager = new MockPriceFeedManager();

        strategyRegistry = new StrategyRegistry(masterWallet, accessControl, priceFeedManager, address(ghostStrategy));
        strategyRegistry.initialize(0, 0, address(0xf01), address(0xf02), emergencyWithdrawalWallet);

        IActionManager actionManager = new ActionManager(accessControl);
        IGuardManager guardManager = new GuardManager(accessControl);
        IRiskManager riskManager = new RiskManager(accessControl, strategyRegistry, address(ghostStrategy));
        depositManager =
        new DepositManager(strategyRegistry, priceFeedManager, guardManager, actionManager, accessControl, masterWallet, address(ghostStrategy));
        withdrawalManager =
            new WithdrawalManager(strategyRegistry, masterWallet, guardManager, actionManager, accessControl);

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

        accessControl.grantRole(ADMIN_ROLE_STRATEGY, address(strategyRegistry));

        strategyA = new MockStrategy(assetGroupRegistry, accessControl, swapper, assetGroupId);
        uint256[] memory strategyRatios = new uint256[](2);
        strategyRatios[0] = 1_000;
        strategyRatios[1] = 68;
        strategyA.initialize("StratA", strategyRatios);
        strategyRegistry.registerStrategy(address(strategyA), 0, ATOMIC_STRATEGY);

        strategyRatios[1] = 67;
        strategyB = new MockStrategy(assetGroupRegistry, accessControl, swapper, assetGroupId);
        strategyB.initialize("StratB", strategyRatios);
        strategyRegistry.registerStrategy(address(strategyB), 0, ATOMIC_STRATEGY);

        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
        accessControl.grantRole(ROLE_DO_HARD_WORKER, doHardWorker);
        accessControl.grantRole(ROLE_ALLOCATION_PROVIDER, address(0xabc));
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(depositManager));
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(withdrawalManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY_REGISTRY, address(strategyRegistry));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(withdrawalManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(depositManager));

        {
            address smartVaultImplementation = address(new SmartVault(accessControl, guardManager));
            SmartVaultFactory smartVaultFactory = new SmartVaultFactory(
                smartVaultImplementation,
                accessControl,
                actionManager,
                guardManager,
                smartVaultManager,
                assetGroupRegistry,
                riskManager
            );
            accessControl.grantRole(ROLE_SMART_VAULT_INTEGRATOR, address(smartVaultFactory));

            mySmartVaultStrategies = Arrays.toArray(address(strategyA), address(strategyB));

            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toUint16a16(400, 600))
            );

            mySmartVault = smartVaultFactory.deploySmartVault(
                SmartVaultSpecification({
                    smartVaultName: "MySmartVault",
                    svtSymbol: "MSV",
                    baseURI: "https://token-cdn-domain/",
                    assetGroupId: assetGroupId,
                    actions: new IAction[](0),
                    actionRequestTypes: new RequestType[](0),
                    guards: new GuardDefinition[][](0),
                    guardRequestTypes: new RequestType[](0),
                    strategies: mySmartVaultStrategies,
                    strategyAllocation: uint16a16.wrap(0),
                    riskTolerance: 4,
                    riskProvider: riskProvider,
                    managementFeePct: 0,
                    depositFeePct: 0,
                    allowRedeemFor: false,
                    allocationProvider: address(0xabc),
                    performanceFeePct: 0
                })
            );
        }
    }

    function generateDhwParameterBag(address[] memory strategies, address[] memory assetGroup_)
        internal
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

        uint256[2][] memory exchangeRateSlippages = new uint256[2][](assetGroup_.length);

        for (uint256 i; i < assetGroup_.length; ++i) {
            exchangeRateSlippages[i][0] = priceFeedManager.exchangeRates(assetGroup_[i]);
            exchangeRateSlippages[i][1] = priceFeedManager.exchangeRates(assetGroup_[i]);
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

    function test_redeem_revertInsufficientBalance() public {
        // set initial state
        deal(address(mySmartVault), alice, 4_000_000, true);
        deal(address(mySmartVault), bob, 1_000_000, true);

        // request withdrawal
        vm.prank(alice);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        smartVaultManager.redeem(
            RedeemBag(address(mySmartVault), 5_000_000, new uint256[](0), new uint256[](0)), alice, false
        );
    }

    function test_redeem_shouldBeAbleToWithdraw() public {
        // set initial state
        deal(address(mySmartVault), alice, 4_000_000, true);
        deal(address(mySmartVault), bob, 1_000_000, true);
        deal(address(strategyA), address(mySmartVault), 40_000_000, true);
        deal(address(strategyB), address(mySmartVault), 10_000_000, true);
        deal(address(tokenA), address(strategyA.protocol()), 40 ether, true);
        deal(address(tokenB), address(strategyA.protocol()), 2.72 ether, true);
        deal(address(tokenA), address(strategyB.protocol()), 10 ether, true);
        deal(address(tokenB), address(strategyB.protocol()), 0.67 ether, true);

        // request withdrawal
        vm.prank(alice);
        uint256 aliceWithdrawalNftId = smartVaultManager.redeem(
            RedeemBag(address(mySmartVault), 3_000_000, new uint256[](0), new uint256[](0)), alice, false
        );

        vm.prank(bob);
        uint256 bobWithdrawalNftId = smartVaultManager.redeem(
            RedeemBag(address(mySmartVault), 200_000, new uint256[](0), new uint256[](0)), bob, false
        );

        // check state
        // - vault tokens are returned to vault
        assertEq(mySmartVault.balanceOf(alice), 1_000_000, "1");
        assertEq(mySmartVault.balanceOf(bob), 800_000, "2");
        assertEq(mySmartVault.balanceOf(address(mySmartVault)), 3_200_000, "3");
        // - withdrawal NFTs are minted
        assertEq(aliceWithdrawalNftId, 2 ** 255 + 1, "4");
        assertEq(bobWithdrawalNftId, 2 ** 255 + 2, "5");
        assertEq(mySmartVault.balanceOfFractional(alice, aliceWithdrawalNftId), NFT_MINTED_SHARES, "6.1");
        assertEq(mySmartVault.balanceOf(alice, aliceWithdrawalNftId), 1, "6.2");
        assertEq(mySmartVault.balanceOfFractional(bob, bobWithdrawalNftId), NFT_MINTED_SHARES, "7.1");
        assertEq(mySmartVault.balanceOf(bob, bobWithdrawalNftId), 1, "7.2");

        // flush
        smartVaultManager.flushSmartVault(address(mySmartVault));

        // check state
        // - vault tokens are burned
        assertEq(mySmartVault.balanceOf(address(mySmartVault)), 0, "8");
        // - strategy tokens are returned to strategies
        assertEq(strategyA.balanceOf(address(mySmartVault)), 14_400_000, "9");
        assertEq(strategyB.balanceOf(address(mySmartVault)), 3_600_000, "10");
        assertEq(strategyA.balanceOf(address(strategyA)), 25_600_000, "11");
        assertEq(strategyB.balanceOf(address(strategyB)), 6_400_000, "12");

        // DHW
        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(mySmartVaultStrategies, assetGroup));
        vm.stopPrank();

        // check state
        // - strategy tokens are burned
        assertEq(strategyA.balanceOf(address(strategyA)), 0, "13");
        assertEq(strategyB.balanceOf(address(strategyB)), 0, "14");
        // - assets are withdrawn from protocol master wallet
        assertEq(tokenA.balanceOf(address(masterWallet)), 32 ether, "15");
        assertEq(tokenB.balanceOf(address(masterWallet)), 2.1696 ether, "16");
        assertEq(tokenA.balanceOf(address(strategyA)), 0, "17");
        assertEq(tokenB.balanceOf(address(strategyA)), 0, "18");
        assertEq(tokenA.balanceOf(address(strategyB)), 0, "19");
        assertEq(tokenB.balanceOf(address(strategyB)), 0, "20");

        // sync vault
        smartVaultManager.syncSmartVault(address(mySmartVault), true);

        // check state
        // nothing to check

        // claim withdrawal
        uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);
        uint256[] memory ids = Arrays.toArray(aliceWithdrawalNftId);
        vm.prank(alice);
        smartVaultManager.claimWithdrawal(address(mySmartVault), ids, amounts, alice);

        ids = Arrays.toArray(bobWithdrawalNftId);
        vm.prank(bob);
        smartVaultManager.claimWithdrawal(address(mySmartVault), ids, amounts, bob);

        // check state
        // - assets are transfered to withdrawers
        assertEq(tokenA.balanceOf(alice), 30 ether, "21");
        assertEq(tokenB.balanceOf(alice), 2.034 ether, "22");
        assertEq(tokenA.balanceOf(bob), 2 ether, "23");
        assertEq(tokenB.balanceOf(bob), 0.1356 ether, "24");
        assertEq(tokenA.balanceOf(address(masterWallet)), 0, "25");
        assertEq(tokenB.balanceOf(address(masterWallet)), 0, "26");
        // - withdrawal NFTs are burned
        assertEq(mySmartVault.balanceOfFractional(alice, aliceWithdrawalNftId), 0, "27");
        assertEq(mySmartVault.balanceOfFractional(bob, bobWithdrawalNftId), 0, "28.1");
        assertEq(mySmartVault.balanceOf(bob, bobWithdrawalNftId), 0, "28.2");
    }

    function test_should_not_revert_when_withdrawing_one_SVT_wei() public {
        // set initial state
        deal(address(mySmartVault), alice, 50_000_000, true);
        deal(address(strategyA), address(mySmartVault), 40_000_000, true);
        deal(address(strategyB), address(mySmartVault), 10_000_000, true);
        deal(address(tokenA), address(strategyA.protocol()), 40 ether, true);
        deal(address(tokenB), address(strategyA.protocol()), 2.72 ether, true);
        deal(address(tokenA), address(strategyB.protocol()), 10 ether, true);
        deal(address(tokenB), address(strategyB.protocol()), 0.67 ether, true);

        // request withdrawal
        vm.prank(alice);
        uint256 aliceWithdrawalNftId = smartVaultManager.redeem(
            RedeemBag(address(mySmartVault), 1, new uint256[](0), new uint256[](0)), alice, false
        );

        // check state
        // - vault tokens are returned to vault
        assertEq(mySmartVault.balanceOf(alice), 49_999_999);
        assertEq(mySmartVault.balanceOf(address(mySmartVault)), 1);

        // flush
        smartVaultManager.flushSmartVault(address(mySmartVault));

        // check state
        // - vault tokens are burned
        assertEq(mySmartVault.balanceOf(address(mySmartVault)), 0);
        // - strategy tokens are returned to strategies
        //   but since there only 1 SVT wei was withdrawn, there should be no changes here
        assertEq(strategyA.balanceOf(address(mySmartVault)), 40_000_000);
        assertEq(strategyB.balanceOf(address(mySmartVault)), 10_000_000);
        assertEq(strategyA.balanceOf(address(strategyA)), 0);
        assertEq(strategyB.balanceOf(address(strategyB)), 0);

        // DHW
        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(mySmartVaultStrategies, assetGroup));
        vm.stopPrank();

        // check state
        // - assets are withdrawn from protocol masteet
        //   but there should be nothing withdrawn
        assertEq(tokenA.balanceOf(address(masterWallet)), 0);
        assertEq(tokenB.balanceOf(address(masterWallet)), 0);
        assertEq(tokenA.balanceOf(address(strategyA)), 0);
        assertEq(tokenB.balanceOf(address(strategyA)), 0);
        assertEq(tokenA.balanceOf(address(strategyB)), 0);
        assertEq(tokenB.balanceOf(address(strategyB)), 0);

        // sync vault
        smartVaultManager.syncSmartVault(address(mySmartVault), true);

        // check state
        // nothing to check

        // claim withdrawal
        uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);
        uint256[] memory ids = Arrays.toArray(aliceWithdrawalNftId);
        vm.prank(alice);
        smartVaultManager.claimWithdrawal(address(mySmartVault), ids, amounts, alice);

        // check state
        // - withdrawal NFTs are burned
        assertEq(mySmartVault.balanceOfFractional(alice, aliceWithdrawalNftId), 0);
    }

    function test_redeemFor_revertIfNotAdmin() public {
        accessControl.grantRole(ADMIN_ROLE_SMART_VAULT_ALLOW_REDEEM, address(this));
        accessControl.grantRole(ROLE_SMART_VAULT_ALLOW_REDEEM, address(mySmartVault));

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SMART_VAULT_ADMIN, alice));
        smartVaultManager.redeemFor(
            RedeemBag(address(mySmartVault), 3_000_000, new uint256[](0), new uint256[](0)), bob, false
        );
        vm.stopPrank();
    }

    function test_redeemFor_revertIfNotAllowed() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(MissingRole.selector, ROLE_SMART_VAULT_ALLOW_REDEEM, address(mySmartVault))
        );
        smartVaultManager.redeemFor(
            RedeemBag(address(mySmartVault), 3_000_000, new uint256[](0), new uint256[](0)), bob, false
        );
    }

    function test_redeemFor_ok() public {
        accessControl.grantRole(ADMIN_ROLE_SMART_VAULT_ALLOW_REDEEM, address(this));
        accessControl.grantRole(ROLE_SMART_VAULT_ALLOW_REDEEM, address(mySmartVault));
        accessControl.grantSmartVaultRole(address(mySmartVault), ROLE_SMART_VAULT_ADMIN, alice);

        // set initial state
        deal(address(mySmartVault), bob, 1_000_000, true);
        deal(address(strategyA), address(mySmartVault), 40_000_000, true);
        deal(address(strategyB), address(mySmartVault), 10_000_000, true);

        // request withdrawal
        vm.prank(alice);
        uint256 redeemId = smartVaultManager.redeemFor(
            RedeemBag(address(mySmartVault), 500_000, new uint256[](0), new uint256[](0)), bob, false
        );

        assertGt(mySmartVault.balanceOf(bob, redeemId), 0);
        assertEq(mySmartVault.balanceOf(alice, redeemId), 0);
    }

    function test_redeemFast_shouldBeAbleToWithdrawFast() public {
        // set initial state
        deal(address(mySmartVault), alice, 4_000_000, true);
        deal(address(mySmartVault), bob, 1_000_000, true);
        deal(address(strategyA), address(mySmartVault), 40_000_000, true);
        deal(address(strategyB), address(mySmartVault), 10_000_000, true);
        deal(address(tokenA), address(strategyA.protocol()), 40 ether, true);
        deal(address(tokenB), address(strategyA.protocol()), 2.72 ether, true);
        deal(address(tokenA), address(strategyB.protocol()), 10 ether, true);
        deal(address(tokenB), address(strategyB.protocol()), 0.67 ether, true);

        // withdraw fast
        uint256[][] memory withdrawalSlippages = new uint256[][](2);
        withdrawalSlippages[0] = new uint256[](0);
        withdrawalSlippages[1] = new uint256[](0);

        vm.startPrank(alice);
        uint256[] memory withdrawnAssets = smartVaultManager.redeemFast(
            RedeemBag(address(mySmartVault), 3_000_000, new uint256[](0), new uint256[](0)), withdrawalSlippages
        );
        vm.stopPrank();

        // check return
        assertEq(withdrawnAssets, Arrays.toArray(30 ether, 2.034 ether));

        // check state
        // - vault tokens were burned
        assertEq(mySmartVault.balanceOf(alice), 1_000_000);
        assertEq(mySmartVault.totalSupply(), 2_000_000);
        // - strategy tokens were burned
        assertEq(strategyA.balanceOf(address(mySmartVault)), 16_000_000);
        assertEq(strategyB.balanceOf(address(mySmartVault)), 4_000_000);
        assertEq(strategyA.totalSupply(), 16_000_000);
        assertEq(strategyB.totalSupply(), 4_000_000);
        // - assets were transferred to Alice
        assertEq(tokenA.balanceOf(alice), 30 ether);
        assertEq(tokenB.balanceOf(alice), 2.034 ether);
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 16 ether);
        assertEq(tokenB.balanceOf(address(strategyA.protocol())), 1.088 ether);
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 4 ether);
        assertEq(tokenB.balanceOf(address(strategyB.protocol())), 0.268 ether);
    }

    function test_redeemFast_shouldEmitStrategySharesFastRedeemed() public {
        // set initial state
        deal(address(mySmartVault), alice, 4_000_000, true);
        deal(address(strategyA), address(mySmartVault), 40_000_000, true);
        deal(address(strategyB), address(mySmartVault), 10_000_000, true);
        deal(address(tokenA), address(strategyA.protocol()), 40 ether, true);
        deal(address(tokenB), address(strategyA.protocol()), 2.72 ether, true);
        deal(address(tokenA), address(strategyB.protocol()), 10 ether, true);
        deal(address(tokenB), address(strategyB.protocol()), 0.67 ether, true);

        // withdraw fast
        uint256[][] memory withdrawalSlippages = new uint256[][](2);
        withdrawalSlippages[0] = new uint256[](0);
        withdrawalSlippages[1] = new uint256[](0);

        vm.startPrank(alice);

        uint256[][] memory expectedAmounts = new uint256[][](2);
        expectedAmounts[0] = Arrays.toArray(20 ether, 1.36 ether);
        expectedAmounts[1] = Arrays.toArray(5 ether, 0.335 ether);

        vm.expectEmit(true, true, true, true);
        emit StrategySharesFastRedeemed(address(strategyA), 20_000_000, expectedAmounts[0]);

        vm.expectEmit(true, true, true, true);
        emit StrategySharesFastRedeemed(address(strategyB), 5_000_000, expectedAmounts[1]);

        smartVaultManager.redeemFast(
            RedeemBag(address(mySmartVault), 2_000_000, new uint256[](0), new uint256[](0)), withdrawalSlippages
        );
        vm.stopPrank();
    }

    function test_redeemFast_revertInvalidArrayLength() public {
        // withdraw fast
        uint256[][] memory withdrawalSlippages = new uint256[][](2);
        withdrawalSlippages[0] = new uint256[](0);
        withdrawalSlippages[1] = new uint256[](0);

        // invalid nft ids length
        vm.startPrank(alice);
        uint256[] memory nftIds = Arrays.toArray(1, 2);
        vm.expectRevert(abi.encodeWithSelector(InvalidNftArrayLength.selector));
        smartVaultManager.redeemFast(
            RedeemBag(address(mySmartVault), 3_000_000, nftIds, new uint256[](0)), withdrawalSlippages
        );
        vm.stopPrank();
    }

    function test_redeemFast_shouldSkipGhostStrategies() public {
        // set initial state
        deal(address(mySmartVault), alice, 4_000_000, true);
        deal(address(mySmartVault), bob, 1_000_000, true);
        deal(address(strategyA), address(mySmartVault), 40_000_000, true);
        deal(address(strategyB), address(mySmartVault), 10_000_000, true);
        deal(address(tokenA), address(strategyA.protocol()), 40 ether, true);
        deal(address(tokenB), address(strategyA.protocol()), 2.72 ether, true);
        deal(address(tokenA), address(strategyB.protocol()), 10 ether, true);
        deal(address(tokenB), address(strategyB.protocol()), 0.67 ether, true);

        // remove strategy A
        smartVaultManager.removeStrategyFromVaults(address(strategyA), Arrays.toArray(address(mySmartVault)), true);

        // Alice withdraws fast
        uint256[][] memory withdrawalSlippages = new uint256[][](2);
        withdrawalSlippages[0] = new uint256[](0);
        withdrawalSlippages[1] = new uint256[](0);

        vm.startPrank(alice);
        smartVaultManager.redeemFast(
            RedeemBag(address(mySmartVault), 4_000_000, new uint256[](0), new uint256[](0)), withdrawalSlippages
        );
        vm.stopPrank();

        // check state
        // - vault tokens were burned
        assertEq(mySmartVault.balanceOf(alice), 0);
        assertEq(mySmartVault.totalSupply(), 1_000_000);
        // - strategy tokens were burned
        assertEq(strategyA.balanceOf(address(mySmartVault)), 40_000_000); // replaced with ghost
        assertEq(strategyB.balanceOf(address(mySmartVault)), 2_000_000);
        assertEq(strategyA.totalSupply(), 40_000_000); // replaced with ghost
        assertEq(strategyB.totalSupply(), 2_000_000);
        // - assets were transferred to Alice
        assertEq(tokenA.balanceOf(alice), 8 ether);
        assertEq(tokenB.balanceOf(alice), 0.536 ether);
        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 40 ether); // replaced with ghost
        assertEq(tokenB.balanceOf(address(strategyA.protocol())), 2.72 ether); // replaced with ghost
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 2 ether);
        assertEq(tokenB.balanceOf(address(strategyB.protocol())), 0.134 ether);
    }

    function test_redeemFast_shouldRevertWhenRedeemingMoreSharesThanOwn() public {
        // set initial state
        deal(address(mySmartVault), alice, 4_000_000, true);
        deal(address(mySmartVault), bob, 1_000_000, true);
        deal(address(strategyA), address(mySmartVault), 40_000_000, true);
        deal(address(strategyB), address(mySmartVault), 10_000_000, true);
        deal(address(tokenA), address(strategyA.protocol()), 40 ether, true);
        deal(address(tokenB), address(strategyA.protocol()), 2.72 ether, true);
        deal(address(tokenA), address(strategyB.protocol()), 10 ether, true);
        deal(address(tokenB), address(strategyB.protocol()), 0.67 ether, true);

        // withdraw fast
        uint256[][] memory withdrawalSlippages = new uint256[][](2);
        withdrawalSlippages[0] = new uint256[](0);
        withdrawalSlippages[1] = new uint256[](0);

        vm.startPrank(alice);
        RedeemBag memory params = RedeemBag(address(mySmartVault), 5_000_000, new uint256[](0), new uint256[](0));
        vm.expectRevert("ERC20: burn amount exceeds balance");
        smartVaultManager.redeemFast(params, withdrawalSlippages);
        vm.stopPrank();
    }

    function test_emergencyWithdraw_revertMissingRole() public {
        uint256[][] memory withdrawalSlippages = new uint256[][](2);
        withdrawalSlippages[0] = new uint256[](0);
        withdrawalSlippages[1] = new uint256[](0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_EMERGENCY_WITHDRAWAL_EXECUTOR, alice));
        strategyRegistry.emergencyWithdraw(mySmartVaultStrategies, withdrawalSlippages, true);
    }

    function test_emergencyWithdraw_ok() public {
        // set initial state
        deal(address(strategyA), address(mySmartVault), 40_000_000, true);
        deal(address(strategyB), address(mySmartVault), 10_000_000, true);
        deal(address(tokenA), address(strategyA.protocol()), 40 ether, true);
        deal(address(tokenB), address(strategyA.protocol()), 2.72 ether, true);
        deal(address(tokenA), address(strategyB.protocol()), 10 ether, true);
        deal(address(tokenB), address(strategyB.protocol()), 0.67 ether, true);

        // withdraw fast
        uint256[][] memory withdrawalSlippages = new uint256[][](2);
        withdrawalSlippages[0] = new uint256[](0);
        withdrawalSlippages[1] = new uint256[](0);

        accessControl.grantRole(ROLE_EMERGENCY_WITHDRAWAL_EXECUTOR, alice);
        vm.prank(alice);
        strategyRegistry.emergencyWithdraw(mySmartVaultStrategies, withdrawalSlippages, true);

        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 0);
        assertEq(tokenB.balanceOf(address(strategyA.protocol())), 0);
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 0);
        assertEq(tokenB.balanceOf(address(strategyB.protocol())), 0);

        assertEq(tokenA.balanceOf(emergencyWithdrawalWallet), 40 ether + 10 ether);
        assertEq(tokenB.balanceOf(emergencyWithdrawalWallet), 2.72 ether + 0.67 ether);
    }

    function test_emergencyWithdraw_shouldSkipGhostStrategy() public {
        // set initial state
        deal(address(strategyA), address(mySmartVault), 40_000_000, true);
        deal(address(tokenA), address(strategyA.protocol()), 40 ether, true);
        deal(address(tokenB), address(strategyA.protocol()), 2.72 ether, true);

        // withdraw fast
        uint256[][] memory withdrawalSlippages = new uint256[][](2);
        withdrawalSlippages[0] = new uint256[](0);
        withdrawalSlippages[1] = new uint256[](0);

        strategyRegistry.setEmergencyWithdrawalWallet(address(0xabc));

        accessControl.grantRole(ROLE_EMERGENCY_WITHDRAWAL_EXECUTOR, alice);
        vm.startPrank(alice);
        strategyRegistry.emergencyWithdraw(
            Arrays.toArray(address(ghostStrategy), address(strategyA)), withdrawalSlippages, true
        );
        vm.stopPrank();

        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 0);
        assertEq(tokenB.balanceOf(address(strategyA.protocol())), 0);
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 0);
        assertEq(tokenB.balanceOf(address(strategyB.protocol())), 0);

        assertEq(tokenA.balanceOf(address(0xabc)), 40 ether);
        assertEq(tokenB.balanceOf(address(0xabc)), 2.72 ether);
    }

    function test_redeemStrategyShares_shouldSkipGhostStrategy() public {
        // set initial state
        deal(address(strategyA), alice, 40_000_000, true);
        deal(address(tokenA), address(strategyA.protocol()), 40 ether, true);
        deal(address(tokenB), address(strategyA.protocol()), 2.72 ether, true);

        // redeem strategy shares
        uint256[][] memory withdrawalSlippages = new uint256[][](2);
        withdrawalSlippages[0] = new uint256[](0);
        withdrawalSlippages[1] = new uint256[](0);

        vm.startPrank(alice);
        strategyRegistry.redeemStrategyShares(
            Arrays.toArray(address(ghostStrategy), address(strategyA)),
            Arrays.toArray(40_000_000, 40_000_000),
            withdrawalSlippages
        );
        vm.stopPrank();

        assertEq(tokenA.balanceOf(address(strategyA.protocol())), 0);
        assertEq(tokenB.balanceOf(address(strategyA.protocol())), 0);
        assertEq(tokenA.balanceOf(address(strategyB.protocol())), 0);
        assertEq(tokenB.balanceOf(address(strategyB.protocol())), 0);

        assertEq(tokenA.balanceOf(alice), 40 ether);
        assertEq(tokenB.balanceOf(alice), 2.72 ether);
    }

    function test_claimWithdrawal_shouldRevertWhenTryingToClaimUnsyncedNfts() public {
        // set initial state
        deal(address(mySmartVault), alice, 4_000_000, true);
        deal(address(mySmartVault), bob, 1_000_000, true);
        deal(address(strategyA), address(mySmartVault), 40_000_000, true);
        deal(address(strategyB), address(mySmartVault), 10_000_000, true);
        deal(address(tokenA), address(strategyA.protocol()), 40 ether, true);
        deal(address(tokenB), address(strategyA.protocol()), 2.72 ether, true);
        deal(address(tokenA), address(strategyB.protocol()), 10 ether, true);
        deal(address(tokenB), address(strategyB.protocol()), 0.67 ether, true);

        // request withdrawal
        vm.prank(alice);
        uint256 aliceWithdrawalNftId = smartVaultManager.redeem(
            RedeemBag(address(mySmartVault), 3_000_000, new uint256[](0), new uint256[](0)), alice, false
        );

        // flush
        smartVaultManager.flushSmartVault(address(mySmartVault));

        // claim withdrawal
        uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);
        uint256[] memory ids = Arrays.toArray(aliceWithdrawalNftId);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalNftNotSyncedYet.selector, aliceWithdrawalNftId));
        vm.prank(alice);
        smartVaultManager.claimWithdrawal(address(mySmartVault), ids, amounts, alice);
    }

    function test_removeStrategyBeforeWithdrawal() public {
        {
            // set initial state
            deal(address(mySmartVault), alice, 4_000_000, true);
            deal(address(mySmartVault), bob, 1_000_000, true);
            deal(address(strategyA), address(mySmartVault), 40_000_000, true);
            deal(address(strategyB), address(mySmartVault), 10_000_000, true);
            deal(address(tokenA), address(strategyA.protocol()), 40 ether, true);
            deal(address(tokenB), address(strategyA.protocol()), 2.72 ether, true);
            deal(address(tokenA), address(strategyB.protocol()), 10 ether, true);
            deal(address(tokenB), address(strategyB.protocol()), 0.67 ether, true);
        }

        {
            // remove strategy A
            smartVaultManager.removeStrategyFromVaults(address(strategyA), Arrays.toArray(address(mySmartVault)), true);
        }

        uint256 aliceWithdrawalNftId;
        uint256 bobWithdrawalNftId;
        {
            // request withdrawal
            vm.prank(alice);
            aliceWithdrawalNftId = smartVaultManager.redeem(
                RedeemBag(address(mySmartVault), 3_000_000, new uint256[](0), new uint256[](0)), alice, false
            );

            vm.prank(bob);
            bobWithdrawalNftId = smartVaultManager.redeem(
                RedeemBag(address(mySmartVault), 200_000, new uint256[](0), new uint256[](0)), bob, false
            );

            // check state
            // - vault tokens are returned to vault
            assertEq(mySmartVault.balanceOf(alice), 1_000_000);
            assertEq(mySmartVault.balanceOf(bob), 800_000);
            assertEq(mySmartVault.balanceOf(address(mySmartVault)), 3_200_000);
            // - withdrawal NFTs are minted
            assertEq(aliceWithdrawalNftId, 2 ** 255 + 1);
            assertEq(bobWithdrawalNftId, 2 ** 255 + 2);
            assertEq(mySmartVault.balanceOfFractional(alice, aliceWithdrawalNftId), NFT_MINTED_SHARES);
            assertEq(mySmartVault.balanceOf(alice, aliceWithdrawalNftId), 1);
            assertEq(mySmartVault.balanceOfFractional(bob, bobWithdrawalNftId), NFT_MINTED_SHARES);
            assertEq(mySmartVault.balanceOf(bob, bobWithdrawalNftId), 1);
        }

        {
            // flush
            smartVaultManager.flushSmartVault(address(mySmartVault));

            // check state
            // - vault tokens are burned
            assertEq(mySmartVault.balanceOf(address(mySmartVault)), 0);
            // - strategy B tokens are returned to strategy B, strategy A tokens remain
            assertEq(strategyA.balanceOf(address(mySmartVault)), 40_000_000);
            assertEq(strategyB.balanceOf(address(mySmartVault)), 3_600_000);
            assertEq(strategyA.balanceOf(address(strategyA)), 0);
            assertEq(strategyB.balanceOf(address(strategyB)), 6_400_000);
        }

        {
            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(Arrays.toArray(address(strategyB)), assetGroup));
            vm.stopPrank();

            // check state
            // - strategy B tokens are burned
            assertEq(strategyB.balanceOf(address(strategyB)), 0);
            // - assets are withdrawn from protocol B to master wallet and left on protocol A
            assertEq(tokenA.balanceOf(address(masterWallet)), 6.4 ether);
            assertEq(tokenB.balanceOf(address(masterWallet)), 0.4288 ether);
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 40 ether);
            assertEq(tokenB.balanceOf(address(strategyA.protocol())), 2.72 ether);
            assertEq(tokenA.balanceOf(address(strategyB.protocol())), 3.6 ether);
            assertEq(tokenB.balanceOf(address(strategyB.protocol())), 0.2412 ether);
        }

        {
            // sync vault
            smartVaultManager.syncSmartVault(address(mySmartVault), true);
        }

        {
            // claim withdrawal
            uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);
            uint256[] memory ids = Arrays.toArray(aliceWithdrawalNftId);
            vm.prank(alice);
            smartVaultManager.claimWithdrawal(address(mySmartVault), ids, amounts, alice);

            ids = Arrays.toArray(bobWithdrawalNftId);
            vm.prank(bob);
            smartVaultManager.claimWithdrawal(address(mySmartVault), ids, amounts, bob);

            // check state
            // - assets are transfered to withdrawers
            assertEq(tokenA.balanceOf(alice), 6 ether);
            assertEq(tokenB.balanceOf(alice), 0.402 ether);
            assertEq(tokenA.balanceOf(bob), 0.4 ether);
            assertEq(tokenB.balanceOf(bob), 0.0268 ether);
            assertEq(tokenA.balanceOf(address(masterWallet)), 0);
            assertEq(tokenB.balanceOf(address(masterWallet)), 0);
            // - withdrawal NFTs are burned
            assertEq(mySmartVault.balanceOfFractional(alice, aliceWithdrawalNftId), 0);
            assertEq(mySmartVault.balanceOfFractional(bob, bobWithdrawalNftId), 0);
            assertEq(mySmartVault.balanceOf(bob, bobWithdrawalNftId), 0);
        }
    }

    function test_removeStrategyAfterWithdrawalAndBeforeFlush() public {
        {
            // set initial state
            deal(address(mySmartVault), alice, 4_000_000, true);
            deal(address(mySmartVault), bob, 1_000_000, true);
            deal(address(strategyA), address(mySmartVault), 40_000_000, true);
            deal(address(strategyB), address(mySmartVault), 10_000_000, true);
            deal(address(tokenA), address(strategyA.protocol()), 40 ether, true);
            deal(address(tokenB), address(strategyA.protocol()), 2.72 ether, true);
            deal(address(tokenA), address(strategyB.protocol()), 10 ether, true);
            deal(address(tokenB), address(strategyB.protocol()), 0.67 ether, true);
        }

        uint256 aliceWithdrawalNftId;
        uint256 bobWithdrawalNftId;
        {
            // request withdrawal
            vm.prank(alice);
            aliceWithdrawalNftId = smartVaultManager.redeem(
                RedeemBag(address(mySmartVault), 3_000_000, new uint256[](0), new uint256[](0)), alice, false
            );

            vm.prank(bob);
            bobWithdrawalNftId = smartVaultManager.redeem(
                RedeemBag(address(mySmartVault), 200_000, new uint256[](0), new uint256[](0)), bob, false
            );

            // check state
            // - vault tokens are returned to vault
            assertEq(mySmartVault.balanceOf(alice), 1_000_000);
            assertEq(mySmartVault.balanceOf(bob), 800_000);
            assertEq(mySmartVault.balanceOf(address(mySmartVault)), 3_200_000);
            // - withdrawal NFTs are minted
            assertEq(aliceWithdrawalNftId, 2 ** 255 + 1);
            assertEq(bobWithdrawalNftId, 2 ** 255 + 2);
            assertEq(mySmartVault.balanceOfFractional(alice, aliceWithdrawalNftId), NFT_MINTED_SHARES);
            assertEq(mySmartVault.balanceOf(alice, aliceWithdrawalNftId), 1);
            assertEq(mySmartVault.balanceOfFractional(bob, bobWithdrawalNftId), NFT_MINTED_SHARES);
            assertEq(mySmartVault.balanceOf(bob, bobWithdrawalNftId), 1);
        }

        {
            // remove strategy A
            smartVaultManager.removeStrategyFromVaults(address(strategyA), Arrays.toArray(address(mySmartVault)), true);
        }

        {
            // flush
            smartVaultManager.flushSmartVault(address(mySmartVault));

            // check state
            // - vault tokens are burned
            assertEq(mySmartVault.balanceOf(address(mySmartVault)), 0);
            // - strategy B tokens are returned to strategy B, strategy A tokens remain
            assertEq(strategyA.balanceOf(address(mySmartVault)), 40_000_000);
            assertEq(strategyB.balanceOf(address(mySmartVault)), 3_600_000);
            assertEq(strategyA.balanceOf(address(strategyA)), 0);
            assertEq(strategyB.balanceOf(address(strategyB)), 6_400_000);
        }

        {
            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(Arrays.toArray(address(strategyB)), assetGroup));
            vm.stopPrank();

            // check state
            // - strategy B tokens are burned
            assertEq(strategyB.balanceOf(address(strategyB)), 0);
            // - assets are withdrawn from protocol B to master wallet and left on protocol A
            assertEq(tokenA.balanceOf(address(masterWallet)), 6.4 ether);
            assertEq(tokenB.balanceOf(address(masterWallet)), 0.4288 ether);
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 40 ether);
            assertEq(tokenB.balanceOf(address(strategyA.protocol())), 2.72 ether);
            assertEq(tokenA.balanceOf(address(strategyB.protocol())), 3.6 ether);
            assertEq(tokenB.balanceOf(address(strategyB.protocol())), 0.2412 ether);
        }

        {
            // sync vault
            smartVaultManager.syncSmartVault(address(mySmartVault), true);
        }

        {
            // claim withdrawal
            uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);
            uint256[] memory ids = Arrays.toArray(aliceWithdrawalNftId);
            vm.prank(alice);
            smartVaultManager.claimWithdrawal(address(mySmartVault), ids, amounts, alice);

            ids = Arrays.toArray(bobWithdrawalNftId);
            vm.prank(bob);
            smartVaultManager.claimWithdrawal(address(mySmartVault), ids, amounts, bob);

            // check state
            // - assets are transfered to withdrawers
            assertEq(tokenA.balanceOf(alice), 6 ether);
            assertEq(tokenB.balanceOf(alice), 0.402 ether);
            assertEq(tokenA.balanceOf(bob), 0.4 ether);
            assertEq(tokenB.balanceOf(bob), 0.0268 ether);
            assertEq(tokenA.balanceOf(address(masterWallet)), 0);
            assertEq(tokenB.balanceOf(address(masterWallet)), 0);
            // - withdrawal NFTs are burned
            assertEq(mySmartVault.balanceOfFractional(alice, aliceWithdrawalNftId), 0);
            assertEq(mySmartVault.balanceOfFractional(bob, bobWithdrawalNftId), 0);
            assertEq(mySmartVault.balanceOf(bob, bobWithdrawalNftId), 0);
        }
    }

    function test_removeStrategyAfterFlushAndBeforeDhw() public {
        {
            // set initial state
            deal(address(mySmartVault), alice, 4_000_000, true);
            deal(address(mySmartVault), bob, 1_000_000, true);
            deal(address(strategyA), address(mySmartVault), 40_000_000, true);
            deal(address(strategyB), address(mySmartVault), 10_000_000, true);
            deal(address(tokenA), address(strategyA.protocol()), 40 ether, true);
            deal(address(tokenB), address(strategyA.protocol()), 2.72 ether, true);
            deal(address(tokenA), address(strategyB.protocol()), 10 ether, true);
            deal(address(tokenB), address(strategyB.protocol()), 0.67 ether, true);
        }

        uint256 aliceWithdrawalNftId;
        uint256 bobWithdrawalNftId;
        {
            // request withdrawal
            vm.prank(alice);
            aliceWithdrawalNftId = smartVaultManager.redeem(
                RedeemBag(address(mySmartVault), 3_000_000, new uint256[](0), new uint256[](0)), alice, false
            );

            vm.prank(bob);
            bobWithdrawalNftId = smartVaultManager.redeem(
                RedeemBag(address(mySmartVault), 200_000, new uint256[](0), new uint256[](0)), bob, false
            );

            // check state
            // - vault tokens are returned to vault
            assertEq(mySmartVault.balanceOf(alice), 1_000_000);
            assertEq(mySmartVault.balanceOf(bob), 800_000);
            assertEq(mySmartVault.balanceOf(address(mySmartVault)), 3_200_000);
            // - withdrawal NFTs are minted
            assertEq(aliceWithdrawalNftId, 2 ** 255 + 1);
            assertEq(bobWithdrawalNftId, 2 ** 255 + 2);
            assertEq(mySmartVault.balanceOfFractional(alice, aliceWithdrawalNftId), NFT_MINTED_SHARES);
            assertEq(mySmartVault.balanceOf(alice, aliceWithdrawalNftId), 1);
            assertEq(mySmartVault.balanceOfFractional(bob, bobWithdrawalNftId), NFT_MINTED_SHARES);
            assertEq(mySmartVault.balanceOf(bob, bobWithdrawalNftId), 1);
        }

        {
            // flush
            smartVaultManager.flushSmartVault(address(mySmartVault));

            // check state
            // - vault tokens are burned
            assertEq(mySmartVault.balanceOf(address(mySmartVault)), 0);
            // - strategy tokens are returned to strategies
            assertEq(strategyA.balanceOf(address(mySmartVault)), 14_400_000);
            assertEq(strategyB.balanceOf(address(mySmartVault)), 3_600_000);
            assertEq(strategyA.balanceOf(address(strategyA)), 25_600_000);
            assertEq(strategyB.balanceOf(address(strategyB)), 6_400_000);
        }

        {
            // remove strategy A
            smartVaultManager.removeStrategyFromVaults(address(strategyA), Arrays.toArray(address(mySmartVault)), true);
        }

        {
            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(Arrays.toArray(address(strategyB)), assetGroup));
            vm.stopPrank();

            // check state
            // - strategy B tokens are burned
            assertEq(strategyB.balanceOf(address(strategyB)), 0);
            // - assets are withdrawn from protocol B to master wallet and left on protocol A
            assertEq(tokenA.balanceOf(address(masterWallet)), 6.4 ether);
            assertEq(tokenB.balanceOf(address(masterWallet)), 0.4288 ether);
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 40 ether);
            assertEq(tokenB.balanceOf(address(strategyA.protocol())), 2.72 ether);
            assertEq(tokenA.balanceOf(address(strategyB.protocol())), 3.6 ether);
            assertEq(tokenB.balanceOf(address(strategyB.protocol())), 0.2412 ether);
        }

        {
            // sync vault
            smartVaultManager.syncSmartVault(address(mySmartVault), true);
        }

        {
            // claim withdrawal
            uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);
            uint256[] memory ids = Arrays.toArray(aliceWithdrawalNftId);
            vm.prank(alice);
            smartVaultManager.claimWithdrawal(address(mySmartVault), ids, amounts, alice);

            ids = Arrays.toArray(bobWithdrawalNftId);
            vm.prank(bob);
            smartVaultManager.claimWithdrawal(address(mySmartVault), ids, amounts, bob);

            // check state
            // - assets are transfered to withdrawers
            assertEq(tokenA.balanceOf(alice), 6 ether);
            assertEq(tokenB.balanceOf(alice), 0.402 ether);
            assertEq(tokenA.balanceOf(bob), 0.4 ether);
            assertEq(tokenB.balanceOf(bob), 0.0268 ether);
            assertEq(tokenA.balanceOf(address(masterWallet)), 0);
            assertEq(tokenB.balanceOf(address(masterWallet)), 0);
            // - withdrawal NFTs are burned
            assertEq(mySmartVault.balanceOfFractional(alice, aliceWithdrawalNftId), 0);
            assertEq(mySmartVault.balanceOfFractional(bob, bobWithdrawalNftId), 0);
            assertEq(mySmartVault.balanceOf(bob, bobWithdrawalNftId), 0);
        }
    }

    function test_removeStrategyAfterDhwAndBeforeSync() public {
        {
            // set initial state
            deal(address(mySmartVault), alice, 4_000_000, true);
            deal(address(mySmartVault), bob, 1_000_000, true);
            deal(address(strategyA), address(mySmartVault), 40_000_000, true);
            deal(address(strategyB), address(mySmartVault), 10_000_000, true);
            deal(address(tokenA), address(strategyA.protocol()), 40 ether, true);
            deal(address(tokenB), address(strategyA.protocol()), 2.72 ether, true);
            deal(address(tokenA), address(strategyB.protocol()), 10 ether, true);
            deal(address(tokenB), address(strategyB.protocol()), 0.67 ether, true);
        }

        uint256 aliceWithdrawalNftId;
        uint256 bobWithdrawalNftId;
        {
            // request withdrawal
            vm.prank(alice);
            aliceWithdrawalNftId = smartVaultManager.redeem(
                RedeemBag(address(mySmartVault), 3_000_000, new uint256[](0), new uint256[](0)), alice, false
            );

            vm.prank(bob);
            bobWithdrawalNftId = smartVaultManager.redeem(
                RedeemBag(address(mySmartVault), 200_000, new uint256[](0), new uint256[](0)), bob, false
            );

            // check state
            // - vault tokens are returned to vault
            assertEq(mySmartVault.balanceOf(alice), 1_000_000);
            assertEq(mySmartVault.balanceOf(bob), 800_000);
            assertEq(mySmartVault.balanceOf(address(mySmartVault)), 3_200_000);
            // - withdrawal NFTs are minted
            assertEq(aliceWithdrawalNftId, 2 ** 255 + 1);
            assertEq(bobWithdrawalNftId, 2 ** 255 + 2);
            assertEq(mySmartVault.balanceOfFractional(alice, aliceWithdrawalNftId), NFT_MINTED_SHARES);
            assertEq(mySmartVault.balanceOf(alice, aliceWithdrawalNftId), 1);
            assertEq(mySmartVault.balanceOfFractional(bob, bobWithdrawalNftId), NFT_MINTED_SHARES);
            assertEq(mySmartVault.balanceOf(bob, bobWithdrawalNftId), 1);
        }

        {
            // flush
            smartVaultManager.flushSmartVault(address(mySmartVault));

            // check state
            // - vault tokens are burned
            assertEq(mySmartVault.balanceOf(address(mySmartVault)), 0);
            // - strategy tokens are returned to strategies
            assertEq(strategyA.balanceOf(address(mySmartVault)), 14_400_000);
            assertEq(strategyB.balanceOf(address(mySmartVault)), 3_600_000);
            assertEq(strategyA.balanceOf(address(strategyA)), 25_600_000);
            assertEq(strategyB.balanceOf(address(strategyB)), 6_400_000);
        }

        {
            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(
                generateDhwParameterBag(Arrays.toArray(address(strategyA), address(strategyB)), assetGroup)
            );
            vm.stopPrank();

            // check state
            // - strategy tokens are burned
            assertEq(strategyA.balanceOf(address(strategyA)), 0);
            assertEq(strategyB.balanceOf(address(strategyB)), 0);
            // - assets are withdrawn from protocols to master wallet
            assertEq(tokenA.balanceOf(address(masterWallet)), 32 ether);
            assertEq(tokenB.balanceOf(address(masterWallet)), 2.1696 ether);
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 14.4 ether);
            assertEq(tokenB.balanceOf(address(strategyA.protocol())), 0.9792 ether);
            assertEq(tokenA.balanceOf(address(strategyB.protocol())), 3.6 ether);
            assertEq(tokenB.balanceOf(address(strategyB.protocol())), 0.2412 ether);
        }

        {
            // remove strategy A
            smartVaultManager.removeStrategyFromVaults(address(strategyA), Arrays.toArray(address(mySmartVault)), true);

            // check state
            // - assets from strategy A are moved from master wallet to emergency withdrawal recipient
            assertEq(tokenA.balanceOf(address(masterWallet)), 6.4 ether);
            assertEq(tokenB.balanceOf(address(masterWallet)), 0.4288 ether);
            assertEq(tokenA.balanceOf(address(emergencyWithdrawalWallet)), 25.6 ether);
            assertEq(tokenB.balanceOf(address(emergencyWithdrawalWallet)), 1.7408 ether);
        }

        {
            // sync vault
            smartVaultManager.syncSmartVault(address(mySmartVault), true);
        }

        {
            // claim withdrawal
            uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);
            uint256[] memory ids = Arrays.toArray(aliceWithdrawalNftId);
            vm.prank(alice);
            smartVaultManager.claimWithdrawal(address(mySmartVault), ids, amounts, alice);

            ids = Arrays.toArray(bobWithdrawalNftId);
            vm.prank(bob);
            smartVaultManager.claimWithdrawal(address(mySmartVault), ids, amounts, bob);

            // check state
            // - assets from strategy B are transfered to withdrawers
            assertEq(tokenA.balanceOf(alice), 6 ether);
            assertEq(tokenB.balanceOf(alice), 0.402 ether);
            assertEq(tokenA.balanceOf(bob), 0.4 ether);
            assertEq(tokenB.balanceOf(bob), 0.0268 ether);
            assertEq(tokenA.balanceOf(address(masterWallet)), 0);
            assertEq(tokenB.balanceOf(address(masterWallet)), 0);
            // - withdrawal NFTs are burned
            assertEq(mySmartVault.balanceOfFractional(alice, aliceWithdrawalNftId), 0);
            assertEq(mySmartVault.balanceOfFractional(bob, bobWithdrawalNftId), 0);
            assertEq(mySmartVault.balanceOf(bob, bobWithdrawalNftId), 0);
        }
    }

    function test_removeStrategyAfterSyncAndBeforeClaim() public {
        {
            // set initial state
            deal(address(mySmartVault), alice, 4_000_000, true);
            deal(address(mySmartVault), bob, 1_000_000, true);
            deal(address(strategyA), address(mySmartVault), 40_000_000, true);
            deal(address(strategyB), address(mySmartVault), 10_000_000, true);
            deal(address(tokenA), address(strategyA.protocol()), 40 ether, true);
            deal(address(tokenB), address(strategyA.protocol()), 2.72 ether, true);
            deal(address(tokenA), address(strategyB.protocol()), 10 ether, true);
            deal(address(tokenB), address(strategyB.protocol()), 0.67 ether, true);
        }

        uint256 aliceWithdrawalNftId;
        uint256 bobWithdrawalNftId;
        {
            // request withdrawal
            vm.prank(alice);
            aliceWithdrawalNftId = smartVaultManager.redeem(
                RedeemBag(address(mySmartVault), 3_000_000, new uint256[](0), new uint256[](0)), alice, false
            );

            vm.prank(bob);
            bobWithdrawalNftId = smartVaultManager.redeem(
                RedeemBag(address(mySmartVault), 200_000, new uint256[](0), new uint256[](0)), bob, false
            );

            // check state
            // - vault tokens are returned to vault
            assertEq(mySmartVault.balanceOf(alice), 1_000_000);
            assertEq(mySmartVault.balanceOf(bob), 800_000);
            assertEq(mySmartVault.balanceOf(address(mySmartVault)), 3_200_000);
            // - withdrawal NFTs are minted
            assertEq(aliceWithdrawalNftId, 2 ** 255 + 1);
            assertEq(bobWithdrawalNftId, 2 ** 255 + 2);
            assertEq(mySmartVault.balanceOfFractional(alice, aliceWithdrawalNftId), NFT_MINTED_SHARES);
            assertEq(mySmartVault.balanceOf(alice, aliceWithdrawalNftId), 1);
            assertEq(mySmartVault.balanceOfFractional(bob, bobWithdrawalNftId), NFT_MINTED_SHARES);
            assertEq(mySmartVault.balanceOf(bob, bobWithdrawalNftId), 1);
        }

        {
            // flush
            smartVaultManager.flushSmartVault(address(mySmartVault));

            // check state
            // - vault tokens are burned
            assertEq(mySmartVault.balanceOf(address(mySmartVault)), 0);
            // - strategy tokens are returned to strategies
            assertEq(strategyA.balanceOf(address(mySmartVault)), 14_400_000);
            assertEq(strategyB.balanceOf(address(mySmartVault)), 3_600_000);
            assertEq(strategyA.balanceOf(address(strategyA)), 25_600_000);
            assertEq(strategyB.balanceOf(address(strategyB)), 6_400_000);
        }

        {
            // DHW
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(
                generateDhwParameterBag(Arrays.toArray(address(strategyA), address(strategyB)), assetGroup)
            );
            vm.stopPrank();

            // check state
            // - strategy tokens are burned
            assertEq(strategyA.balanceOf(address(strategyA)), 0);
            assertEq(strategyB.balanceOf(address(strategyB)), 0);
            // - assets are withdrawn from protocols to master wallet
            assertEq(tokenA.balanceOf(address(masterWallet)), 32 ether);
            assertEq(tokenB.balanceOf(address(masterWallet)), 2.1696 ether);
            assertEq(tokenA.balanceOf(address(strategyA.protocol())), 14.4 ether);
            assertEq(tokenB.balanceOf(address(strategyA.protocol())), 0.9792 ether);
            assertEq(tokenA.balanceOf(address(strategyB.protocol())), 3.6 ether);
            assertEq(tokenB.balanceOf(address(strategyB.protocol())), 0.2412 ether);
        }

        {
            // sync vault
            smartVaultManager.syncSmartVault(address(mySmartVault), true);
        }

        {
            // remove strategy A
            smartVaultManager.removeStrategyFromVaults(address(strategyA), Arrays.toArray(address(mySmartVault)), true);

            // check state
            // - no assets moved from master wallet to emergency withdrawal recipient
            assertEq(tokenA.balanceOf(address(masterWallet)), 32 ether);
            assertEq(tokenB.balanceOf(address(masterWallet)), 2.1696 ether);
            assertEq(tokenA.balanceOf(address(emergencyWithdrawalWallet)), 0 ether);
            assertEq(tokenB.balanceOf(address(emergencyWithdrawalWallet)), 0 ether);
        }

        {
            // claim withdrawal
            uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);
            uint256[] memory ids = Arrays.toArray(aliceWithdrawalNftId);
            vm.prank(alice);
            smartVaultManager.claimWithdrawal(address(mySmartVault), ids, amounts, alice);

            ids = Arrays.toArray(bobWithdrawalNftId);
            vm.prank(bob);
            smartVaultManager.claimWithdrawal(address(mySmartVault), ids, amounts, bob);

            // check state
            // - assets from strategy B are transfered to withdrawers
            assertEq(tokenA.balanceOf(alice), 30 ether);
            assertEq(tokenB.balanceOf(alice), 2.034 ether);
            assertEq(tokenA.balanceOf(bob), 2 ether);
            assertEq(tokenB.balanceOf(bob), 0.1356 ether);
            assertEq(tokenA.balanceOf(address(masterWallet)), 0);
            assertEq(tokenB.balanceOf(address(masterWallet)), 0);
            // - withdrawal NFTs are burned
            assertEq(mySmartVault.balanceOfFractional(alice, aliceWithdrawalNftId), 0);
            assertEq(mySmartVault.balanceOfFractional(bob, bobWithdrawalNftId), 0);
            assertEq(mySmartVault.balanceOf(bob, bobWithdrawalNftId), 0);
        }
    }
}
