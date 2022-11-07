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

contract AllowlistGuardIntergrationTest is Test {
    address private alice;
    address private bob;
    address private charlie;

    MockToken private token;

    AllowlistGuard private allowlistGuard;
    GuardManager private guardManager;
    SmartVault private smartVault;
    SmartVaultManager private smartVaultManager;

    function setUp() public {
        alice = address(0xa);
        bob = address(0xb);
        charlie = address(0xc);

        token = new MockToken("Token", "T");

        ActionManager actionManager = new ActionManager();
        AssetGroupRegistry assetGroupRegistry = new AssetGroupRegistry();
        guardManager = new GuardManager();
        MasterWallet masterWallet = new MasterWallet();
        UsdPriceFeedManager priceFeedManager = new UsdPriceFeedManager();
        RiskManager riskManager = new RiskManager();
        SmartVaultDeposits vaultDepositManager = new SmartVaultDeposits(masterWallet);
        StrategyRegistry strategyRegistry = new StrategyRegistry(masterWallet);
        smartVaultManager = new SmartVaultManager(
            strategyRegistry,
            riskManager,
            vaultDepositManager,
            priceFeedManager,
            assetGroupRegistry,
            masterWallet,
            actionManager,
            guardManager
        );

        strategyRegistry.initialize();

        masterWallet.setWalletManager(address(smartVaultManager), true);

        allowlistGuard = new AllowlistGuard();

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
        smartVaultManager.registerSmartVault(address(smartVault));
        IAction[] memory actions = new IAction[](0);
        RequestType[] memory actionsRequestTypes = new RequestType[](0);
        actionManager.setActions(address(smartVault), actions, actionsRequestTypes);
        address[] memory smartVaultStrategies = new address[](1);
        smartVaultStrategies[0] = address(strategy);
        smartVaultManager.setStrategies(address(smartVault), smartVaultStrategies);

        setUpAllowlistGuard();
    }

    function setUpAllowlistGuard() private {
        // setup smart vault to use AllowlistGuard.isAllowed as the only guard
        GuardDefinition[] memory guards = new GuardDefinition[](1);

        // guard call receives 3 parameters:
        // - address of the smart vault
        // - ID of allowlist to use for the smart vault
        // - address to check against the allowlist
        GuardParamType[] memory guardParamTypes = new GuardParamType[](3);
        guardParamTypes[0] = GuardParamType.VaultAddress; // address of the smart vault
        guardParamTypes[1] = GuardParamType.CustomValue; // ID of the allowlist
        guardParamTypes[2] = GuardParamType.Receiver; // address to check is set to the receiver

        bytes[] memory methodParamValues = new bytes[](1);
        methodParamValues[0] = abi.encode(uint256(0)); // ID of the allowlist is set to 0

        // define the guard
        guards[0] = GuardDefinition({
            contractAddress: address(allowlistGuard),
            methodSignature: "isAllowed(address,uint256,address)",
            expectedValue: 0, // do not need this
            methodParamTypes: guardParamTypes,
            methodParamValues: methodParamValues,
            requestType: RequestType.Deposit,
            operator: 0 // do not need this
        });

        // set guards for the smart vault
        guardManager.setGuards(address(smartVault), guards);

        // allow Alice to update allowlists for the smart vault
        smartVault.grantRole(allowlistGuard.ALLOWLIST_MANAGER_ROLE(), alice);
        // add Bob to the allowlist
        address[] memory addressesToAdd = new address[](1);
        addressesToAdd[0] = bob;
        vm.prank(alice);
        allowlistGuard.addToAllowlist(address(smartVault), 0, addressesToAdd);
    }

    function test() public {
        token.mint(alice, 2 ether);
        vm.startPrank(alice);

        token.approve(address(smartVaultManager), 2 ether);
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1 ether;
        // deposit with Bob as receiver, should pass
        uint256 bobDepositNftId = smartVaultManager.deposit(address(smartVault), depositAmounts, bob);

        assertEq(bobDepositNftId, 1);

        token.approve(address(smartVaultManager), 1 ether);

        vm.expectRevert(GuardFailed.selector);
        // deposit with Charlie as receiver, should revert
        smartVaultManager.deposit(address(smartVault), depositAmounts, charlie);

        vm.stopPrank();
    }
}
