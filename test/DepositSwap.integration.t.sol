// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/Test.sol";
import "../src/interfaces/RequestType.sol";
import "../src/DepositSwap.sol";
import "../src/SmartVaultFactory.sol";
import "../src/MetaVault.sol";
import "../src/Swapper.sol";
import "./libraries/Arrays.sol";
import "./libraries/Constants.sol";
import "./mocks/MockExchange.sol";
import "./mocks/MockPriceFeedManager.sol";
import "./mocks/MockStrategy.sol";
import "./mocks/MockToken.sol";
import "./fixtures/TestFixture.sol";
import "./mocks/MockWeth.sol";

contract DepositSwapIntegrationTest is TestFixture {
    address private alice;
    address private bob;
    address swapperAdmin;

    MockToken private tokenA;
    MockToken private tokenB;
    MockToken private tokenC;

    IWETH9 private weth;

    DepositSwap depositSwap;
    ISmartVault smartVaultWeth;

    function setUp() public {
        setUpBase();

        alice = address(0xa);
        bob = address(0xb);
        swapperAdmin = address(0xc);

        accessControl.grantRole(ROLE_SPOOL_ADMIN, swapperAdmin);

        address[] memory sorted = Arrays.sort(
            Arrays.toArray(
                address(new MockToken("Token", "T")),
                address(new MockToken("Token", "T")),
                address(new MockToken("Token", "T"))
            )
        );

        tokenA = MockToken(sorted[0]);
        tokenB = MockToken(sorted[1]);
        tokenC = MockToken(sorted[2]);
        weth = IWETH9(address(new WETH9()));

        assetGroupRegistry.allowToken(address(tokenA));
        assetGroupRegistry.allowToken(address(tokenB));
        assetGroupRegistry.allowToken(address(tokenC));
        assetGroupRegistry.allowToken(address(weth));

        {
            uint256 assetGroupId;
            {
                address[] memory assetGroup = new address[](2);
                assetGroup[0] = address(tokenA);
                assetGroup[1] = address(tokenB);
                assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
            }

            MockStrategy strategy = new MockStrategy(assetGroupRegistry, accessControl, swapper, assetGroupId);
            {
                uint256[] memory strategyRatios = new uint256[](2);
                strategyRatios[0] = 800;
                strategyRatios[1] = 200;
                strategy.initialize("Strategy", strategyRatios);
                strategyRegistry.registerStrategy(address(strategy), 0, ATOMIC_STRATEGY);
            }

            {
                vm.mockCall(
                    address(riskManager),
                    abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                    abi.encode(Arrays.toUint16a16(1_000))
                );

                smartVault = smartVaultFactory.deploySmartVault(
                    SmartVaultSpecification({
                        smartVaultName: "SmartVault",
                        svtSymbol: "SV",
                        baseURI: "https://token-cdn-domain/",
                        assetGroupId: assetGroupId,
                        actions: new IAction[](0),
                        actionRequestTypes: new RequestType[](0),
                        guards: new GuardDefinition[][](0),
                        guardRequestTypes: new RequestType[](0),
                        strategies: Arrays.toArray(address(strategy)),
                        strategyAllocation: Arrays.toUint16a16(FULL_PERCENT),
                        riskTolerance: 0,
                        riskProvider: address(0),
                        allocationProvider: address(0),
                        managementFeePct: 0,
                        depositFeePct: 0,
                        allowRedeemFor: false,
                        performanceFeePct: 0
                    })
                );
            }
        }

        {
            uint256 assetGroupId;
            {
                address[] memory assetGroup = new address[](1);
                assetGroup[0] = address(weth);
                assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
            }

            MockStrategy strategy = new MockStrategy(assetGroupRegistry, accessControl, swapper, assetGroupId);
            {
                uint256[] memory strategyRatios = new uint256[](1);
                strategyRatios[0] = 1000;
                strategy.initialize("Strategy WETH", strategyRatios);
                strategyRegistry.registerStrategy(address(strategy), 0, ATOMIC_STRATEGY);
            }

            {
                smartVaultWeth = smartVaultFactory.deploySmartVault(
                    SmartVaultSpecification({
                        smartVaultName: "SmartVault WETH",
                        svtSymbol: "SVW",
                        baseURI: "https://token-cdn-domain/",
                        assetGroupId: assetGroupId,
                        actions: new IAction[](0),
                        actionRequestTypes: new RequestType[](0),
                        guards: new GuardDefinition[][](0),
                        guardRequestTypes: new RequestType[](0),
                        strategies: Arrays.toArray(address(strategy)),
                        strategyAllocation: Arrays.toUint16a16(FULL_PERCENT),
                        riskTolerance: 0,
                        riskProvider: address(0),
                        allocationProvider: address(0),
                        managementFeePct: 0,
                        depositFeePct: 0,
                        allowRedeemFor: false,
                        performanceFeePct: 0
                    })
                );
            }
        }
    }

    function test_depositSwap_swapAndDeposit_shouldDoCompleteSwapAndThenDeposit() public {
        tokenC.mint(alice, 2 ether);

        MockExchange exchangeAC = new MockExchange(tokenA, tokenC, priceFeedManager);
        tokenA.mint(address(exchangeAC), 1000 ether);
        MockExchange exchangeBC = new MockExchange(tokenB, tokenC, priceFeedManager);
        tokenB.mint(address(exchangeBC), 1000 ether);

        vm.startPrank(swapperAdmin);
        swapper.updateExchangeAllowlist(
            Arrays.toArray(address(exchangeAC), address(exchangeBC)), Arrays.toArray(true, true)
        );
        vm.stopPrank();

        priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(tokenB), 1 * USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(tokenC), 2 * USD_DECIMALS_MULTIPLIER);

        depositSwap = new DepositSwap(weth, assetGroupRegistry, smartVaultManager, swapper);
        accessControl.grantRole(ROLE_SWAPPER, address(depositSwap));

        SwapInfo[] memory swapInfo = new SwapInfo[](2);
        swapInfo[0] = SwapInfo(
            address(exchangeAC),
            address(tokenC),
            abi.encodeWithSelector(exchangeAC.swap.selector, address(tokenC), 1 ether, address(depositSwap))
        );
        swapInfo[1] = SwapInfo(
            address(exchangeBC),
            address(tokenC),
            abi.encodeWithSelector(exchangeBC.swap.selector, address(tokenC), 0.25 ether, address(depositSwap))
        );

        vm.startPrank(alice);
        tokenC.approve(address(depositSwap), 2 ether);

        uint256 nftId = depositSwap.swapAndDeposit(
            SwapDepositBag(
                Arrays.toArray(address(tokenC)),
                Arrays.toArray(2 ether),
                swapInfo,
                address(smartVault),
                bob,
                address(0),
                false
            )
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
        tokenB.mint(address(exchangeAB), 1000 ether);

        vm.startPrank(swapperAdmin);
        swapper.updateExchangeAllowlist(Arrays.toArray(address(exchangeAB)), Arrays.toArray(true));
        vm.stopPrank();

        priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(tokenB), 1 * USD_DECIMALS_MULTIPLIER);

        depositSwap = new DepositSwap(weth, assetGroupRegistry, smartVaultManager, swapper);
        accessControl.grantRole(ROLE_SWAPPER, address(depositSwap));

        SwapInfo[] memory swapInfo = new SwapInfo[](1);
        swapInfo[0] = SwapInfo(
            address(exchangeAB),
            address(tokenA),
            abi.encodeWithSelector(exchangeAB.swap.selector, address(tokenA), 0.4 ether, address(depositSwap))
        );

        vm.startPrank(alice);
        tokenA.approve(address(depositSwap), 2 ether);

        uint256 nftId = depositSwap.swapAndDeposit(
            SwapDepositBag(
                Arrays.toArray(address(tokenA)),
                Arrays.toArray(2 ether),
                swapInfo,
                address(smartVault),
                bob,
                address(0),
                false
            )
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

    function test_depositSwap_swapAndDeposit_shouldWrapEthSwapItAndThenDeposit() public {
        vm.deal(alice, 3 ether);
        vm.prank(alice);
        weth.deposit{value: 1 ether}(); // Alice wraps 1 ether

        MockExchange exchangeWethA = new MockExchange(IERC20(address(weth)), tokenA, priceFeedManager);
        tokenA.mint(address(exchangeWethA), 1000 ether);
        MockExchange exchangeWethB = new MockExchange(IERC20(address(weth)), tokenB, priceFeedManager);
        tokenB.mint(address(exchangeWethB), 1000 ether);

        vm.startPrank(swapperAdmin);
        swapper.updateExchangeAllowlist(
            Arrays.toArray(address(exchangeWethA), address(exchangeWethB)), Arrays.toArray(true, true)
        );
        vm.stopPrank();

        priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(tokenB), 1 * USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(weth), 1 * USD_DECIMALS_MULTIPLIER);

        depositSwap = new DepositSwap(weth, assetGroupRegistry, smartVaultManager, swapper);
        accessControl.grantRole(ROLE_SWAPPER, address(depositSwap));

        SwapInfo[] memory swapInfo = new SwapInfo[](2);
        swapInfo[0] = SwapInfo(
            address(exchangeWethA),
            address(weth),
            abi.encodeWithSelector(exchangeWethA.swap.selector, address(weth), 2 ether, address(depositSwap))
        );
        swapInfo[1] = SwapInfo(
            address(exchangeWethB),
            address(weth),
            abi.encodeWithSelector(exchangeWethB.swap.selector, address(weth), 0.5 ether, address(depositSwap))
        );

        vm.startPrank(alice);
        IERC20(address(weth)).approve(address(depositSwap), 1 ether);

        uint256 nftId = depositSwap.swapAndDeposit{value: 2 ether}(
            SwapDepositBag(
                Arrays.toArray(address(weth)),
                Arrays.toArray(1 ether),
                swapInfo,
                address(smartVault),
                bob,
                address(0),
                false
            )
        ); // Alice sends in 2 ether and 1 wrapped ether
        vm.stopPrank();

        assertEq(nftId, 1, "NFT ID"); // deposit is made
        assertEq(tokenA.balanceOf(address(masterWallet)), 2 ether, "Token A - MasterWallet"); // swapped
        assertEq(tokenB.balanceOf(address(masterWallet)), 0.5 ether, "Token B - MasterWallet"); // swapped
        assertEq(IERC20(address(weth)).balanceOf(alice), 0.5 ether, "WETH - Alice"); // unswapped

        DepositMetadata memory depositMetadata =
            abi.decode(smartVault.getMetadata(Arrays.toArray(nftId))[0], (DepositMetadata));

        assertEq(depositMetadata.assets.length, 2, "assets length"); // check deposit
        assertEq(depositMetadata.assets[0], 2 ether, "assets 0");
        assertEq(depositMetadata.assets[1], 0.5 ether, "assets 1");
        assertEq(smartVault.balanceOfFractional(bob, nftId), NFT_MINTED_SHARES, "NFT - Bob");
    }

    function test_depositSwap_swapAndDeposit_shouldWrapAndReturnItEvenWhenNotInInTokens() public {
        vm.deal(alice, 2 ether);
        tokenA.mint(alice, 2 ether);
        tokenB.mint(alice, 0.5 ether);

        priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);

        depositSwap = new DepositSwap(weth, assetGroupRegistry, smartVaultManager, swapper);
        accessControl.grantRole(ROLE_SWAPPER, address(depositSwap));

        SwapInfo[] memory swapInfo = new SwapInfo[](0);

        vm.startPrank(alice);
        IERC20(address(tokenA)).approve(address(depositSwap), 2 ether);
        IERC20(address(tokenB)).approve(address(depositSwap), 0.5 ether);

        uint256 nftId = depositSwap.swapAndDeposit{value: 2 ether}(
            SwapDepositBag(
                Arrays.toArray(address(tokenA), address(tokenB)),
                Arrays.toArray(2 ether, 0.5 ether),
                swapInfo,
                address(smartVault),
                bob,
                address(0),
                false
            )
        ); // Alice sends in 2 ether but it is not used
        vm.stopPrank();

        assertEq(nftId, 1, "NFT ID"); // deposit is made
        assertEq(tokenA.balanceOf(address(masterWallet)), 2 ether, "Token A - MasterWallet"); // deposited
        assertEq(tokenB.balanceOf(address(masterWallet)), 0.5 ether, "Token B - MasterWallet"); // deposited
        assertEq(IERC20(address(weth)).balanceOf(alice), 2 ether, "WETH - Alice"); // returned
    }

    function test_depositSwap_swapAndDeposit_shouldWrapEthAndDepositIt() public {
        vm.deal(alice, 2 ether);

        priceFeedManager.setExchangeRate(address(weth), 1000 * USD_DECIMALS_MULTIPLIER);

        depositSwap = new DepositSwap(weth, assetGroupRegistry, smartVaultManager, swapper);
        accessControl.grantRole(ROLE_SWAPPER, address(depositSwap));

        vm.startPrank(alice);
        IERC20(address(weth)).approve(address(depositSwap), 1 ether);

        uint256 nftId = depositSwap.swapAndDeposit{value: 1 ether}(
            SwapDepositBag(
                Arrays.toArray(address(weth)),
                Arrays.toArray(0),
                new SwapInfo[](0),
                address(smartVaultWeth),
                alice,
                address(0),
                false
            )
        ); // Alice sends in 1 ether
        vm.stopPrank();

        assertEq(nftId, 1, "NFT ID"); // deposit is made
        assertEq(IERC20(address(weth)).balanceOf(address(masterWallet)), 1 ether, "WETH - MasterWallet"); // deposited
        assertEq(IERC20(address(weth)).balanceOf(alice), 0, "WETH - Alice"); // no WETH returned
    }

    function test_swapAndDepositIntoMetaVault() external {
        tokenA.mint(alice, 2 ether);

        MockExchange exchangeAB = new MockExchange(tokenA, tokenB, priceFeedManager);
        tokenB.mint(address(exchangeAB), 1000 ether);

        vm.startPrank(swapperAdmin);
        swapper.updateExchangeAllowlist(Arrays.toArray(address(exchangeAB)), Arrays.toArray(true));
        vm.stopPrank();

        priceFeedManager.setExchangeRate(address(tokenA), 1 * USD_DECIMALS_MULTIPLIER);
        priceFeedManager.setExchangeRate(address(tokenB), 1 * USD_DECIMALS_MULTIPLIER);

        depositSwap = new DepositSwap(weth, assetGroupRegistry, smartVaultManager, swapper);
        accessControl.grantRole(ROLE_SWAPPER, address(depositSwap));

        SwapInfo[] memory swapInfo = new SwapInfo[](1);
        uint256 swapAmount = 0.4 ether;
        swapInfo[0] = SwapInfo(
            address(exchangeAB),
            address(tokenA),
            abi.encodeWithSelector(exchangeAB.swap.selector, address(tokenA), swapAmount, address(depositSwap))
        );

        vm.startPrank(alice);
        tokenA.approve(address(depositSwap), 2 ether);

        MetaVault metaVaultImplementation = new MetaVault(
            ISmartVaultManager(address(0x1)),
            ISpoolAccessControl(address(0x2)),
            IMetaVaultGuard(address(0x3)),
            ISpoolLens(address(0x4))
        );
        MetaVault metaVault =
            MetaVault(address(new TransparentUpgradeableProxy(address(metaVaultImplementation), address(0x1), "")));
        metaVault.initialize(address(this), address(tokenB), "MV", "MVT", new address[](0), new uint256[](0));

        depositSwap.swapAndDepositIntoMetaVault(
            metaVault, Arrays.toArray(address(tokenA)), Arrays.toArray(2 ether), swapInfo
        );
        vm.stopPrank();

        assertEq(tokenA.balanceOf(alice), 1.6 ether, "Token A - Alice");
        assertEq(tokenB.balanceOf(address(metaVault)), swapAmount, "Token B - MetaVault"); // swapped
        assertEq(metaVault.flushToDepositedAssets(0), swapAmount);
        assertEq(metaVault.userToFlushToDepositedAssets(alice, 0), swapAmount);
    }
}
