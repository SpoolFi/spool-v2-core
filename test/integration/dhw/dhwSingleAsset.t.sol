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
import "../../mocks/MockStrategy.sol";
import "../../mocks/MockToken.sol";
import "../../mocks/MockPriceFeedManager.sol";
import "../../mocks/BaseTestContracts.sol";

contract DhwSingleAssetTest is BaseTestContracts, Test {
    address private alice;
    address private bob;

    MockToken tokenA;

    MockStrategy strategyA;
    MockStrategy strategyB;
    MockStrategy strategyC;
    address[] smartVaultStrategies;

    function setUp() public {
        setUpBase();

        alice = address(0xa);
        bob = address(0xb);

        tokenA = new MockToken("Token A", "TA");

        address[] memory assetGroup = Arrays.toArray(address(tokenA));
        assetGroupRegistry.allowToken(address(tokenA));
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        strategyA = new MockStrategy("StratA", strategyRegistry, assetGroupRegistry, accessControl, new Swapper());
        uint256[] memory strategyRatios = new uint256[](3);
        strategyRatios[0] = 1000;
        strategyRatios[1] = 71;
        strategyRatios[2] = 4300;
        strategyA.initialize(assetGroupId, strategyRatios);
        strategyRegistry.registerStrategy(address(strategyA));

        strategyRatios[1] = 74;
        strategyRatios[2] = 4500;
        strategyB = new MockStrategy("StratB", strategyRegistry, assetGroupRegistry, accessControl, new Swapper());
        strategyB.initialize(assetGroupId, strategyRatios);
        strategyRegistry.registerStrategy(address(strategyB));

        strategyRatios[1] = 76;
        strategyRatios[2] = 4600;
        strategyC = new MockStrategy("StratC", strategyRegistry, assetGroupRegistry, accessControl, new Swapper());
        strategyC.initialize(assetGroupId, strategyRatios);
        strategyRegistry.registerStrategy(address(strategyC));

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

            smartVaultStrategies = Arrays.toArray(address(strategyA), address(strategyB), address(strategyC));

            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(600, 300, 100))
            );

            smartVault = smartVaultFactory.deploySmartVault(
                SmartVaultSpecification({
                    smartVaultName: "MySmartVault",
                    assetGroupId: assetGroupId,
                    actions: new IAction[](0),
                    actionRequestTypes: new RequestType[](0),
                    guards: new GuardDefinition[][](0),
                    guardRequestTypes: new RequestType[](0),
                    strategies: smartVaultStrategies,
                    riskAppetite: 4,
                    riskProvider: riskProvider
                })
            );
        }

        priceFeedManager.setExchangeRate(address(tokenA), 1200 * 10 ** 26);
    }

    function test_dhw_twoDepositors() public {
        uint256 tokenAInitialBalanceAlice = 100 ether;

        // set initial state
        deal(address(tokenA), alice, tokenAInitialBalanceAlice, true);

        // Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmountsAlice = Arrays.toArray(tokenAInitialBalanceAlice);

        tokenA.approve(address(depositManager), depositAmountsAlice[0]);

        uint256 aliceDepositNftId =
            smartVaultManager.deposit(address(smartVault), depositAmountsAlice, alice, address(0));

        vm.stopPrank();

        // flush
        smartVaultManager.flushSmartVault(address(smartVault));

        // DHW - DEPOSIT
        SwapInfo[][] memory dhwSwapInfo = new SwapInfo[][](3);
        dhwSwapInfo[0] = new SwapInfo[](0);
        dhwSwapInfo[1] = new SwapInfo[](0);
        dhwSwapInfo[2] = new SwapInfo[](0);

        strategyRegistry.doHardWork(smartVaultStrategies, dhwSwapInfo);

        // sync vault
        smartVaultManager.syncSmartVault(address(smartVault));

        // claim deposit
        vm.startPrank(alice);
        smartVaultManager.claimSmartVaultTokens(
            address(smartVault), Arrays.toArray(aliceDepositNftId), Arrays.toArray(NFT_MINTED_SHARES)
        );
        vm.stopPrank();

        // ======================

        uint256 tokenAInitialBalanceBob = 10 ether;

        // set initial state
        deal(address(tokenA), bob, tokenAInitialBalanceBob, true);

        // Bob deposits
        vm.startPrank(bob);

        uint256[] memory depositAmountsBob = Arrays.toArray(tokenAInitialBalanceBob);

        tokenA.approve(address(depositManager), depositAmountsBob[0]);

        uint256 bobDepositNftId = smartVaultManager.deposit(address(smartVault), depositAmountsBob, bob, address(0));

        vm.stopPrank();

        // flush
        smartVaultManager.flushSmartVault(address(smartVault));

        // DHW - DEPOSIT

        strategyRegistry.doHardWork(smartVaultStrategies, dhwSwapInfo);

        // // sync vault
        smartVaultManager.syncSmartVault(address(smartVault));

        // claim deposit
        vm.startPrank(bob);
        smartVaultManager.claimSmartVaultTokens(
            address(smartVault), Arrays.toArray(bobDepositNftId), Arrays.toArray(NFT_MINTED_SHARES)
        );
        vm.stopPrank();

        // ======================

        // WITHDRAW
        uint256 aliceShares = smartVault.balanceOf(alice);
        uint256 bobShares = smartVault.balanceOf(bob);
        console2.log("aliceShares Before:", aliceShares);

        vm.prank(alice);
        uint256 aliceWithdrawalNftId =
            smartVaultManager.redeem(address(smartVault), aliceShares, alice, alice, new uint256[](0), new uint256[](0));
        vm.prank(bob);
        uint256 bobWithdrawalNftId =
            smartVaultManager.redeem(address(smartVault), bobShares, bob, bob, new uint256[](0), new uint256[](0));

        console2.log("flushSmartVault");
        smartVaultManager.flushSmartVault(address(smartVault));

        // DHW - WITHDRAW
        SwapInfo[][] memory dhwSwapInfoWithdraw = new SwapInfo[][](3);
        dhwSwapInfoWithdraw[0] = new SwapInfo[](0);
        dhwSwapInfoWithdraw[1] = new SwapInfo[](0);
        dhwSwapInfoWithdraw[2] = new SwapInfo[](0);
        console2.log("doHardWork");
        strategyRegistry.doHardWork(smartVaultStrategies, dhwSwapInfo);

        // sync vault
        console2.log("syncSmartVault");
        smartVaultManager.syncSmartVault(address(smartVault));

        // claim withdrawal
        console2.log("tokenA Before:", tokenA.balanceOf(alice));

        vm.startPrank(alice);
        console2.log("claimWithdrawal");
        smartVaultManager.claimWithdrawal(
            address(smartVault), Arrays.toArray(aliceWithdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
        );
        vm.stopPrank();
        vm.startPrank(bob);
        smartVaultManager.claimWithdrawal(
            address(smartVault), Arrays.toArray(bobWithdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), bob
        );
        vm.stopPrank();

        console2.log("tokenA alice  After:", tokenA.balanceOf(alice));
        console2.log("tokenA bob    After:", tokenA.balanceOf(bob));

        assertApproxEqAbs(tokenA.balanceOf(alice), tokenAInitialBalanceAlice, 10);
        assertApproxEqAbs(tokenA.balanceOf(bob), tokenAInitialBalanceBob, 10);
    }
}
