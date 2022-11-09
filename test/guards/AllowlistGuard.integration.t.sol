// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "../../src/interfaces/RequestType.sol";
import "../../src/guards/AllowlistGuard.sol";
import "../../src/managers/ActionManager.sol";
import "../../src/managers/AssetGroupRegistry.sol";
import "../../src/managers/GuardManager.sol";
import "../../src/managers/RiskManager.sol";
import "../../src/managers/SmartVaultManager.sol";
import "../../src/managers/StrategyRegistry.sol";
import "../../src/managers/UsdPriceFeedManager.sol";
import "../../src/MasterWallet.sol";
import "../../src/SmartVault.sol";
import "../mocks/MockStrategy.sol";
import "../mocks/MockToken.sol";

contract AllowlistGuardIntegrationTest is Test, SpoolAccessRoles {
    address private alice;
    address private bob;
    address private charlie;
    address private dave;
    address private eve;

    MockToken private token;

    AllowlistGuard private allowlistGuard;
    GuardManager private guardManager;
    SmartVault private smartVault;
    SmartVaultManager private smartVaultManager;
    ISpoolAccessControl private accessControl;

    function setUp() public {
        alice = address(0xa);
        bob = address(0xb);
        charlie = address(0xc);
        dave = address(0xd);
        eve = address(0xe);

        token = new MockToken("Token", "T");
        accessControl = new SpoolAccessControl();

        ActionManager actionManager = new ActionManager();
        AssetGroupRegistry assetGroupRegistry = new AssetGroupRegistry();
        guardManager = new GuardManager();
        MasterWallet masterWallet = new MasterWallet();
        UsdPriceFeedManager priceFeedManager = new UsdPriceFeedManager();
        RiskManager riskManager = new RiskManager();
        SmartVaultDeposits vaultDepositManager = new SmartVaultDeposits(masterWallet);
        StrategyRegistry strategyRegistry = new StrategyRegistry(masterWallet, accessControl);
        smartVaultManager = new SmartVaultManager(
            accessControl,
            strategyRegistry,
            riskManager,
            vaultDepositManager,
            priceFeedManager,
            assetGroupRegistry,
            masterWallet,
            actionManager,
            guardManager
        );

        masterWallet.setWalletManager(address(smartVaultManager), true);

        allowlistGuard = new AllowlistGuard(accessControl);

        address[] memory assetGroup = new address[](1);
        assetGroup[0] = address(token);
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        MockStrategy strategy = new MockStrategy("Strategy", strategyRegistry, assetGroupRegistry);
        uint256[] memory strategyRatios = new uint256[](1);
        strategyRatios[0] = 1_000;
        strategy.initialize(assetGroupId, strategyRatios);
        strategyRegistry.registerStrategy(address(strategy));

        smartVault = new SmartVault("SmartVault", smartVaultManager);
        smartVault.initialize(assetGroupId, assetGroupRegistry);
        accessControl.grantRole(ROLE_SMART_VAULT, address(smartVault));
        IAction[] memory actions = new IAction[](0);
        RequestType[] memory actionsRequestTypes = new RequestType[](0);
        actionManager.setActions(address(smartVault), actions, actionsRequestTypes);
        address[] memory smartVaultStrategies = new address[](1);
        smartVaultStrategies[0] = address(strategy);
        smartVaultManager.setStrategies(address(smartVault), smartVaultStrategies);

        setUpAllowlistGuard();
    }

    function setUpAllowlistGuard() private {
        // Setup smart vault with three guards:
        // - check whether the person executing the deposit is on allowlist
        // - check whether the person owning the assets being deposited is on allowlist
        // - check whether the person receiving the deposit NFT is on allowlist
        // All three guards are implemented using the `isAllowed` function of the
        // AllowlistGuard contract. Each of the three checks is using a different
        // allowlist, as to separate the three roles.
        // AllowlistGuards supports this by allowing multiple allowlists per each
        // smart vault, each allowlist having a different ID.
        GuardDefinition[] memory guards = new GuardDefinition[](3);

        // guard call receives three parameters:
        // - address of the smart vault
        // - ID of allowlist to use for the smart vault
        // - address to check against the allowlist
        GuardParamType[][] memory guardParamTypes = new GuardParamType[][](3);
        bytes[][] memory methodParamValues = new bytes[][](3);

        // first guard will check the person executing the deposit
        guardParamTypes[0] = new GuardParamType[](3);
        guardParamTypes[0][0] = GuardParamType.VaultAddress; // address of the smart vault
        guardParamTypes[0][1] = GuardParamType.CustomValue; // ID of the allowlist, set as method param value below
        guardParamTypes[0][2] = GuardParamType.Executor; // address of the executor
        methodParamValues[0] = new bytes[](1);
        methodParamValues[0][0] = abi.encode(uint256(0)); // ID of the allowlist is set to 0

        // second guard will check the person owning the assets being deposited
        guardParamTypes[1] = new GuardParamType[](3);
        guardParamTypes[1][0] = GuardParamType.VaultAddress; // address of the smart vault
        guardParamTypes[1][1] = GuardParamType.CustomValue; // ID of the allowlist, set as method param value below
        guardParamTypes[1][2] = GuardParamType.Owner; // address of the owner
        methodParamValues[1] = new bytes[](1);
        methodParamValues[1][0] = abi.encode(uint256(1)); // ID of the allowlist is set to 1

        // second guard will check the person receiving the deposit NFT
        guardParamTypes[2] = new GuardParamType[](3);
        guardParamTypes[2][0] = GuardParamType.VaultAddress; // address of the smart vault
        guardParamTypes[2][1] = GuardParamType.CustomValue; // ID of the allowlist, set as method param value below
        guardParamTypes[2][2] = GuardParamType.Receiver; // address of the receiver
        methodParamValues[2] = new bytes[](1);
        methodParamValues[2][0] = abi.encode(uint256(2)); // ID of the allowlist is set to 2

        // define the guards
        guards[0] = GuardDefinition({ // guard checking the executor
            contractAddress: address(allowlistGuard),
            methodSignature: "isAllowed(address,uint256,address)",
            expectedValue: 0, // do not need this
            methodParamTypes: guardParamTypes[0],
            methodParamValues: methodParamValues[0],
            requestType: RequestType.Deposit,
            operator: 0 // do not need this
        });
        guards[1] = GuardDefinition({ // guard checking the owner
            contractAddress: address(allowlistGuard),
            methodSignature: "isAllowed(address,uint256,address)",
            expectedValue: 0, // do not need this
            methodParamTypes: guardParamTypes[1],
            methodParamValues: methodParamValues[1],
            requestType: RequestType.Deposit,
            operator: 0 // do not need this
        });
        guards[2] = GuardDefinition({ // guard checking the receiver
            contractAddress: address(allowlistGuard),
            methodSignature: "isAllowed(address,uint256,address)",
            expectedValue: 0, // do not need this
            methodParamTypes: guardParamTypes[2],
            methodParamValues: methodParamValues[2],
            requestType: RequestType.Deposit,
            operator: 0 // do not need this
        });

        // set guards for the smart vault
        guardManager.setGuards(address(smartVault), guards);

        // allow Alice to update allowlists for the smart vault
        smartVault.grantRole(allowlistGuard.ALLOWLIST_MANAGER_ROLE(), alice);
        address[] memory addressesToAdd = new address[](1);
        // Bob can execute the deposit
        addressesToAdd[0] = bob;

        vm.prank(alice);
        allowlistGuard.addToAllowlist(address(smartVault), 0, addressesToAdd);
        // Charlie can own the assets
        addressesToAdd[0] = charlie;
        vm.prank(alice);
        allowlistGuard.addToAllowlist(address(smartVault), 1, addressesToAdd);
        // Dave can receive the NFT
        addressesToAdd[0] = dave;
        vm.prank(alice);
        allowlistGuard.addToAllowlist(address(smartVault), 2, addressesToAdd);
    }

    function test() public {
        token.mint(charlie, 2 ether);
        token.mint(eve, 1 ether);

        vm.prank(charlie);
        token.approve(address(smartVaultManager), 2 ether);
        vm.prank(eve);
        token.approve(address(smartVaultManager), 1 ether);

        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1 ether;
        // deposit as Bob using Charlies assets with Dave set as receiver, should pass
        vm.prank(bob);
        smartVaultManager.depositFor(address(smartVault), depositAmounts, dave, charlie);
        // deposit as Eve using Charlies assets with Dave set as receiver, should fail
        vm.prank(eve);
        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 0));
        smartVaultManager.depositFor(address(smartVault), depositAmounts, dave, charlie);
        // deposit as Bob using Eve assets with Dave set as receiver, should fail
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 1));
        smartVaultManager.depositFor(address(smartVault), depositAmounts, dave, eve);
        // deposit as Bob using Charlies assets with Eve set as receiver, should fail
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 2));
        smartVaultManager.depositFor(address(smartVault), depositAmounts, eve, charlie);
    }
}
