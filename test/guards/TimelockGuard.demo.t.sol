// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

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
import "../../src/Swapper.sol";
import "../mocks/MockStrategy.sol";
import "../mocks/MockNft.sol";
import "../mocks/MockToken.sol";
import "../mocks/MockPriceFeedManager.sol";
import "../mocks/MockGuard.sol";
import "../libraries/Arrays.sol";

contract NftGateGuardDemoTest is Test, SpoolAccessRoles {
    address private alice = address(0xa);
    address private bob = address(0xb);
    address private charlie = address(0xc);
    address private eve = address(0xe);
    address private riskProvider = address(0x1);

    MockGuard private guard;
    MockToken private token;
    GuardManager private guardManager;
    SmartVault private smartVault;
    SmartVaultManager private smartVaultManager;

    function setUp() public {
        token = new MockToken("Token", "T");
        guard = new MockGuard();

        ISpoolAccessControl accessControl = new SpoolAccessControl();
        ActionManager actionManager = new ActionManager(accessControl);
        AssetGroupRegistry assetGroupRegistry = new AssetGroupRegistry();
        guardManager = new GuardManager(accessControl);
        MasterWallet masterWallet = new MasterWallet(accessControl);
        IUsdPriceFeedManager priceFeedManager = new MockPriceFeedManager();
        StrategyRegistry strategyRegistry = new StrategyRegistry(masterWallet, accessControl, priceFeedManager);
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

        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(token)));
        MockStrategy strategy =
            new MockStrategy("Strategy", strategyRegistry, assetGroupRegistry, accessControl, new Swapper());
        {
            uint256[] memory strategyRatios = new uint256[](1);
            strategyRatios[0] = 1_000;
            strategy.initialize(assetGroupId, strategyRatios);
            strategyRegistry.registerStrategy(address(strategy));
        }

        {
            smartVault = new SmartVault("SmartVault", accessControl, guardManager);
            smartVault.initialize(assetGroupId);
            accessControl.grantRole(ROLE_SMART_VAULT, address(smartVault));
            actionManager.setActions(address(smartVault), new IAction[](0), new RequestType[](0));
            SmartVaultRegistrationForm memory registrationForm = SmartVaultRegistrationForm({
                assetGroupId: assetGroupId,
                strategies: Arrays.toArray(address(strategy)),
                strategyAllocations: Arrays.toArray(1_000),
                riskProvider: riskProvider
            });
            smartVaultManager.registerSmartVault(address(smartVault), registrationForm);
        }

        setUpGuard();
    }

    function setUpGuard() private {
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

        // set guards for the smart contract
        guardManager.setGuards(address(smartVault), guards, requestTypes);
    }

    function test_transferNFT_timelockReverts() public {
        token.mint(alice, 2 ether);

        vm.startPrank(alice);
        token.approve(address(smartVaultManager), 2 ether);
        uint256[] memory depositAmounts = Arrays.toArray(1 ether);
        uint256 tokenId = smartVaultManager.deposit(address(smartVault), depositAmounts, alice, address(0));
        DepositMetadata memory metadata = smartVault.getDepositMetadata(tokenId);

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
        DepositMetadata memory metadata = smartVault.getDepositMetadata(tokenId);

        assertEq(tokenId, 1);
        assertTrue(metadata.initiated > 0);

        vm.startPrank(address(smartVaultManager));

        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 0));
        smartVault.burnNFT(alice, tokenId, RequestType.Deposit);

        vm.warp(block.timestamp + 60 * 60 * 24 + 1);
        smartVault.burnNFT(alice, tokenId, RequestType.Deposit);
    }
}
