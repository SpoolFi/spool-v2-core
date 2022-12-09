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

contract NftGateGuardDemoTest is Test, SpoolAccessRoles {
    address private alice;
    address private bob;
    address private charlie;
    address private eve;

    MockNft private nft;
    MockToken private token;

    GuardManager private guardManager;
    SmartVault private smartVault;
    SmartVaultManager private smartVaultManager;

    function setUp() public {
        alice = address(0xa);
        bob = address(0xb);
        charlie = address(0xc);
        eve = address(0xe);

        address riskProvider = address(0x1);

        nft = new MockNft("Nft", "N");
        token = new MockToken("Token", "T");

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

        uint256 assetGroupId;
        {
            address[] memory assetGroup = new address[](1);
            assetGroup[0] = address(token);
            assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        }

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
            IAction[] memory actions = new IAction[](0);
            RequestType[] memory actionsRequestTypes = new RequestType[](0);
            actionManager.setActions(address(smartVault), actions, actionsRequestTypes);
            address[] memory smartVaultStrategies = new address[](1);
            smartVaultStrategies[0] = address(strategy);
            uint256[] memory smartVaultStrategyAllocations = new uint256[](1);
            smartVaultStrategyAllocations[0] = 1_000;
            SmartVaultRegistrationForm memory registrationForm = SmartVaultRegistrationForm({
                assetGroupId: assetGroupId,
                strategies: smartVaultStrategies,
                strategyAllocations: smartVaultStrategyAllocations,
                riskProvider: riskProvider
            });
            smartVaultManager.registerSmartVault(address(smartVault), registrationForm);
        }

        setUpNftGateGuard();
    }

    function setUpNftGateGuard() private {
        // Setup smart vault with one guard:
        // - check that the person receiving the deposit NFT has at least one selected NFT
        // The guard is implemented using the `balanceOf` function of the IERC721 contract.
        GuardDefinition[][] memory guards = new GuardDefinition[][](1);
        guards[0] = new GuardDefinition[](1);

        // guard call receives one parameter:
        // - address to check the NFT balance of
        GuardParamType[] memory guardParamTypes = new GuardParamType[](1);
        bytes[] memory guardParamValues = new bytes[](0);

        // the guard will check the NFT balance of the receiver
        guardParamTypes[0] = GuardParamType.Receiver;

        // define the guard
        guards[0][0] = GuardDefinition({ // guard checking the NFT balance of the receiver
            contractAddress: address(nft),
            methodSignature: "balanceOf(address)",
            methodParamTypes: guardParamTypes,
            methodParamValues: guardParamValues,
            operator: ">=", // balance must be equal to or greater than 1
            expectedValue: bytes32(uint256(1))
        });

        RequestType[] memory requestTypes = new RequestType[](1);
        requestTypes[0] = RequestType.Deposit;

        // set guards for the smart contract
        guardManager.setGuards(address(smartVault), guards, requestTypes);

        // mint one NFT for Bob and two NFTs for Charlie
        nft.mint(bob);
        nft.mint(charlie);
        nft.mint(charlie);
    }

    function test() public {
        token.mint(alice, 2 ether);

        vm.prank(alice);
        token.approve(address(smartVaultManager), 2 ether);

        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1 ether;

        vm.prank(alice);
        // deposit for Bob who has one NFT, should pass
        smartVaultManager.deposit(address(smartVault), depositAmounts, bob, address(0));
        vm.prank(alice);
        // deposit for Charlie who has two NFTs, should pass
        smartVaultManager.deposit(address(smartVault), depositAmounts, charlie, address(0));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 0));
        // deposit for Eve who doesn't have any NFT, should fail
        smartVaultManager.deposit(address(smartVault), depositAmounts, eve, address(0));
    }
}
