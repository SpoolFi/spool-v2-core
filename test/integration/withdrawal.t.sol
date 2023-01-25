// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/console.sol";
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
import "../../src/SmartVaultFactory.sol";
import "../../src/Swapper.sol";
import "../libraries/Arrays.sol";
import "../mocks/MockStrategy.sol";
import "../mocks/MockToken.sol";
import "../mocks/MockPriceFeedManager.sol";
import "../../src/managers/WithdrawalManager.sol";
import "../../src/managers/DepositManager.sol";
import "../../src/managers/RewardManager.sol";

contract WithdrawalIntegrationTest is Test {
    address private alice;
    address private bob;

    MockToken tokenA;
    MockToken tokenB;

    MockStrategy strategyA;
    MockStrategy strategyB;
    address[] mySmartVaultStrategies;

    ISmartVault private mySmartVault;
    SmartVaultManager private smartVaultManager;
    StrategyRegistry private strategyRegistry;
    MasterWallet private masterWallet;
    AssetGroupRegistry private assetGroupRegistry;
    SpoolAccessControl accessControl;
    IDepositManager depositManager;
    IWithdrawalManager withdrawalManager;

    function setUp() public {
        alice = address(0xa);
        bob = address(0xb);

        address riskProvider = address(0x1);

        tokenA = new MockToken("Token A", "TA");
        tokenB = new MockToken("Token B", "TB");

        accessControl = new SpoolAccessControl();
        accessControl.initialize();
        masterWallet = new MasterWallet(accessControl);

        address[] memory assetGroup = new address[](2);
        assetGroup[0] = address(tokenA);
        assetGroup[1] = address(tokenB);
        assetGroupRegistry = new AssetGroupRegistry(accessControl);
        assetGroupRegistry.initialize(assetGroup);
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        IUsdPriceFeedManager priceFeedManager = new MockPriceFeedManager();
        strategyRegistry = new StrategyRegistry(masterWallet, accessControl, priceFeedManager);
        IActionManager actionManager = new ActionManager(accessControl);
        IGuardManager guardManager = new GuardManager(accessControl);
        IRiskManager riskManager = new RiskManager(accessControl);
        depositManager =
            new DepositManager(strategyRegistry, priceFeedManager, guardManager, actionManager, accessControl);
        withdrawalManager =
        new WithdrawalManager(strategyRegistry, priceFeedManager, masterWallet, guardManager, actionManager, accessControl);

        address managerAddress = computeCreateAddress(address(this), 1);
        IRewardManager rewardManager =
            new RewardManager(accessControl, assetGroupRegistry, ISmartVaultBalance(managerAddress));

        smartVaultManager = new SmartVaultManager(
            accessControl,
            assetGroupRegistry,
            riskManager,
            depositManager,
            withdrawalManager,
            strategyRegistry,
            masterWallet,
            rewardManager
        );

        strategyA = new MockStrategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, new Swapper());
        uint256[] memory strategyRatios = new uint256[](2);
        strategyRatios[0] = 1_000;
        strategyRatios[1] = 68;
        strategyA.initialize(assetGroupId, strategyRatios);
        strategyRegistry.registerStrategy(address(strategyA));

        strategyRatios[1] = 67;
        strategyB = new MockStrategy("StratB", strategyRegistry, assetGroupRegistry, accessControl, new Swapper());
        strategyB.initialize(assetGroupId, strategyRatios);
        strategyRegistry.registerStrategy(address(strategyB));

        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
        accessControl.grantRole(ROLE_STRATEGY_CLAIMER, address(withdrawalManager));
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(depositManager));
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(withdrawalManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(strategyRegistry));
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
                assetGroupRegistry
            );
            accessControl.grantRole(ADMIN_ROLE_SMART_VAULT, address(smartVaultFactory));
            accessControl.grantRole(ROLE_SMART_VAULT_INTEGRATOR, address(smartVaultFactory));

            mySmartVaultStrategies = Arrays.toArray(address(strategyA), address(strategyB));

            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(400, 600))
            );

            mySmartVault = smartVaultFactory.deploySmartVault(
                SmartVaultSpecification({
                    smartVaultName: "MySmartVault",
                    assetGroupId: assetGroupId,
                    actions: new IAction[](0),
                    actionRequestTypes: new RequestType[](0),
                    guards: new GuardDefinition[][](0),
                    guardRequestTypes: new RequestType[](0),
                    strategies: mySmartVaultStrategies,
                    riskAppetite: 4,
                    riskProvider: riskProvider
                })
            );
        }
    }

    function test_shouldBeAbleToWithdraw() public {
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
            RedeemBag(address(mySmartVault), 3_000_000, new uint256[](0), new uint256[](0)), alice, alice
        );

        vm.prank(bob);
        uint256 bobWithdrawalNftId = smartVaultManager.redeem(
            RedeemBag(address(mySmartVault), 200_000, new uint256[](0), new uint256[](0)), bob, bob
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

        SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](2);
        dhwSwapInfo[0] = new SwapInfo[](0);
        dhwSwapInfo[1] = new SwapInfo[](0);

        strategyRegistry.doHardWork(mySmartVaultStrategies, dhwSwapInfo);

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

    function test_shouldBeAbleToWithdrawFast() public {
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
        vm.startPrank(alice);
        uint256[] memory withdrawnAssets = smartVaultManager.redeemFast(
            RedeemBag(address(mySmartVault), 3_000_000, new uint256[](0), new uint256[](0))
        );

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
}
