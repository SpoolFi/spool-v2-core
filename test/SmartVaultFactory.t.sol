// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Test} from "forge-std/Test.sol";
import {IAccessControlUpgradeable} from "@openzeppelin-upgradeable/access/IAccessControlUpgradeable.sol";
import {IActionManager, IAction} from "../src/interfaces/IAction.sol";
import {IAssetGroupRegistry} from "../src/interfaces/IAssetGroupRegistry.sol";
import "../src/interfaces/IGuardManager.sol";
import {RequestType} from "../src/interfaces/RequestType.sol";
import {ISmartVault} from "../src/interfaces/ISmartVault.sol";
import {ISmartVaultManager} from "../src/interfaces/ISmartVaultManager.sol";
import {ISpoolAccessControl} from "../src/interfaces/ISpoolAccessControl.sol";
import {SmartVault} from "../src/SmartVault.sol";
import {SmartVaultFactory, SmartVaultSpecification} from "../src/SmartVaultFactory.sol";
import {Arrays} from "./libraries/Arrays.sol";

contract SmartVaultVariant is SmartVault {
    uint256 private immutable _testValue;

    constructor(ISpoolAccessControl accessControl_, IGuardManager guardManager_, uint256 testValue_)
        SmartVault(accessControl_, guardManager_)
    {
        _testValue = testValue_;
    }

    function test_mock() external pure {}

    function getTestValue() external view returns (uint256) {
        return _testValue;
    }
}

