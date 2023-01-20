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
import "./libraries/Constants.sol";
import "./mocks/MockExchange.sol";
import "./mocks/MockPriceFeedManager.sol";
import "./mocks/MockStrategy.sol";
import "./mocks/MockToken.sol";
import "./mocks/BaseTestContracts.sol";

contract DepositSwapIntegrationTest is BaseTestContracts, Test {
    address private alice;
    address private bob;

    MockToken private tokenA;
    MockToken private tokenB;
    MockToken private tokenC;

    Swapper private swapper;

    function setUp() public {
        setUpBase();

        alice = address(0xa);
        bob = address(0xb);

        tokenA = new MockToken("Token A", "TA");
        tokenB = new MockToken("Token B", "TB");
        tokenC = new MockToken("Token C", "TC");

        assetGroupRegistry.allowToken(address(tokenA));
        assetGroupRegistry.allowToken(address(tokenB));
        assetGroupRegistry.allowToken(address(tokenC));
        assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(tokenA), address(tokenB), address(tokenC)));

        swapper = new Swapper();

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

            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toArray(1_000))
            );

            smartVault = smartVaultFactory.deploySmartVault(
                SmartVaultSpecification({
                    smartVaultName: "SmartVault",
                    assetGroupId: assetGroupId,
                    actions: new IAction[](0),
                    actionRequestTypes: new RequestType[](0),
                    guards: new GuardDefinition[][](0),
                    guardRequestTypes: new RequestType[](0),
                    strategies: Arrays.toArray(address(strategy)),
                    riskAppetite: 4,
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

        priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(tokenB), 1 * USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(tokenC), 2 * USD_DECIMALS_MULTIPLIER);

        DepositSwap depositSwap = new DepositSwap(assetGroupRegistry, smartVaultManager, swapper, depositManager);

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

        DepositMetadata memory depositMetadata =
            abi.decode(smartVault.getMetadata(Arrays.toArray(nftId))[0], (DepositMetadata));

        assertEq(depositMetadata.assets.length, 2, "assets length"); // check deposit
        assertEq(depositMetadata.assets[0], 2 ether, "assets 0");
        assertEq(depositMetadata.assets[1], 0.5 ether, "assets 1");
        assertEq(smartVault.balanceOfFractional(bob, nftId), NFT_MINTED_SHARES, "NFT - Bob");
    }

    function test_depositSwap_swapAndDeposit_shouldDoPartialSwapAndThenDeposit() public {
        tokenA.mint(alice, 2 ether);

        MockExchange exchangeAB = new MockExchange(tokenA, tokenB, priceFeedManager);
        tokenA.mint(address(exchangeAB), 1000 ether);
        tokenB.mint(address(exchangeAB), 1000 ether);

        priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(tokenB), 1 * USD_DECIMALS_MULTIPLIER);

        DepositSwap depositSwap = new DepositSwap(assetGroupRegistry, smartVaultManager, swapper, depositManager);

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

        DepositMetadata memory depositMetadata =
            abi.decode(smartVault.getMetadata(Arrays.toArray(nftId))[0], (DepositMetadata));

        assertEq(depositMetadata.assets.length, 2, "assets length"); // check deposit
        assertEq(depositMetadata.assets[0], 1.6 ether, "assets 0");
        assertEq(depositMetadata.assets[1], 0.4 ether, "assets 1");
        assertEq(smartVault.balanceOfFractional(bob, nftId), NFT_MINTED_SHARES, "NFT - Bob");
    }
}
