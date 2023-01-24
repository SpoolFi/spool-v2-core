// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

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
import "../../src/SmartVaultFactory.sol";
import "../../src/Swapper.sol";
import "../mocks/MockStrategy.sol";
import "../mocks/MockToken.sol";
import "../mocks/MockPriceFeedManager.sol";
import "../libraries/Arrays.sol";
import "../mocks/TestFixture.sol";

contract AllowlistGuardIntegrationTest is TestFixture {
    address private alice;
    address private bob;
    address private charlie;
    address private dave;
    address private eve;

    AllowlistGuard private allowlistGuard;

    function setUp() public {
        setUpBase();

        alice = address(0xa);
        bob = address(0xb);
        charlie = address(0xc);
        dave = address(0xd);
        eve = address(0xe);

        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(token)));

        (GuardDefinition[][] memory guards, RequestType[] memory guardRequestTypes) = setUpAllowlistGuard();

        MockStrategy strategy =
            new MockStrategy("Strategy", strategyRegistry, assetGroupRegistry, accessControl, new Swapper());
        {
            uint256[] memory strategyRatios = new uint256[](1);
            strategyRatios[0] = 1_000;
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
                    guards: guards,
                    guardRequestTypes: guardRequestTypes,
                    strategies: Arrays.toArray(address(strategy)),
                    riskAppetite: 4,
                    riskProvider: riskProvider
                })
            );
        }

        setUpAllowlist();
    }

    function setUpAllowlistGuard() private returns (GuardDefinition[][] memory, RequestType[] memory) {
        allowlistGuard = new AllowlistGuard(accessControl);

        // Setup smart vault with three guards:
        // - check whether the person executing the deposit is on allowlist
        // - check whether the person owning the assets being deposited is on allowlist
        // - check whether the person receiving the deposit NFT is on allowlist
        // All three guards are implemented using the `isAllowed` function of the
        // AllowlistGuard contract. Each of the three checks is using a different
        // allowlist, as to separate the three roles.
        // AllowlistGuards supports this by allowing multiple allowlists per each
        // smart vault, each allowlist having a different ID.
        GuardDefinition[][] memory guards = new GuardDefinition[][](1);
        guards[0] = new GuardDefinition[](3);

        // guard call receives three parameters:
        // - address of the smart vault
        // - ID of allowlist to use for the smart vault
        // - address to check against the allowlist
        GuardParamType[][] memory guardParamTypes = new GuardParamType[][](3);
        bytes[][] memory guardParamValues = new bytes[][](3);

        // first guard will check the person executing the deposit
        guardParamTypes[0] = new GuardParamType[](3);
        guardParamTypes[0][0] = GuardParamType.VaultAddress; // address of the smart vault
        guardParamTypes[0][1] = GuardParamType.CustomValue; // ID of the allowlist, set as method param value below
        guardParamTypes[0][2] = GuardParamType.Executor; // address of the executor
        guardParamValues[0] = new bytes[](1);
        guardParamValues[0][0] = abi.encode(uint256(0)); // ID of the allowlist is set to 0

        // second guard will check the person owning the assets being deposited
        guardParamTypes[1] = new GuardParamType[](3);
        guardParamTypes[1][0] = GuardParamType.VaultAddress; // address of the smart vault
        guardParamTypes[1][1] = GuardParamType.CustomValue; // ID of the allowlist, set as method param value below
        guardParamTypes[1][2] = GuardParamType.Owner; // address of the owner
        guardParamValues[1] = new bytes[](1);
        guardParamValues[1][0] = abi.encode(uint256(1)); // ID of the allowlist is set to 1

        // second guard will check the person receiving the deposit NFT
        guardParamTypes[2] = new GuardParamType[](3);
        guardParamTypes[2][0] = GuardParamType.VaultAddress; // address of the smart vault
        guardParamTypes[2][1] = GuardParamType.CustomValue; // ID of the allowlist, set as method param value below
        guardParamTypes[2][2] = GuardParamType.Receiver; // address of the receiver
        guardParamValues[2] = new bytes[](1);
        guardParamValues[2][0] = abi.encode(uint256(2)); // ID of the allowlist is set to 2

        // define the guards
        guards[0][0] = GuardDefinition({ // guard checking the executor
            contractAddress: address(allowlistGuard),
            methodSignature: "isAllowed(address,uint256,address)",
            expectedValue: 0, // do not need this
            methodParamTypes: guardParamTypes[0],
            methodParamValues: guardParamValues[0],
            operator: 0 // do not need this
        });
        guards[0][1] = GuardDefinition({ // guard checking the owner
            contractAddress: address(allowlistGuard),
            methodSignature: "isAllowed(address,uint256,address)",
            expectedValue: 0, // do not need this
            methodParamTypes: guardParamTypes[1],
            methodParamValues: guardParamValues[1],
            operator: 0 // do not need this
        });
        guards[0][2] = GuardDefinition({ // guard checking the receiver
            contractAddress: address(allowlistGuard),
            methodSignature: "isAllowed(address,uint256,address)",
            expectedValue: 0, // do not need this
            methodParamTypes: guardParamTypes[2],
            methodParamValues: guardParamValues[2],
            operator: 0 // do not need this
        });

        RequestType[] memory requestTypes = new RequestType[](1);
        requestTypes[0] = RequestType.Deposit;

        return (guards, requestTypes);
    }

    function setUpAllowlist() private {
        // allow Alice to update allowlists for the smart vault
        accessControl.grantSmartVaultRole(address(smartVault), ROLE_GUARD_ALLOWLIST_MANAGER, alice);

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
        smartVaultManager.depositFor(DepositBag(address(smartVault), depositAmounts, dave, address(0)), charlie);
        // deposit as Eve using Charlies assets with Dave set as receiver, should fail
        vm.prank(eve);
        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 0));
        smartVaultManager.depositFor(DepositBag(address(smartVault), depositAmounts, dave, address(0)), charlie);
        // deposit as Bob using Eve assets with Dave set as receiver, should fail
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 1));
        smartVaultManager.depositFor(DepositBag(address(smartVault), depositAmounts, dave, address(0)), eve);
        // deposit as Bob using Charlies assets with Eve set as receiver, should fail
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 2));
        smartVaultManager.depositFor(DepositBag(address(smartVault), depositAmounts, eve, address(0)), charlie);
    }
}
