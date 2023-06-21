// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../../src/access/SpoolAccessControl.sol";
import "../../src/libraries/uint16a16Lib.sol";
import "../../src/guards/AllowlistGuard.sol";
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
import "../../src/SmartVault.sol";
import "../../src/SmartVaultFactory.sol";
import "../../src/Swapper.sol";
import "../libraries/Arrays.sol";
import "../libraries/Constants.sol";
import "../libraries/TimeUtils.sol";
import "../mocks/MockPriceFeedManager.sol";
import "../mocks/MockStrategy.sol";
import "../mocks/MockToken.sol";

contract ScenariosTest is Test {
    using uint16a16Lib for uint16a16;

    address alice;
    address bob;

    address doHardWorker;
    address ecosystemFeeReceiver;
    address treasuryFeeReceiver;
    address emergencyWithdrawalWallet;
    address allocationProvider;
    address riskProvider;

    MockToken tokenA;
    MockToken tokenB;
    MockToken tokenC;

    address[] assetGroupA;
    address[] assetGroupAB;
    address[] assetGroupABC;

    uint256 assetGroupIdA;
    uint256 assetGroupIdAB;

    MockStrategy strategyA1;
    MockStrategy strategyA2;
    MockStrategy strategyAB1;

    SpoolAccessControl accessControl;
    ActionManager actionManager;
    AssetGroupRegistry assetGroupRegistry;
    DepositManager depositManager;
    GhostStrategy ghostStrategy;
    GuardManager guardManager;
    MasterWallet masterWallet;
    MockPriceFeedManager priceFeedManager;
    RiskManager riskManager;
    SmartVaultFactory smartVaultFactory;
    SmartVaultManager smartVaultManager;
    StrategyRegistry strategyRegistry;
    Swapper swapper;
    WithdrawalManager withdrawalManager;

    function setUp() public {
        {
            alice = address(0xa);
            bob = address(0xb);

            doHardWorker = address(0x1);
            ecosystemFeeReceiver = address(0x2);
            treasuryFeeReceiver = address(0x3);
            emergencyWithdrawalWallet = address(0x4);
            allocationProvider = address(0x5);
            riskProvider = address(0x6);
        }

        {
            assetGroupABC = Arrays.sort(
                Arrays.toArray(
                    address(new MockToken("Token", "T")),
                    address(new MockToken("Token", "T")),
                    address(new MockToken("Token", "T"))
                )
            );

            tokenA = MockToken(address(assetGroupABC[0]));
            tokenB = MockToken(address(assetGroupABC[1]));
            tokenC = MockToken(address(assetGroupABC[2]));

            assetGroupA = Arrays.toArray(address(tokenA));
            assetGroupAB = Arrays.toArray(address(tokenA), address(tokenB));

            tokenA.mint(alice, 100 ether);
            tokenB.mint(alice, 100 ether);
            tokenC.mint(alice, 100 ether);
            tokenA.mint(bob, 100 ether);
            tokenB.mint(bob, 100 ether);
            tokenC.mint(bob, 100 ether);
        }

        {
            accessControl = new SpoolAccessControl();
            accessControl.initialize();
            accessControl.grantRole(ROLE_ALLOCATION_PROVIDER, allocationProvider);
            accessControl.grantRole(ROLE_DO_HARD_WORKER, doHardWorker);
            accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);

            masterWallet = new MasterWallet(accessControl);

            swapper = new Swapper(accessControl);

            assetGroupRegistry = new AssetGroupRegistry(accessControl);
            assetGroupRegistry.initialize(assetGroupABC);
            assetGroupIdA = assetGroupRegistry.registerAssetGroup(assetGroupA);
            assetGroupIdAB = assetGroupRegistry.registerAssetGroup(assetGroupAB);

            ghostStrategy = new GhostStrategy();

            priceFeedManager = new MockPriceFeedManager();
            priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
            priceFeedManager.setExchangeRate(address(tokenB), 1 * USD_DECIMALS_MULTIPLIER);
            priceFeedManager.setExchangeRate(address(tokenC), 1 * USD_DECIMALS_MULTIPLIER);

            strategyRegistry =
                new StrategyRegistry(masterWallet, accessControl, priceFeedManager, address(ghostStrategy));
            strategyRegistry.initialize(0, 0, ecosystemFeeReceiver, treasuryFeeReceiver, emergencyWithdrawalWallet);
            accessControl.grantRole(ADMIN_ROLE_STRATEGY, address(strategyRegistry));
            accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(strategyRegistry));
            accessControl.grantRole(ROLE_STRATEGY_REGISTRY, address(strategyRegistry));

            actionManager = new ActionManager(accessControl);

            guardManager = new GuardManager(accessControl);

            riskManager = new RiskManager(accessControl, strategyRegistry, address(ghostStrategy));

            depositManager =
                new DepositManager(strategyRegistry, priceFeedManager, guardManager, actionManager, accessControl);
            accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(depositManager));
            accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(depositManager));

            withdrawalManager =
                new WithdrawalManager(strategyRegistry, masterWallet, guardManager, actionManager, accessControl);
            accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(withdrawalManager));
            accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(withdrawalManager));

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
            accessControl.grantRole(ADMIN_ROLE_SMART_VAULT_ALLOW_REDEEM, address(smartVaultFactory));
        }

        {
            strategyA1 = new MockStrategy(assetGroupRegistry, accessControl, swapper, assetGroupIdA);
            strategyA1.initialize("StratA1", Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyA1), 0);

            strategyA2 = new MockStrategy(assetGroupRegistry, accessControl, swapper, assetGroupIdA);
            strategyA2.initialize("StratA2", Arrays.toArray(1));
            strategyRegistry.registerStrategy(address(strategyA2), 0);

            strategyAB1 = new MockStrategy(assetGroupRegistry, accessControl, swapper, assetGroupIdAB);
            strategyAB1.initialize("StratAB1", Arrays.toArray(1, 1));
            strategyRegistry.registerStrategy(address(strategyAB1), 0);
        }
    }

    function test_deposit_shouldNotRevertWhenDepositingVerySmallAmount() public {
        address[] memory smartVaultStrategies = Arrays.toArray(address(strategyA1));
        ISmartVault smartVault =
            smartVaultFactory.deploySmartVault(getSmartVaultSpecification(assetGroupIdA, smartVaultStrategies));

        // arrange
        priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER / 1000);

        // - Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmounts = Arrays.toArray(10 ether);
        tokenA.approve(address(smartVaultManager), depositAmounts[0]);

        uint256 depositNftIdAlice = smartVaultManager.deposit(
            DepositBag({
                smartVault: address(smartVault),
                assets: depositAmounts,
                receiver: alice,
                referral: address(0x0),
                doFlush: false
            })
        );

        vm.stopPrank();

        // - flush
        smartVaultManager.flushSmartVault(address(smartVault));

        // - DHW
        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroupA));
        vm.stopPrank();

        // - sync vault
        smartVaultManager.syncSmartVault(address(smartVault), true);

        // - claim deposits
        vm.startPrank(alice);
        smartVaultManager.claimSmartVaultTokens(
            address(smartVault), Arrays.toArray(depositNftIdAlice), Arrays.toArray(NFT_MINTED_SHARES)
        );
        vm.stopPrank();

        // check initial state
        // - tokens were transferred
        assertEq(tokenA.balanceOf(alice), 90 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0);
        assertEq(tokenA.balanceOf(address(strategyA1.protocol())), 10 ether);
        // strategy tokens were minted
        assertEq(strategyA1.totalSupply(), 10000000000000000000);
        assertEq(strategyA1.balanceOf(address(smartVault)), 10000000000000000000);
        // - vault tokens were minted
        assertEq(smartVault.totalSupply(), 10000000000000000000);
        assertEq(smartVault.balanceOf(address(alice)), 10000000000000000000);

        // Bob deposits 1 wei of token A and flushes vault
        // - 1 wei of token A equal 0 USD with current exchange rate and because of rounding
        vm.startPrank(bob);

        depositAmounts = Arrays.toArray(1);
        tokenA.approve(address(smartVaultManager), depositAmounts[0]);

        uint256 depositNftIdBob = smartVaultManager.deposit(
            DepositBag({
                smartVault: address(smartVault),
                assets: depositAmounts,
                receiver: bob,
                referral: address(0x0),
                doFlush: true
            })
        );

        vm.stopPrank();

        // check state
        // - tokens were transferred
        assertEq(tokenA.balanceOf(bob), 100 ether - 1);
        assertEq(tokenA.balanceOf(address(masterWallet)), 1);

        // DHW
        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroupA));
        vm.stopPrank();

        // check state
        // - tokens were routed to the protocol
        //   but deposit value is zero, so tokens stay on strategy
        assertEq(tokenA.balanceOf(address(masterWallet)), 0);
        assertEq(tokenA.balanceOf(address(strategyA1)), 1);
        assertEq(tokenA.balanceOf(address(strategyA1.protocol())), 10 ether);
        // - strategy tokens were minted
        //   but there is nothing to mint
        assertEq(strategyA1.totalSupply(), 10000000000000000000);

        // sync vault
        smartVaultManager.syncSmartVault(address(smartVault), true);

        // check state
        // - strategy tokens were claimed
        //   but there should be nothing to claim since deposited value was zero
        assertEq(strategyA1.balanceOf(address(smartVault)), 10000000000000000000);
        // - vault tokens were minted
        //   but none should be minted
        assertEq(smartVault.totalSupply(), 10000000000000000000);

        // claim deposits
        vm.startPrank(bob);
        smartVaultManager.claimSmartVaultTokens(
            address(smartVault), Arrays.toArray(depositNftIdBob), Arrays.toArray(NFT_MINTED_SHARES)
        );
        vm.stopPrank();

        // check state
        // - vault tokens were claimed
        //   but there should be nothing to claim since deposited value was zero
        assertEq(smartVault.balanceOf(address(bob)), 0);
        // - deposit NFT was burned
        assertEq(smartVault.balanceOfFractional(bob, depositNftIdBob), 0);
    }

    function test_deposit_shouldRevertWhenOnlyGhostStrategies() public {
        address[] memory smartVaultStrategies = Arrays.toArray(address(strategyA1), address(strategyA2));
        ISmartVault smartVault =
            smartVaultFactory.deploySmartVault(getSmartVaultSpecification(assetGroupIdA, smartVaultStrategies));

        // Alice should be able to deposit
        vm.startPrank(alice);

        uint256[] memory depositAmounts = Arrays.toArray(10 ether);
        tokenA.approve(address(smartVaultManager), depositAmounts[0]);

        uint256 depositNftIdAlice = smartVaultManager.deposit(
            DepositBag({
                smartVault: address(smartVault),
                assets: depositAmounts,
                receiver: alice,
                referral: address(0x0),
                doFlush: false
            })
        );

        vm.stopPrank();

        // check state
        // - deposit NFTs were minted
        assertEq(depositNftIdAlice, 1);
        assertEq(smartVault.balanceOf(alice, depositNftIdAlice), 1);

        // strategy A1 is removed
        smartVaultManager.removeStrategyFromVaults(smartVaultStrategies[0], Arrays.toArray(address(smartVault)), true);

        // Alice should be able to deposit
        vm.startPrank(alice);

        depositAmounts = Arrays.toArray(10 ether);
        tokenA.approve(address(smartVaultManager), depositAmounts[0]);

        depositNftIdAlice = smartVaultManager.deposit(
            DepositBag({
                smartVault: address(smartVault),
                assets: depositAmounts,
                receiver: alice,
                referral: address(0x0),
                doFlush: false
            })
        );

        vm.stopPrank();

        // check state
        // - deposit NFTs were minted
        assertEq(depositNftIdAlice, 2);
        assertEq(smartVault.balanceOf(alice, depositNftIdAlice), 1);

        // strategy A2 is removed
        smartVaultManager.removeStrategyFromVaults(smartVaultStrategies[1], Arrays.toArray(address(smartVault)), true);

        // Alice should not be able to deposit
        vm.startPrank(alice);

        depositAmounts = Arrays.toArray(10 ether);
        tokenA.approve(address(smartVaultManager), depositAmounts[0]);

        vm.expectRevert(GhostVault.selector);
        smartVaultManager.deposit(
            DepositBag({
                smartVault: address(smartVault),
                assets: depositAmounts,
                receiver: alice,
                referral: address(0x0),
                doFlush: false
            })
        );

        vm.stopPrank();
    }

    function test_depositAndDonate_shouldNotRevertWhenDepositingVerySmallAmount() public {
        address[] memory smartVaultStrategies = Arrays.toArray(address(strategyA1));
        ISmartVault smartVault =
            smartVaultFactory.deploySmartVault(getSmartVaultSpecification(assetGroupIdA, smartVaultStrategies));

        // arrange
        priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER / 1000);

        // - Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmounts = Arrays.toArray(10 ether);
        tokenA.approve(address(smartVaultManager), depositAmounts[0]);

        uint256 depositNftIdAlice = smartVaultManager.deposit(
            DepositBag({
                smartVault: address(smartVault),
                assets: depositAmounts,
                receiver: alice,
                referral: address(0x0),
                doFlush: false
            })
        );

        vm.stopPrank();

        // - flush
        smartVaultManager.flushSmartVault(address(smartVault));

        // - DHW
        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroupA));
        vm.stopPrank();

        // - sync vault
        smartVaultManager.syncSmartVault(address(smartVault), true);

        // - claim deposits
        vm.startPrank(alice);
        smartVaultManager.claimSmartVaultTokens(
            address(smartVault), Arrays.toArray(depositNftIdAlice), Arrays.toArray(NFT_MINTED_SHARES)
        );
        vm.stopPrank();

        // check initial state
        // - tokens were transferred
        assertEq(tokenA.balanceOf(alice), 90 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0);
        assertEq(tokenA.balanceOf(address(strategyA1.protocol())), 10 ether);
        // strategy tokens were minted
        assertEq(strategyA1.totalSupply(), 10000000000000000000);
        assertEq(strategyA1.balanceOf(address(smartVault)), 10000000000000000000);
        // - vault tokens were minted
        assertEq(smartVault.totalSupply(), 10000000000000000000);
        assertEq(smartVault.balanceOf(address(alice)), 10000000000000000000);

        // Bob deposits 1 wei of token A and flushes vault
        // - 1 wei of token A equal 0 USD with current exchange rate and because of rounding
        vm.startPrank(bob);

        depositAmounts = Arrays.toArray(1);
        tokenA.approve(address(smartVaultManager), depositAmounts[0]);

        uint256 depositNftIdBob = smartVaultManager.deposit(
            DepositBag({
                smartVault: address(smartVault),
                assets: depositAmounts,
                receiver: bob,
                referral: address(0x0),
                doFlush: true
            })
        );

        // Bob donates 999 wei of token A to strategy A1
        // - this brings the USD value of token A waiting for deposit to non-zero
        tokenA.transfer(address(strategyA1), 999);

        vm.stopPrank();

        // check state
        // - tokens were transferred
        assertEq(tokenA.balanceOf(bob), 100 ether - 1000);
        assertEq(tokenA.balanceOf(address(masterWallet)), 1);
        assertEq(tokenA.balanceOf(address(strategyA1)), 999);

        // DHW
        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroupA));
        vm.stopPrank();

        // check state
        // - tokens were routed to the protocol
        assertEq(tokenA.balanceOf(address(masterWallet)), 0);
        assertEq(tokenA.balanceOf(address(strategyA1)), 0);
        assertEq(tokenA.balanceOf(address(strategyA1.protocol())), 10 ether + 1000);
        // - strategy tokens were minted
        assertEq(strategyA1.totalSupply(), 10000000000000001000);

        // sync vault
        smartVaultManager.syncSmartVault(address(smartVault), true);

        // check state
        // - strategy tokens were claimed
        //   but there should be nothing to claim since deposited value was zero
        assertEq(strategyA1.balanceOf(address(smartVault)), 10000000000000000000);
        // - vault tokens were minted
        //   but none should be minted
        assertEq(smartVault.totalSupply(), 10000000000000000000);

        // claim deposits
        vm.startPrank(bob);
        smartVaultManager.claimSmartVaultTokens(
            address(smartVault), Arrays.toArray(depositNftIdBob), Arrays.toArray(NFT_MINTED_SHARES)
        );
        vm.stopPrank();

        // check state
        // - vault tokens were claimed
        //   but there should be nothing to claim since deposited value was zero
        assertEq(smartVault.balanceOf(address(bob)), 0);
        // - deposit NFT was burned
        assertEq(smartVault.balanceOfFractional(bob, depositNftIdBob), 0);
    }

    function test_depositAndWithdraw_shouldProcessEvenIfFirstAssetHasZeroIdealWeight() public {
        address[] memory smartVaultStrategies = Arrays.toArray(address(strategyAB1));
        ISmartVault smartVault =
            smartVaultFactory.deploySmartVault(getSmartVaultSpecification(assetGroupIdAB, smartVaultStrategies));

        // arrange
        strategyAB1.setAssetRatio(Arrays.toArray(0, 1));
        // - must DHW for new asset ratio to take effect
        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroupAB));
        vm.stopPrank();

        // Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmounts = Arrays.toArray(0, 10 ether);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);

        uint256 depositNftIdAlice = smartVaultManager.deposit(
            DepositBag({
                smartVault: address(smartVault),
                assets: depositAmounts,
                receiver: alice,
                referral: address(0x0),
                doFlush: false
            })
        );

        vm.stopPrank();

        // check state
        // - tokens were transferred
        assertEq(tokenA.balanceOf(alice), 100 ether);
        assertEq(tokenB.balanceOf(alice), 90 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0);
        assertEq(tokenB.balanceOf(address(masterWallet)), 10 ether);
        // - deposit NFT was minted
        assertEq(depositNftIdAlice, 1);
        assertEq(smartVault.balanceOfFractional(alice, depositNftIdAlice), NFT_MINTED_SHARES);

        // flush
        smartVaultManager.flushSmartVault(address(smartVault));

        // DHW
        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroupAB));
        vm.stopPrank();

        // check state
        // - tokens were routed to the protocol
        assertEq(tokenA.balanceOf(address(strategyAB1.protocol())), 0);
        assertEq(tokenB.balanceOf(address(strategyAB1.protocol())), 10 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0);
        assertEq(tokenB.balanceOf(address(masterWallet)), 0);
        // - strategy tokens were minted
        assertEq(strategyAB1.totalSupply(), 10000000000000000000000);

        // sync vault
        smartVaultManager.syncSmartVault(address(smartVault), true);

        // check state
        // - strategy tokens were claimed
        assertEq(strategyAB1.balanceOf(address(smartVault)), 10000000000000000000000);
        assertEq(strategyAB1.balanceOf(address(strategyAB1)), 0);
        // - vault tokens were minted
        assertEq(smartVault.totalSupply(), 10000000000000000000000);
        assertEq(smartVault.balanceOf(address(smartVault)), 10000000000000000000000);

        // claim deposit
        uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);
        vm.startPrank(alice);
        smartVaultManager.claimSmartVaultTokens(address(smartVault), Arrays.toArray(depositNftIdAlice), amounts);
        vm.stopPrank();

        // check state
        // - vault tokens were claimed
        assertEq(smartVault.balanceOf(alice), 10000000000000000000000);
        assertEq(smartVault.balanceOf(address(smartVault)), 0);
        // - deposit NFT was burned
        assertEq(smartVault.balanceOfFractional(alice, depositNftIdAlice), 0);

        // Alice requests withdrawal
        vm.startPrank(alice);
        uint256 withdrawalNftIdAlice = smartVaultManager.redeem(
            RedeemBag(address(smartVault), smartVault.balanceOf(alice) / 2, new uint256[](0), new uint256[](0)),
            alice,
            false
        );
        vm.stopPrank();

        // check state
        // - vault tokens are returned to vault
        assertEq(smartVault.balanceOf(alice), 5000000000000000000000);
        assertEq(smartVault.balanceOf(address(smartVault)), 5000000000000000000000);
        // - withdrawal NFTs are minted
        assertEq(withdrawalNftIdAlice, 2 ** 255 + 1);
        assertEq(smartVault.balanceOfFractional(alice, withdrawalNftIdAlice), NFT_MINTED_SHARES);
        assertEq(smartVault.balanceOf(alice, withdrawalNftIdAlice), 1);

        // flush
        smartVaultManager.flushSmartVault(address(smartVault));

        // check state
        // - vault tokens are burned
        assertEq(smartVault.balanceOf(address(smartVault)), 0);
        // - strategy tokens are returned to strategies
        assertEq(strategyAB1.balanceOf(address(smartVault)), 5000000000000000000000);
        assertEq(strategyAB1.balanceOf(address(strategyAB1)), 5000000000000000000000);

        // DHW
        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroupAB));
        vm.stopPrank();

        // check state
        // - strategy tokens are burned
        assertEq(strategyAB1.balanceOf(address(strategyAB1)), 0);
        // - assets are withdrawn from protocol master wallet
        assertEq(tokenA.balanceOf(address(masterWallet)), 0);
        assertEq(tokenB.balanceOf(address(masterWallet)), 5 ether);
        assertEq(tokenA.balanceOf(address(strategyAB1)), 0);
        assertEq(tokenB.balanceOf(address(strategyAB1)), 0);

        // sync vault
        smartVaultManager.syncSmartVault(address(smartVault), true);

        // claim withdrawal
        vm.startPrank(alice);
        smartVaultManager.claimWithdrawal(
            address(smartVault), Arrays.toArray(withdrawalNftIdAlice), Arrays.toArray(NFT_MINTED_SHARES), alice
        );
        vm.stopPrank();

        // check state
        // - assets are transfered to withdrawers
        assertEq(tokenA.balanceOf(alice), 100 ether);
        assertEq(tokenB.balanceOf(alice), 95 ether);
        assertEq(tokenA.balanceOf(address(masterWallet)), 0);
        assertEq(tokenB.balanceOf(address(masterWallet)), 0);
        // - withdrawal NFTs are burned
        assertEq(smartVault.balanceOfFractional(alice, withdrawalNftIdAlice), 0);
        assertEq(smartVault.balanceOf(alice, withdrawalNftIdAlice), 0);
    }

    function test_redeemFor_shouldRevertWhenExecutorNotOnAllowlist() public {
        // set smart vault with allowlist guard checking executor of redeemal
        AllowlistGuard allowlistGuard = new AllowlistGuard(accessControl);

        GuardDefinition[][] memory guards = new GuardDefinition[][](1);
        guards[0] = new GuardDefinition[](1);

        GuardParamType[] memory guardParamTypes = new GuardParamType[](3);
        guardParamTypes[0] = GuardParamType.VaultAddress; // address of the smart vault
        guardParamTypes[1] = GuardParamType.CustomValue; // ID of the allowlist, set as method param value below
        guardParamTypes[2] = GuardParamType.Executor; // address of the executor

        bytes[] memory guardParamValues = new bytes[](1);
        guardParamValues[0] = abi.encode(uint256(0));

        guards[0][0] = GuardDefinition({
            contractAddress: address(allowlistGuard),
            methodSignature: "isAllowed(address,uint256,address)",
            expectedValue: 0, // do not need this
            methodParamTypes: guardParamTypes,
            methodParamValues: guardParamValues,
            operator: 0 // do not need this
        });

        RequestType[] memory guardRequestTypes = new RequestType[](1);
        guardRequestTypes[0] = RequestType.Withdrawal;

        address[] memory smartVaultStrategies = Arrays.toArray(address(strategyA1));

        SmartVaultSpecification memory smartVaultSpecification =
            getSmartVaultSpecification(assetGroupIdA, smartVaultStrategies);
        smartVaultSpecification.guards = guards;
        smartVaultSpecification.guardRequestTypes = guardRequestTypes;
        smartVaultSpecification.allowRedeemFor = true;

        vm.startPrank(bob);
        // Bob creates the smart vault
        ISmartVault smartVault = smartVaultFactory.deploySmartVault(smartVaultSpecification);
        vm.stopPrank();

        // add Alice to allowlist
        accessControl.grantSmartVaultRole(address(smartVault), ROLE_GUARD_ALLOWLIST_MANAGER, address(this));
        allowlistGuard.addToAllowlist(address(smartVault), 0, Arrays.toArray(alice));

        // set initial state - Alice deposited 40 ether to the smart vault
        deal(address(smartVault), alice, 4_000_000, true);
        deal(address(strategyA1), address(smartVault), 4_000_000, true);
        deal(address(tokenA), address(strategyA1), 40 ether, true);

        // Alice can request withdrawal
        vm.startPrank(alice);
        uint256 withdrawalNftIdAlice = smartVaultManager.redeem(
            RedeemBag({
                smartVault: address(smartVault),
                shares: 1_000_000,
                nftIds: new uint256[](0),
                nftAmounts: new uint256[](0)
            }),
            alice,
            false
        );
        vm.stopPrank();

        // check state
        // - vault tokens are returned to vault
        assertEq(smartVault.balanceOf(alice), 3_000_000);
        assertEq(smartVault.balanceOf(address(smartVault)), 1_000_000);
        // - withdrawal NFT is minted
        assertEq(withdrawalNftIdAlice, 2 ** 255 + 1);
        assertEq(smartVault.balanceOf(alice, withdrawalNftIdAlice), 1);

        // Bob as smart vault owner cannnot request withdrawal for Alice
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 0));
        smartVaultManager.redeemFor(
            RedeemBag({
                smartVault: address(smartVault),
                shares: 2_000_000,
                nftIds: new uint256[](0),
                nftAmounts: new uint256[](0)
            }),
            alice,
            false
        );
        vm.stopPrank();

        // add Bob to allowlist
        allowlistGuard.addToAllowlist(address(smartVault), 0, Arrays.toArray(bob));

        // Bob as smart vault owner can request withdrawal for Alice
        vm.startPrank(bob);
        uint256 withdrawalNftIdBob = smartVaultManager.redeemFor(
            RedeemBag({
                smartVault: address(smartVault),
                shares: 2_000_000,
                nftIds: new uint256[](0),
                nftAmounts: new uint256[](0)
            }),
            alice,
            false
        );
        vm.stopPrank();

        // check state
        // - vault tokens are returned to vault
        assertEq(smartVault.balanceOf(alice), 1_000_000);
        assertEq(smartVault.balanceOf(address(smartVault)), 3_000_000);
        // - withdrawal NFT is minted
        assertEq(withdrawalNftIdBob, 2 ** 255 + 2);
        assertEq(smartVault.balanceOf(alice, withdrawalNftIdBob), 1);
    }

    function getSmartVaultSpecification(uint256 assetGroupId, address[] memory strategies)
        private
        view
        returns (SmartVaultSpecification memory)
    {
        uint256 allocationRemaining = 100_00;
        uint256 strategiesRemaining = strategies.length;
        uint16a16 allocation;
        for (uint256 i; i < strategies.length; ++i) {
            uint256 strategyAllocation = allocationRemaining / strategiesRemaining;
            strategiesRemaining -= 1;
            allocationRemaining -= strategyAllocation;
            allocation = allocation.set(i, strategyAllocation);
        }

        return SmartVaultSpecification({
            smartVaultName: "MySmartVault",
            svtSymbol: "MSV",
            baseURI: "https://token-cdn-domain/",
            assetGroupId: assetGroupId,
            actions: new IAction[](0),
            actionRequestTypes: new RequestType[](0),
            guards: new GuardDefinition[][](0),
            guardRequestTypes: new RequestType[](0),
            strategies: strategies,
            strategyAllocation: allocation,
            riskTolerance: 4,
            riskProvider: riskProvider,
            managementFeePct: 0,
            depositFeePct: 0,
            allowRedeemFor: false,
            allocationProvider: allocationProvider,
            performanceFeePct: 0
        });
    }

    function generateDhwParameterBag(address[] memory strategies, address[] memory assetGroup)
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
}
