// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../src/interfaces/RequestType.sol";
import "../src/managers/ActionManager.sol";
import "../src/managers/AssetGroupRegistry.sol";
import "../src/managers/GuardManager.sol";
import "../src/managers/RiskManager.sol";
import "../src/managers/SmartVaultManager.sol";
import "../src/managers/StrategyRegistry.sol";
import "../src/managers/UsdPriceFeedManager.sol";
import "../src/DepositSwap.sol";
import "../src/MasterWallet.sol";
import "../src/SmartVault.sol";
import "../src/SmartVaultFactory.sol";
import "../src/Swapper.sol";
import "./libraries/Arrays.sol";
import "./mocks/MockExchange.sol";
import "./mocks/MockPriceFeedManager.sol";
import "./mocks/MockStrategy.sol";
import "./mocks/MockToken.sol";

contract DepositSwapIntegrationTest is Test, SpoolAccessRoles {
    address private alice;
    address private bob;

    MockToken private tokenA;
    MockToken private tokenB;
    MockToken private tokenC;

    AssetGroupRegistry private assetGroupRegistry;
    MasterWallet private masterWallet;
    MockPriceFeedManager private priceFeedManager;
    ISmartVault private smartVault;
    SmartVaultManager private smartVaultManager;
    Swapper private swapper;

    function setUp() public {
        alice = address(0xa);
        bob = address(0xb);

        address riskProvider = address(0x1);

        tokenA = new MockToken("Token A", "TA");
        tokenB = new MockToken("Token B", "TB");
        tokenC = new MockToken("Token C", "TC");

        SpoolAccessControl accessControl = new SpoolAccessControl();
        accessControl.initialize();
        ActionManager actionManager = new ActionManager(accessControl);
        assetGroupRegistry = new AssetGroupRegistry();
        GuardManager guardManager = new GuardManager(accessControl);
        masterWallet = new MasterWallet(accessControl);
        priceFeedManager = new MockPriceFeedManager();
        StrategyRegistry strategyRegistry = new StrategyRegistry(masterWallet, accessControl, priceFeedManager);
        swapper = new Swapper();
        smartVaultManager = new SmartVaultManager(
            accessControl,
            strategyRegistry,
            priceFeedManager,
            assetGroupRegistry,
            masterWallet,
            actionManager,
            guardManager
        );

        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);

        uint256 assetGroupId;
        {
            address[] memory assetGroup = new address[](2);
            assetGroup[0] = address(tokenA);
            assetGroup[1] = address(tokenB);
            assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        }

        MockStrategy strategy =
            new MockStrategy("Strategy", strategyRegistry, assetGroupRegistry, accessControl, swapper);
        {
            uint256[] memory strategyRatios = new uint256[](2);
            strategyRatios[0] = 800;
            strategyRatios[1] = 200;
            strategy.initialize(assetGroupId, strategyRatios);
            strategyRegistry.registerStrategy(address(strategy));
        }

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

            smartVault = smartVaultFactory.deploySmartVault(
                SmartVaultSpecification({
                    smartVaultName: "SmartVault",
                    assetGroupId: assetGroupId,
                    actions: new IAction[](0),
                    actionRequestTypes: new RequestType[](0),
                    guards: new GuardDefinition[][](0),
                    guardRequestTypes: new RequestType[](0),
                    strategies: Arrays.toArray(address(strategy)),
                    strategyAllocations: Arrays.toArray(1_000),
                    riskProvider: riskProvider
                })
            );
        }
    }

    function test_depositSwap_swapAndDeposit_shouldDoCompleteSwapAndThenDeposit() public {
        tokenC.mint(alice, 2 ether);

        MockExchange exchangeAC = new MockExchange(tokenA, tokenC, priceFeedManager);
        tokenA.mint(address(exchangeAC), 1000 ether);
        tokenC.mint(address(exchangeAC), 1000 ether);
        MockExchange exchangeBC = new MockExchange(tokenB, tokenC, priceFeedManager);
        tokenB.mint(address(exchangeBC), 1000 ether);
        tokenC.mint(address(exchangeBC), 1000 ether);

        priceFeedManager.setExchangeRate(address(tokenA), 1 * 10 ** 26);
        priceFeedManager.setExchangeRate(address(tokenB), 1 * 10 ** 26);
        priceFeedManager.setExchangeRate(address(tokenC), 2 * 10 ** 26);

        DepositSwap depositSwap = new DepositSwap(assetGroupRegistry, smartVaultManager, swapper);

        SwapInfo[] memory swapInfo = new SwapInfo[](2);
        swapInfo[0] = SwapInfo(
            address(exchangeAC),
            address(tokenC),
            1 ether,
            abi.encodeWithSelector(exchangeAC.swap.selector, address(tokenC), 1 ether, address(depositSwap))
        );
        swapInfo[1] = SwapInfo(
            address(exchangeBC),
            address(tokenC),
            1 ether,
            abi.encodeWithSelector(exchangeBC.swap.selector, address(tokenC), 0.25 ether, address(depositSwap))
        );

        vm.startPrank(alice);
        tokenC.approve(address(depositSwap), 2 ether);

        uint256 nftId = depositSwap.swapAndDeposit(
            Arrays.toArray(address(tokenC)), Arrays.toArray(2 ether), swapInfo, address(smartVault), bob
        );
        vm.stopPrank();

        assertEq(nftId, 1, "NFT ID"); // deposit is made
        assertEq(tokenA.balanceOf(address(masterWallet)), 2 ether, "Token A - MasterWallet"); // swapped
        assertEq(tokenB.balanceOf(address(masterWallet)), 0.5 ether, "Token B - MasterWallet"); // swapped
        assertEq(tokenC.balanceOf(alice), 0.75 ether, "Token C - Alice"); // returned unswapped tokens

        DepositMetadata memory depositMetadata = smartVault.getDepositMetadata(nftId);

        assertEq(depositMetadata.assets.length, 2, "assets length"); // check deposit
        assertEq(depositMetadata.assets[0], 2 ether, "assets 0");
        assertEq(depositMetadata.assets[1], 0.5 ether, "assets 1");
        assertEq(smartVault.balanceOf(bob, nftId), 1, "NFT - Bob");
    }

    function test_depositSwap_swapAndDeposit_shouldDoPartialSwapAndThenDeposit() public {
        tokenA.mint(alice, 2 ether);

        MockExchange exchangeAB = new MockExchange(tokenA, tokenB, priceFeedManager);
        tokenA.mint(address(exchangeAB), 1000 ether);
        tokenB.mint(address(exchangeAB), 1000 ether);

        priceFeedManager.setExchangeRate(address(tokenA), 1 * 10 ** 26);
        priceFeedManager.setExchangeRate(address(tokenB), 1 * 10 ** 26);

        DepositSwap depositSwap = new DepositSwap(assetGroupRegistry, smartVaultManager, swapper);

        SwapInfo[] memory swapInfo = new SwapInfo[](1);
        swapInfo[0] = SwapInfo(
            address(exchangeAB),
            address(tokenA),
            0.4 ether,
            abi.encodeWithSelector(exchangeAB.swap.selector, address(tokenA), 0.4 ether, address(depositSwap))
        );

        vm.startPrank(alice);
        tokenA.approve(address(depositSwap), 2 ether);

        uint256 nftId = depositSwap.swapAndDeposit(
            Arrays.toArray(address(tokenA)), Arrays.toArray(2 ether), swapInfo, address(smartVault), bob
        );
        vm.stopPrank();

        assertEq(nftId, 1, "NFT ID"); // deposit is made
        assertEq(tokenA.balanceOf(address(masterWallet)), 1.6 ether, "Token A - MasterWallet"); // swapped
        assertEq(tokenB.balanceOf(address(masterWallet)), 0.4 ether, "Token B - MasterWallet"); // swapped
        assertEq(tokenA.balanceOf(alice), 0 ether, "Token A - Alice");

        DepositMetadata memory depositMetadata = smartVault.getDepositMetadata(nftId);

        assertEq(depositMetadata.assets.length, 2, "assets length"); // check deposit
        assertEq(depositMetadata.assets[0], 1.6 ether, "assets 0");
        assertEq(depositMetadata.assets[1], 0.4 ether, "assets 1");
        assertEq(smartVault.balanceOf(bob, nftId), 1, "NFT - Bob");
    }
}
