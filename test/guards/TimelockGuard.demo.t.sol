// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../src/interfaces/RequestType.sol";
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
import "../mocks/MockStrategy.sol";
import "../mocks/MockNft.sol";
import "../mocks/MockToken.sol";
import "../mocks/MockPriceFeedManager.sol";
import "../mocks/MockGuard.sol";
import "../libraries/Arrays.sol";

contract NftGateGuardDemoTest is Test {
    address private alice = address(0xa);
    address private bob = address(0xb);
    address private charlie = address(0xc);
    address private eve = address(0xe);
    address private riskProvider = address(0x1);

    MockGuard private guard;
    MockToken private token;
    GuardManager private guardManager;
    ISmartVault private smartVault;
    SmartVaultManager private smartVaultManager;

    function setUp() public {
        token = new MockToken("Token", "T");
        guard = new MockGuard();

        SpoolAccessControl accessControl = new SpoolAccessControl();
        accessControl.initialize();
        ActionManager actionManager = new ActionManager(accessControl);
        AssetGroupRegistry assetGroupRegistry = new AssetGroupRegistry(Arrays.toArray(address(token)), accessControl);
        guardManager = new GuardManager(accessControl);
        MasterWallet masterWallet = new MasterWallet(accessControl);
        IUsdPriceFeedManager priceFeedManager = new MockPriceFeedManager();
        StrategyRegistry strategyRegistry = new StrategyRegistry(masterWallet, accessControl, priceFeedManager);
        IRiskManager riskManager = new RiskManager(accessControl);
        smartVaultManager = new SmartVaultManager(
            accessControl,
            strategyRegistry,
            priceFeedManager,
            assetGroupRegistry,
            masterWallet,
            actionManager,
            guardManager,
            riskManager
        );

        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_MASTER_WALLET_MANAGER, address(smartVaultManager));
        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);

        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(token)));
        MockStrategy strategy =
            new MockStrategy("Strategy", strategyRegistry, assetGroupRegistry, accessControl, new Swapper());
        {
            uint256[] memory strategyRatios = new uint256[](1);
            strategyRatios[0] = 1_000;
            strategy.initialize(assetGroupId, strategyRatios);
            strategyRegistry.registerStrategy(address(strategy));
        }

        (GuardDefinition[][] memory guards, RequestType[] memory guardRequestTypes) = setUpGuard();

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
                    guards: guards,
                    guardRequestTypes: guardRequestTypes,
                    strategies: Arrays.toArray(address(strategy)),
                    riskAppetite: 4,
                    riskProvider: riskProvider
                })
            );
        }
    }

    function setUpGuard() private view returns (GuardDefinition[][] memory, RequestType[] memory) {
        GuardDefinition[][] memory guards = new GuardDefinition[][](1);
        guards[0] = new GuardDefinition[](1);

        GuardParamType[] memory guardParamTypes = new GuardParamType[](3);
        guardParamTypes[0] = GuardParamType.VaultAddress;
        guardParamTypes[1] = GuardParamType.Assets;
        guardParamTypes[2] = GuardParamType.CustomValue;

        bytes[] memory paramValues = new bytes[](1);
        paramValues[0] = abi.encode(uint256(60 * 60 * 24));

        // define the guard
        guards[0][0] = GuardDefinition({ // guard checking the NFT balance of the receiver
            contractAddress: address(guard),
            methodParamTypes: guardParamTypes,
            methodSignature: "checkTimelock(address,uint256[],uint256)",
            methodParamValues: paramValues,
            operator: "",
            expectedValue: 0x0
        });

        RequestType[] memory requestTypes = new RequestType[](1);
        requestTypes[0] = RequestType.TransferNFT;

        return (guards, requestTypes);
    }

    function test_transferNFT_timelockReverts() public {
        token.mint(alice, 2 ether);

        vm.startPrank(alice);
        token.approve(address(smartVaultManager), 2 ether);
        uint256[] memory depositAmounts = Arrays.toArray(1 ether);
        uint256 tokenId = smartVaultManager.deposit(address(smartVault), depositAmounts, alice, address(0));
        DepositMetadata memory metadata =
            abi.decode(smartVault.getMetadata(Arrays.toArray(tokenId))[0], (DepositMetadata));

        assertEq(tokenId, 1);
        assertTrue(metadata.initiated > 0);

        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 0));
        smartVault.safeTransferFrom(alice, bob, tokenId, 1, "");

        vm.warp(block.timestamp + 60 * 60 * 24 + 1);
        smartVault.safeTransferFrom(alice, bob, tokenId, 1, "");
    }

    function test_burnNFT_timelockReverts() public {
        token.mint(alice, 2 ether);

        vm.prank(alice);
        token.approve(address(smartVaultManager), 2 ether);
        uint256[] memory depositAmounts = Arrays.toArray(1 ether);

        vm.prank(alice);
        uint256 tokenId = smartVaultManager.deposit(address(smartVault), depositAmounts, alice, address(0));
        DepositMetadata memory metadata =
            abi.decode(smartVault.getMetadata(Arrays.toArray(tokenId))[0], (DepositMetadata));

        assertEq(tokenId, 1);
        assertTrue(metadata.initiated > 0);

        vm.startPrank(address(smartVaultManager));

        uint256[] memory ids = Arrays.toArray(tokenId);
        uint256[] memory amounts = Arrays.toArray(NFT_MINTED_SHARES);
        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 0));
        smartVault.burnNFTs(alice, ids, amounts);

        vm.warp(block.timestamp + 60 * 60 * 24 + 1);
        smartVault.burnNFTs(alice, ids, amounts);
    }
}
