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
import "../../mocks/TestFixture.sol";

contract DhwTest is TestFixture {
    address private alice;

    MockToken tokenA;
    MockToken tokenB;
    MockToken tokenC;

    MockStrategy strategyA;
    MockStrategy strategyB;
    MockStrategy strategyC;
    address[] smartVaultStrategies;

    function setUp() public {
        alice = address(0xa);

        tokenA = new MockToken("Token A", "TA");
        tokenB = new MockToken("Token B", "TB");
        tokenC = new MockToken("Token C", "TC");

        setUpBase();

        address[] memory assetGroup = new address[](3);
        assetGroup[0] = address(tokenA);
        assetGroup[1] = address(tokenB);
        assetGroup[2] = address(tokenC);
        assetGroupRegistry.allowToken(address(tokenA));
        assetGroupRegistry.allowToken(address(tokenB));
        assetGroupRegistry.allowToken(address(tokenC));
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

        accessControl.grantRole(ROLE_STRATEGY_CLAIMER, address(smartVaultManager));
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
        priceFeedManager.setExchangeRate(address(tokenB), 16400 * 10 ** 26);
        priceFeedManager.setExchangeRate(address(tokenC), 270 * 10 ** 26);
    }

    function test_dhwSimple() public {
        uint256 tokenAInitialBalance = 100 ether;
        uint256 tokenBInitialBalance = 10 ether;
        uint256 tokenCInitialBalance = 500 ether;

        // set initial state
        deal(address(tokenA), alice, tokenAInitialBalance, true);
        deal(address(tokenB), alice, tokenBInitialBalance, true);
        deal(address(tokenC), alice, tokenCInitialBalance, true);

        // Alice deposits
        vm.startPrank(alice);

        uint256[] memory depositAmounts = Arrays.toArray(100 ether, 7.237 ether, 438.8 ether);

        tokenA.approve(address(smartVaultManager), depositAmounts[0]);
        tokenB.approve(address(smartVaultManager), depositAmounts[1]);
        tokenC.approve(address(smartVaultManager), depositAmounts[2]);

        uint256 aliceDepositNftId =
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, alice, address(0)));
        console2.log("smartVault.balanceOf(alice, aliceDepositNftId):", smartVault.balanceOf(alice, aliceDepositNftId));

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
        console2.log("smartVault.balanceOf(alice, aliceDepositNftId):", smartVault.balanceOf(alice, aliceDepositNftId));
        vm.startPrank(alice);
        smartVaultManager.claimSmartVaultTokens(
            address(smartVault), Arrays.toArray(aliceDepositNftId), Arrays.toArray(NFT_MINTED_SHARES)
        );
        vm.stopPrank();

        // WITHDRAW
        uint256 aliceShares = smartVault.balanceOf(alice);
        console2.log("aliceShares Before:", aliceShares);

        vm.prank(alice);
        uint256 aliceWithdrawalNftId = smartVaultManager.redeem(
            RedeemBag(address(smartVault), aliceShares, new uint256[](0), new uint256[](0)), alice, alice
        );

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
        console2.log("tokenB Before:", tokenB.balanceOf(alice));
        console2.log("tokenC Before:", tokenC.balanceOf(alice));

        vm.startPrank(alice);
        console2.log("claimWithdrawal");
        smartVaultManager.claimWithdrawal(
            address(smartVault), Arrays.toArray(aliceWithdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
        );
        vm.stopPrank();

        console2.log("tokenA After:", tokenA.balanceOf(alice));
        console2.log("tokenB After:", tokenB.balanceOf(alice));
        console2.log("tokenC After:", tokenC.balanceOf(alice));

        assertEq(tokenA.balanceOf(alice), tokenAInitialBalance);
        assertEq(tokenB.balanceOf(alice), tokenBInitialBalance);
        assertEq(tokenC.balanceOf(alice), tokenCInitialBalance);
    }
}
