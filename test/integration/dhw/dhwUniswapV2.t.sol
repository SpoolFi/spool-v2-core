// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../../src/managers/ActionManager.sol";
import "../../../src/managers/AssetGroupRegistry.sol";
import "../../../src/managers/GuardManager.sol";
import "../../../src/managers/RiskManager.sol";
import "../../../src/managers/SmartVaultManager.sol";
import "../../../src/managers/StrategyRegistry.sol";
import "../../../src/managers/UsdPriceFeedManager.sol";
import "../../../src/MasterWallet.sol";
import "../../../src/SmartVault.sol";
import "../../../src/SmartVaultFactory.sol";
import "../../../src/Swapper.sol";
import "../../libraries/Arrays.sol";
import "../../utils/UniswapV2Setup.sol";
import "../../mocks/MockUniswapV2Strategy.sol";
import "../../mocks/MockToken.sol";
import "../../mocks/MockPriceFeedManager.sol";

contract dhwUniswapV2 is Test {
    address private alice;
    address private bob;

    MockToken tokenA;
    MockToken tokenB;

    UniswapV2Setup uniswapV2Setup;

    MockUniswapV2Strategy strategyA;
    address[] mySmartVaultStrategies;

    ISmartVault private mySmartVault;
    SmartVaultManager private smartVaultManager;
    StrategyRegistry private strategyRegistry;
    MasterWallet private masterWallet;
    AssetGroupRegistry private assetGroupRegistry;
    SpoolAccessControl accessControl;

    function setUp() public {
        tokenA = new MockToken("Token A", "TA");
        tokenB = new MockToken("Token B", "TB");

        uniswapV2Setup = new UniswapV2Setup();
        uniswapV2Setup.addLiquidity(address(tokenA), 10000 ether, address(tokenB), 10 ether, address(0));

        alice = address(0xa);
        bob = address(0xb);

        address riskProvider = address(0x1);

        accessControl = new SpoolAccessControl();
        accessControl.initialize();
        masterWallet = new MasterWallet(accessControl);

        address[] memory assetGroup = new address[](2);
        assetGroup[0] = address(tokenA);
        assetGroup[1] = address(tokenB);
        assetGroupRegistry = new AssetGroupRegistry(accessControl);
        assetGroupRegistry.initialize(assetGroup);
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        MockPriceFeedManager priceFeedManager = new MockPriceFeedManager();
        strategyRegistry = new StrategyRegistry(masterWallet, accessControl, priceFeedManager);
        IActionManager actionManager = new ActionManager(accessControl);
        IGuardManager guardManager = new GuardManager(accessControl);
        IRiskManager riskManager = new RiskManager(accessControl);

        smartVaultManager = new SmartVaultManager(
            accessControl,
            strategyRegistry,
            priceFeedManager,
            assetGroupRegistry,
            masterWallet,
            new ActionManager(accessControl),
            guardManager,
            riskManager
        );

        strategyA =
        new MockUniswapV2Strategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, uniswapV2Setup.router());
        strategyA.initialize(assetGroupId);
        strategyRegistry.registerStrategy(address(strategyA));

        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
        accessControl.grantRole(ROLE_STRATEGY_CLAIMER, address(smartVaultManager));
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(strategyRegistry));

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

            mySmartVaultStrategies = Arrays.toArray(address(strategyA));

            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(1000))
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

        priceFeedManager.setExchangeRate(address(tokenA), 1000 * 10 ** 26);
        priceFeedManager.setExchangeRate(address(tokenB), 1 * 10 ** 26);
    }

    function test_dhwUniswapV2() public {
        uint256[] memory tokenAliceInitial = Arrays.toArray(4000 ether, 4 ether);

        // set initial state
        deal(address(tokenA), alice, tokenAliceInitial[0], true);
        deal(address(tokenB), alice, tokenAliceInitial[1], true);

        // Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmountsAlice = Arrays.toArray(tokenAliceInitial[0], tokenAliceInitial[1]);

        tokenA.approve(address(smartVaultManager), depositAmountsAlice[0]);
        tokenB.approve(address(smartVaultManager), depositAmountsAlice[1]);

        uint256 aliceDepositNftId =
            smartVaultManager.deposit(address(mySmartVault), depositAmountsAlice, alice, address(0));

        vm.stopPrank();

        // flush
        smartVaultManager.flushSmartVault(address(mySmartVault));

        // DHW - DEPOSIT
        SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](2);
        dhwSwapInfo[0] = new SwapInfo[](0);
        dhwSwapInfo[1] = new SwapInfo[](0);

        strategyRegistry.doHardWork(mySmartVaultStrategies, dhwSwapInfo);

        // produce 50% yield for Alice
        uint256 firstYieldPercentage = 50_00;
        uniswapV2Setup.addProfitToPair(address(tokenA), address(tokenB), firstYieldPercentage);

        // sync vault
        smartVaultManager.syncSmartVault(address(mySmartVault));

        // claim deposit
        vm.startPrank(alice);
        smartVaultManager.claimSmartVaultTokens(
            address(mySmartVault), Arrays.toArray(aliceDepositNftId), Arrays.toArray(NFT_MINTED_SHARES)
        );
        vm.stopPrank();

        // ======================

        uint256[] memory tokenBobInitial = Arrays.toArray(2000 ether, 2 ether);

        // set initial state
        deal(address(tokenA), bob, tokenBobInitial[0], true);
        deal(address(tokenB), bob, tokenBobInitial[1], true);

        // Bob deposits
        vm.startPrank(bob);

        uint256[] memory depositAmountsBob = Arrays.toArray(tokenBobInitial[0], tokenBobInitial[1]);

        tokenA.approve(address(smartVaultManager), depositAmountsBob[0]);
        tokenB.approve(address(smartVaultManager), depositAmountsBob[1]);

        uint256 bobDepositNftId = smartVaultManager.deposit(address(mySmartVault), depositAmountsBob, bob, address(0));

        vm.stopPrank();

        // flush
        smartVaultManager.flushSmartVault(address(mySmartVault));

        // DHW - DEPOSIT

        strategyRegistry.doHardWork(mySmartVaultStrategies, dhwSwapInfo);

        // produce 25% yield for Alice and Bob
        uint256 secondYieldPercentage = 25_00;
        uniswapV2Setup.addProfitToPair(address(tokenA), address(tokenB), secondYieldPercentage);

        // sync vault
        smartVaultManager.syncSmartVault(address(mySmartVault));

        // claim deposit
        vm.startPrank(bob);
        smartVaultManager.claimSmartVaultTokens(
            address(mySmartVault), Arrays.toArray(bobDepositNftId), Arrays.toArray(NFT_MINTED_SHARES)
        );
        vm.stopPrank();

        // ======================

        // WITHDRAW
        uint256 aliceShares = mySmartVault.balanceOf(alice);
        uint256 bobShares = mySmartVault.balanceOf(bob);
        console2.log("aliceShares Before:", aliceShares);

        {
            vm.prank(alice);
            uint256 aliceWithdrawalNftId = smartVaultManager.redeem(
                address(mySmartVault), aliceShares, alice, alice, new uint256[](0), new uint256[](0)
            );
            vm.prank(bob);
            uint256 bobWithdrawalNftId =
                smartVaultManager.redeem(address(mySmartVault), bobShares, bob, bob, new uint256[](0), new uint256[](0));

            console2.log("flushSmartVault");
            smartVaultManager.flushSmartVault(address(mySmartVault));

            // DHW - WITHDRAW
            SwapInfo[][] memory dhwSwapInfoWithdraw = new SwapInfo[][](1);
            dhwSwapInfoWithdraw[0] = new SwapInfo[](0);
            console2.log("doHardWork");
            strategyRegistry.doHardWork(mySmartVaultStrategies, dhwSwapInfo);

            // sync vault
            console2.log("syncSmartVault");
            smartVaultManager.syncSmartVault(address(mySmartVault));

            // claim withdrawal
            console2.log("tokenA Before:", tokenA.balanceOf(alice));

            vm.startPrank(alice);
            console2.log("claimWithdrawal");
            smartVaultManager.claimWithdrawal(
                address(mySmartVault), Arrays.toArray(aliceWithdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
            vm.startPrank(bob);
            smartVaultManager.claimWithdrawal(
                address(mySmartVault), Arrays.toArray(bobWithdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), bob
            );
            vm.stopPrank();

            console2.log("tokenA alice  After:", roundUp(tokenA.balanceOf(alice)));
            console2.log("tokenA bob    After:", roundUp(tokenA.balanceOf(bob)));
            console2.log("tokenB alice  After:", roundUp(tokenB.balanceOf(alice)));
            console2.log("tokenB bob    After:", roundUp(tokenB.balanceOf(bob)));
        }

        {
            // first yield only belongs to alice
            uint256 aliceAfterFirstYieldBalanceA =
                tokenAliceInitial[0] + tokenAliceInitial[0] * firstYieldPercentage / 100_00;
            uint256 aliceAfterFirstYieldBalanceB =
                tokenAliceInitial[1] + tokenAliceInitial[1] * firstYieldPercentage / 100_00;

            // second yield distributes to alice and bob
            uint256 aliceAftersecondYieldBalanceA =
                aliceAfterFirstYieldBalanceA + aliceAfterFirstYieldBalanceA * secondYieldPercentage / 100_00;
            uint256 aliceAftersecondYieldBalanceB =
                aliceAfterFirstYieldBalanceB + aliceAfterFirstYieldBalanceB * secondYieldPercentage / 100_00;
            uint256 bobAftersecondYieldBalanceA =
                tokenBobInitial[0] + tokenBobInitial[0] * secondYieldPercentage / 100_00;
            uint256 bobAftersecondYieldBalanceB =
                tokenBobInitial[1] + tokenBobInitial[1] * secondYieldPercentage / 100_00;

            console2.log("aliceAftersecondYieldBalanceA:", aliceAftersecondYieldBalanceA);
            console2.log("aliceAftersecondYieldBalanceB:", aliceAftersecondYieldBalanceB);
            console2.log("bobAftersecondYieldBalanceA:", bobAftersecondYieldBalanceA);
            console2.log("bobAftersecondYieldBalanceB:", bobAftersecondYieldBalanceB);

            // NOTE: check relative error size
            assertApproxEqRel(tokenA.balanceOf(alice), aliceAftersecondYieldBalanceA, 10 ** 9);
            assertApproxEqRel(tokenB.balanceOf(alice), aliceAftersecondYieldBalanceB, 10 ** 9);
            assertApproxEqRel(tokenA.balanceOf(bob), bobAftersecondYieldBalanceA, 10 ** 9);
            assertApproxEqRel(tokenB.balanceOf(bob), bobAftersecondYieldBalanceB, 10 ** 9);
        }
    }

    function roundUp(uint256 x) private pure returns (uint256) {
        return x + (1000 - (x % 1000));
    }
}
