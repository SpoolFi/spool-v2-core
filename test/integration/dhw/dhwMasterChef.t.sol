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
import "../../mocks/MockMasterChef.sol";
import "../../mocks/MockMasterChefStrategy.sol";
import "../../mocks/MockToken.sol";
import "../../mocks/MockPriceFeedManager.sol";
import "../../fixtures/TestFixture.sol";

contract DhwMasterChefTest is TestFixture {
    address private alice;
    address private bob;

    MockMasterChefStrategy strategyA;
    address[] smartVaultStrategies;
    MockMasterChef masterChef;

    address[] assetGroup;

    uint256 rewardsPerSecond;

    function setUp() public {
        setUpBase();

        rewardsPerSecond = 1 ether;
        masterChef = new MockMasterChef(address(token), rewardsPerSecond);
        masterChef.add(100, token, true);

        alice = address(0xa);
        bob = address(0xb);

        assetGroup = Arrays.toArray(address(token));
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        strategyA = new MockMasterChefStrategy("StratA", assetGroupRegistry, accessControl, masterChef, 0);
        strategyA.initialize(assetGroupId);
        strategyRegistry.registerStrategy(address(strategyA));

        accessControl.grantRole(ROLE_STRATEGY_CLAIMER, address(smartVaultManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY_REGISTRY, address(strategyRegistry));

        {
            smartVaultStrategies = Arrays.toArray(address(strategyA));

            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toUint16a16(1000))
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
                    strategyAllocation: new uint256[](0),
                    riskTolerance: 4,
                    riskProvider: riskProvider,
                    managementFeePct: 0,
                    depositFeePct: 0,
                    allowRedeemFor: false,
                    allocationProvider: address(allocationProvider)
                })
            );
        }

        priceFeedManager.setExchangeRate(address(token), 1200 * 10 ** 26);
    }

    function test_dhwGenerateYield() public {
        uint256 tokenInitialBalanceAlice = 78 ether;

        // set initial state
        deal(address(token), alice, tokenInitialBalanceAlice, true);

        // Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmountsAlice = Arrays.toArray(tokenInitialBalanceAlice);

        token.approve(address(smartVaultManager), depositAmountsAlice[0]);

        uint256 aliceDepositNftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmountsAlice, alice, address(0), false));
        console2.log("smartVault.balanceOf(alice, aliceDepositNftId):", smartVault.balanceOf(alice, aliceDepositNftId));

        vm.stopPrank();

        // flush
        smartVaultManager.flushSmartVault(address(smartVault));

        // DHW - DEPOSIT
        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroup));
        vm.stopPrank();

        // skip 2 seconds to produce 2 * 10**18 yield, only goes to alice
        uint256 firstYieldSeconds = 2;
        skip(firstYieldSeconds);

        // sync vault
        smartVaultManager.syncSmartVault(address(smartVault), true);

        // claim deposit
        vm.startPrank(alice);
        smartVaultManager.claimSmartVaultTokens(
            address(smartVault), Arrays.toArray(aliceDepositNftId), Arrays.toArray(NFT_MINTED_SHARES)
        );
        vm.stopPrank();

        // ======================

        uint256 tokenInitialBalanceBob = 20 ether;

        // set initial state
        deal(address(token), bob, tokenInitialBalanceBob, true);

        // Bob deposits
        vm.startPrank(bob);

        uint256[] memory depositAmountsBob = Arrays.toArray(tokenInitialBalanceBob);

        token.approve(address(smartVaultManager), depositAmountsBob[0]);

        uint256 bobDepositNftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmountsBob, bob, address(0), false));

        vm.stopPrank();

        // flush
        smartVaultManager.flushSmartVault(address(smartVault));

        // DHW - DEPOSIT
        vm.startPrank(doHardWorker);
        strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroup));
        vm.stopPrank();

        // skip 2 seconds to produce 10**18 yield, distributes between alice and bob
        uint256 secondYieldSeconds = 1;
        skip(secondYieldSeconds);

        // sync vault
        smartVaultManager.syncSmartVault(address(smartVault), true);

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

        {
            vm.prank(alice);
            uint256 aliceWithdrawalNftId = smartVaultManager.redeem(
                RedeemBag(address(smartVault), aliceShares, new uint256[](0), new uint256[](0)), alice, false
            );
            vm.prank(bob);
            uint256 bobWithdrawalNftId = smartVaultManager.redeem(
                RedeemBag(address(smartVault), bobShares, new uint256[](0), new uint256[](0)), bob, false
            );

            console2.log("flushSmartVault");
            smartVaultManager.flushSmartVault(address(smartVault));

            // DHW - WITHDRAW
            console2.log("doHardWork");
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(smartVaultStrategies, assetGroup));
            vm.stopPrank();

            // sync vault
            console2.log("syncSmartVault");
            smartVaultManager.syncSmartVault(address(smartVault), true);

            // claim withdrawal
            console2.log("token Before:", token.balanceOf(alice));

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

            console2.log("token alice  After:", token.balanceOf(alice));
            console2.log("token bob    After:", token.balanceOf(bob));
        }

        {
            uint256 firstYield = rewardsPerSecond * firstYieldSeconds;
            uint256 secondYield = rewardsPerSecond * secondYieldSeconds;

            // first yield only belongs to alice
            uint256 aliceAfterFirstYieldBalance = tokenInitialBalanceAlice + firstYield;

            // first yield only distributes to alice and bob
            uint256 aliceAftersecondYieldBalance = aliceAfterFirstYieldBalance
                + (secondYield * aliceAfterFirstYieldBalance / (aliceAfterFirstYieldBalance + tokenInitialBalanceBob));
            uint256 bobAftersecondYieldBalance = tokenInitialBalanceBob
                + (secondYield * tokenInitialBalanceBob / (aliceAfterFirstYieldBalance + tokenInitialBalanceBob));

            console2.log("aliceAftersecondYieldBalance:", aliceAftersecondYieldBalance);
            console2.log("bobAftersecondYieldBalance:", bobAftersecondYieldBalance);

            // NOTE: check relative error size
            assertApproxEqRel(token.balanceOf(alice), aliceAftersecondYieldBalance, 10 ** 9);
            assertApproxEqRel(token.balanceOf(bob), bobAftersecondYieldBalance, 10 ** 9);
        }
    }
}