contract SmartVaultFactoryTest is Test {
    event SmartVaultDeployed(address indexed smartVault, address indexed deployer);

    SmartVaultFactory private factory;

    ISpoolAccessControl accessControl;
    IActionManager actionManager;
    IGuardManager guardManager;
    ISmartVaultManager smartVaultManager;
    IAssetGroupRegistry assetGroupRegistry;

    function setUp() public {
        accessControl = ISpoolAccessControl(address(0x1));
        vm.mockCall(
            address(accessControl), abi.encodeWithSelector(IAccessControlUpgradeable.grantRole.selector), abi.encode(0)
        );

        actionManager = IActionManager(address(0x2));
        vm.mockCall(address(actionManager), abi.encodeWithSelector(IActionManager.setActions.selector), abi.encode(0));

        guardManager = IGuardManager(address(0x3));
        vm.mockCall(address(guardManager), abi.encodeWithSelector(IGuardManager.setGuards.selector), abi.encode(0));

        smartVaultManager = ISmartVaultManager(address(0x4));
        vm.mockCall(
            address(smartVaultManager),
            abi.encodeWithSelector(ISmartVaultManager.registerSmartVault.selector),
            abi.encode(0)
        );

        assetGroupRegistry = IAssetGroupRegistry(address(0x5));
        vm.mockCall(
            address(assetGroupRegistry),
            abi.encodeWithSelector(IAssetGroupRegistry.validateAssetGroup.selector),
            abi.encode(0)
        );

        address implementation1 = address(new SmartVaultVariant(accessControl, guardManager, 1));

        factory = new SmartVaultFactory(
            implementation1,
            accessControl,
            actionManager,
            guardManager,
            smartVaultManager,
            assetGroupRegistry
        );
    }

    /* ========== deploySmartVault ========== */

    function test_deploySmartVault_shouldDeploySmartVault() public {
        ISmartVault mySmartVault = factory.deploySmartVault(_getSpecification());

        assertEq(mySmartVault.vaultName(), "MySmartVault");
    }

    function test_deploySmartVault_shouldValidateSpecification() public {
        // - validate asset group
        vm.expectCall(
            address(assetGroupRegistry), abi.encodeWithSelector(IAssetGroupRegistry.validateAssetGroup.selector)
        );

        factory.deploySmartVault(_getSpecification());
    }

    function test_deploySmartVault_shouldIntegrateSmartVault() public {
        // - set actions
        vm.expectCall(address(actionManager), abi.encodeWithSelector(IActionManager.setActions.selector));
        // - set guards
        vm.expectCall(address(guardManager), abi.encodeWithSelector(IGuardManager.setGuards.selector));
        // - register smart vault
        vm.expectCall(
            address(smartVaultManager), abi.encodeWithSelector(ISmartVaultManager.registerSmartVault.selector)
        );

        factory.deploySmartVault(_getSpecification());
    }

    function test_deploySmartVault_shouldEmitSmartVaultDeployed() public {
        vm.expectEmit(false, false, false, false);
        emit SmartVaultDeployed(address(0x0), address(0x0));

        factory.deploySmartVault(_getSpecification());
    }

    /* ========== deploySmartVaultDeterministically ========== */

    function test_deploySmartVaultDeterministically_shouldDeploySmartVault() public {
        ISmartVault mySmartVault = factory.deploySmartVaultDeterministically(_getSpecification(), bytes32(uint256(123)));

        assertEq(mySmartVault.vaultName(), "MySmartVault");
    }

    function test_deploySmartVaultDeterministically_shouldValidateSpecification() public {
        // - validate asset group
        vm.expectCall(
            address(assetGroupRegistry), abi.encodeWithSelector(IAssetGroupRegistry.validateAssetGroup.selector)
        );

        factory.deploySmartVaultDeterministically(_getSpecification(), bytes32(uint256(123)));
    }

    function test_deploySmartVaultDeterministically_shouldIntegrateSmartVault() public {
        // - set actions
        vm.expectCall(address(actionManager), abi.encodeWithSelector(IActionManager.setActions.selector));
        // - set guards
        vm.expectCall(address(guardManager), abi.encodeWithSelector(IGuardManager.setGuards.selector));
        // - register smart vault
        vm.expectCall(
            address(smartVaultManager), abi.encodeWithSelector(ISmartVaultManager.registerSmartVault.selector)
        );

        factory.deploySmartVaultDeterministically(_getSpecification(), bytes32(uint256(123)));
    }

    function test_deploySmartVaultDeterministically_shouldEmitSmartVaultDeployed() public {
        vm.expectEmit(false, false, false, false);
        emit SmartVaultDeployed(address(0x0), address(0x0));

        factory.deploySmartVaultDeterministically(_getSpecification(), bytes32(uint256(123)));
    }

    /* ========== predictDeterministicAddress ========== */

    function test_predictDeterministicAddress_shouldPredictAddress() public {
        SmartVaultSpecification memory specification = _getSpecification();
        bytes32 salt = bytes32(uint256(123));

        address predictedAddress = factory.predictDeterministicAddress(specification, salt);

        ISmartVault mySmartVault = factory.deploySmartVaultDeterministically(specification, salt);

        assertEq(predictedAddress, address(mySmartVault));
    }

    function test_predictDeterministicAddress_predictedAddressShouldDifferBasedOnSaltAndCreationData() public {
        SmartVaultSpecification memory specification = _getSpecification();
        bytes32 salt = bytes32(uint256(123));

        address predictedAddress1 = factory.predictDeterministicAddress(specification, salt);

        specification.smartVaultName = "AnotherSmartVault";
        address predictedAddress2 = factory.predictDeterministicAddress(specification, salt);

        salt = bytes32(uint256(321));
        address predictedAddress3 = factory.predictDeterministicAddress(specification, salt);

        assertFalse(predictedAddress1 == predictedAddress2);
        assertFalse(predictedAddress2 == predictedAddress3);
    }

    /* ========== proxy ========== */

    function test_proxy_eachSmartVaultShouldHaveItsOwnState() public {
        SmartVaultSpecification memory specification = _getSpecification();

        specification.smartVaultName = "SmartVault1";
        ISmartVault smartVault1 = factory.deploySmartVault(specification);

        specification.smartVaultName = "SmartVault2";
        ISmartVault smartVault2 = factory.deploySmartVault(specification);

        specification.smartVaultName = "SmartVault3";
        ISmartVault smartVault3 = factory.deploySmartVaultDeterministically(specification, bytes32(uint256(123)));

        specification.smartVaultName = "SmartVault4";
        ISmartVault smartVault4 = factory.deploySmartVaultDeterministically(specification, bytes32(uint256(321)));

        assertEq(smartVault1.vaultName(), "SmartVault1");
        assertEq(smartVault2.vaultName(), "SmartVault2");
        assertEq(smartVault3.vaultName(), "SmartVault3");
        assertEq(smartVault4.vaultName(), "SmartVault4");
    }

    function test_upgradeTo_shouldUpgradeAllExistingVaults() public {
        SmartVaultSpecification memory specification = _getSpecification();

        specification.smartVaultName = "SmartVault1";
        ISmartVault smartVault1 = factory.deploySmartVault(specification);

        specification.smartVaultName = "SmartVault2";
        ISmartVault smartVault2 = factory.deploySmartVault(specification);

        specification.smartVaultName = "SmartVault3";
        ISmartVault smartVault3 = factory.deploySmartVaultDeterministically(specification, bytes32(uint256(123)));

        specification.smartVaultName = "SmartVault4";
        ISmartVault smartVault4 = factory.deploySmartVaultDeterministically(specification, bytes32(uint256(321)));

        assertEq(SmartVaultVariant(address(smartVault1)).getTestValue(), 1);
        assertEq(SmartVaultVariant(address(smartVault2)).getTestValue(), 1);
        assertEq(SmartVaultVariant(address(smartVault3)).getTestValue(), 1);
        assertEq(SmartVaultVariant(address(smartVault4)).getTestValue(), 1);

        address implementation2 = address(new SmartVaultVariant(accessControl, guardManager, 2));
        factory.upgradeTo(implementation2);

        assertEq(SmartVaultVariant(address(smartVault1)).getTestValue(), 2);
        assertEq(SmartVaultVariant(address(smartVault2)).getTestValue(), 2);
        assertEq(SmartVaultVariant(address(smartVault3)).getTestValue(), 2);
        assertEq(SmartVaultVariant(address(smartVault4)).getTestValue(), 2);
    }

    function test_upgradeTo_afterUpgradeShouldDeployAccordingToNewImplementation() public {
        SmartVaultSpecification memory specification = _getSpecification();

        address implementation2 = address(new SmartVaultVariant(accessControl, guardManager, 2));
        factory.upgradeTo(implementation2);

        specification.smartVaultName = "SmartVault1";
        ISmartVault smartVault1 = factory.deploySmartVault(specification);

        specification.smartVaultName = "SmartVault2";
        ISmartVault smartVault2 = factory.deploySmartVaultDeterministically(specification, bytes32(uint256(123)));

        assertEq(SmartVaultVariant(address(smartVault1)).getTestValue(), 2);
        assertEq(SmartVaultVariant(address(smartVault2)).getTestValue(), 2);
    }

    /* ========== HELPERS ========== */

    function _getSpecification() private pure returns (SmartVaultSpecification memory) {
        return SmartVaultSpecification({
            smartVaultName: "MySmartVault",
            assetGroupId: 1,
            strategies: Arrays.toArray(address(0x6)),
            strategyAllocation: new uint256[](0),
            riskTolerance: 4,
            riskProvider: address(0x7),
            allocationProvider: address(0xabc),
            actions: new IAction[](0),
            actionRequestTypes: new RequestType[](0),
            guards: new GuardDefinition[][](0),
            guardRequestTypes: new RequestType[](0),
            managementFeePct: 0,
            depositFeePct: 0,
            allowRedeemFor: false
        });
    }
}
