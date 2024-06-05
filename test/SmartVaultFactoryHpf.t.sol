// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "@openzeppelin-upgradeable/access/IAccessControlUpgradeable.sol";
import "../src/interfaces/IAction.sol";
import "../src/interfaces/IAssetGroupRegistry.sol";
import "../src/interfaces/IGuardManager.sol";
import "../src/interfaces/RequestType.sol";
import "../src/interfaces/ISmartVault.sol";
import "../src/interfaces/ISmartVaultManager.sol";
import "../src/interfaces/ISpoolAccessControl.sol";
import "../src/interfaces/IStrategy.sol";
import "../src/SmartVault.sol";
import "../src/SmartVaultBeneficiary.sol";
import "../src/SmartVaultFactoryHpf.sol";
import "./libraries/Arrays.sol";
import "../src/managers/RiskManager.sol";
import "../src/access/SpoolAccessControl.sol";

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

contract SmartVaultFactoryHpfTest is Test {
    using uint16a16Lib for uint16a16;

    event SmartVaultDeployed(address indexed smartVault, address indexed deployer);
    event BaseURIChanged(string baseURI);

    address strategy = address(0x1);
    address anotherStrategy = address(0x11);
    address riskProvider = address(0x7);
    address allocProviderAddress = address(0x8);

    SmartVaultFactoryHpf private factory;

    SpoolAccessControl accessControl;
    IActionManager actionManager;
    IGuardManager guardManager;
    ISmartVaultManager smartVaultManager;
    IAssetGroupRegistry assetGroupRegistry;
    IRiskManager riskManager;
    IStrategyRegistry strategyRegistry;
    IAllocationProvider allocProvider;

    function setUp() public {
        vm.mockCall(strategy, abi.encodeWithSelector(IStrategy.assetGroupId.selector), abi.encode(1));
        vm.mockCall(anotherStrategy, abi.encodeWithSelector(IStrategy.assetGroupId.selector), abi.encode(1));

        accessControl = new SpoolAccessControl();
        accessControl.initialize();

        actionManager = IActionManager(address(0x2));
        vm.mockCall(address(actionManager), abi.encodeWithSelector(IActionManager.setActions.selector), abi.encode(0));

        guardManager = IGuardManager(address(0x3));
        vm.mockCall(address(guardManager), abi.encodeWithSelector(IGuardManager.setGuards.selector), abi.encode(0));

        smartVaultManager = ISmartVaultManager(address(0x4));
        vm.mockCall(
            address(smartVaultManager),
            abi.encodeWithSelector(ISmartVaultRegistry.registerSmartVault.selector),
            abi.encode(0)
        );

        assetGroupRegistry = IAssetGroupRegistry(address(0x5));
        vm.mockCall(
            address(assetGroupRegistry),
            abi.encodeWithSelector(IAssetGroupRegistry.validateAssetGroup.selector),
            abi.encode(0)
        );

        strategyRegistry = IStrategyRegistry(address(0x6));
        vm.mockCall(
            address(strategyRegistry),
            abi.encodeWithSelector(IStrategyRegistry.strategyAPYs.selector),
            abi.encode(new int256[](0))
        );

        allocProvider = IAllocationProvider(allocProviderAddress);
        vm.mockCall(
            address(allocProvider),
            abi.encodeWithSelector(IAllocationProvider.calculateAllocation.selector),
            abi.encode(Arrays.toArray(FULL_PERCENT / 2, FULL_PERCENT / 2))
        );

        riskManager = new RiskManager(accessControl, strategyRegistry, address(0xabc));
        address implementation1 = address(new SmartVaultVariant(accessControl, guardManager, 1));

        factory = new SmartVaultFactoryHpf(
            implementation1,
            accessControl,
            actionManager,
            guardManager,
            smartVaultManager,
            assetGroupRegistry,
            riskManager
        );

        accessControl.grantRole(ROLE_SMART_VAULT_INTEGRATOR, address(factory));
        accessControl.grantRole(ADMIN_ROLE_STRATEGY, address(this));
        accessControl.grantRole(ROLE_STRATEGY, strategy);
        accessControl.grantRole(ROLE_STRATEGY, anotherStrategy);
        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
        accessControl.grantRole(ROLE_ALLOCATION_PROVIDER, allocProviderAddress);
        accessControl.grantRole(ROLE_HPF_SMART_VAULT_DEPLOYER, address(this));

        address[] memory strategies = Arrays.toArray(strategy, anotherStrategy);
        uint8[] memory riskScores = new uint8[](2);
        riskScores[0] = 1;
        riskScores[1] = 1;
        vm.prank(riskProvider);
        riskManager.setRiskScores(riskScores, strategies);
    }

    /* ========== deploySmartVault ========== */

    function test_grantSmartVaultOwnership_revertMissingRole() public {
        address bob = address(0xa);
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SMART_VAULT_INTEGRATOR, bob));
        accessControl.grantSmartVaultOwnership(address(0xa), bob);
        vm.stopPrank();
    }

    function test_deploySmartVault_shouldDeploySmartVault() public {
        SmartVaultSpecification memory specification = _getSpecification();

        // - smart vault with dynamic allocation
        {
            ISmartVault mySmartVault = factory.deploySmartVault(specification);

            assertEq(mySmartVault.vaultName(), "MySmartVault");
        }

        // - smart vault with static allocation
        {
            address allocationProviderBefore = specification.allocationProvider;
            address riskProviderBefore = specification.riskProvider;
            int8 riskToleranceBefore = specification.riskTolerance;
            uint16a16 strategyAllocationBefore = specification.strategyAllocation;

            specification.allocationProvider = address(0);
            specification.riskProvider = address(0);
            specification.riskTolerance = 0;
            specification.strategyAllocation = Arrays.toUint16a16(FULL_PERCENT / 2, FULL_PERCENT / 2);

            ISmartVault mySmartVault = factory.deploySmartVault(specification);

            assertEq(mySmartVault.vaultName(), "MySmartVault");

            specification.allocationProvider = allocationProviderBefore;
            specification.riskProvider = riskProviderBefore;
            specification.riskTolerance = riskToleranceBefore;
            specification.strategyAllocation = strategyAllocationBefore;
        }
    }

    function test_deploySmartVault_shouldValidateSpecification() public {
        SmartVaultSpecification memory specification = _getSpecification();

        // - validate asset group
        vm.expectCall(
            address(assetGroupRegistry), abi.encodeWithSelector(IAssetGroupRegistry.validateAssetGroup.selector)
        );
        factory.deploySmartVault(specification);

        // - validate number of strategies
        {
            address[] memory before = specification.strategies;

            specification.strategies = new address[](0);
            vm.expectRevert(SmartVaultRegistrationNoStrategies.selector);
            factory.deploySmartVault(specification);

            specification.strategies = new address[](STRATEGY_COUNT_CAP + 1);
            vm.expectRevert(StrategyCapExceeded.selector);
            factory.deploySmartVault(specification);

            specification.strategies = before;
        }

        // - validate strategy duplicates
        {
            address[] memory before = specification.strategies;
            specification.strategies = Arrays.toArray(specification.strategies[0], specification.strategies[0]);
            vm.expectRevert(StrategiesNotUnique.selector);
            factory.deploySmartVault(specification);

            specification.strategies = before;
        }

        // - validate strategy validity
        {
            vm.mockCall(
                address(accessControl),
                abi.encodeWithSelector(IAccessControlUpgradeable.hasRole.selector, ROLE_STRATEGY),
                abi.encode(false)
            );

            vm.expectRevert(abi.encodeWithSelector(InvalidStrategy.selector, strategy));
            factory.deploySmartVault(specification);

            vm.mockCall(
                address(accessControl),
                abi.encodeWithSelector(IAccessControlUpgradeable.hasRole.selector, ROLE_STRATEGY),
                abi.encode(true)
            );
        }

        // - validate strategies asset group
        {
            vm.mockCall(strategy, abi.encodeWithSelector(IStrategy.assetGroupId.selector), abi.encode(2));

            vm.expectRevert(NotSameAssetGroup.selector);
            factory.deploySmartVault(specification);

            vm.mockCall(strategy, abi.encodeWithSelector(IStrategy.assetGroupId.selector), abi.encode(1));
        }

        // - validate fees
        {
            uint16 before = specification.managementFeePct;

            specification.managementFeePct = uint16(MANAGEMENT_FEE_MAX) + 1;
            vm.expectRevert(abi.encodeWithSelector(ManagementFeeTooLarge.selector, specification.managementFeePct));
            factory.deploySmartVault(specification);

            specification.managementFeePct = before;

            before = specification.depositFeePct;

            specification.depositFeePct = uint16(DEPOSIT_FEE_MAX) + 1;
            vm.expectRevert(abi.encodeWithSelector(DepositFeeTooLarge.selector, specification.depositFeePct));
            factory.deploySmartVault(specification);

            specification.depositFeePct = before;

            before = specification.performanceFeePct;

            specification.performanceFeePct = uint16(SV_PERFORMANCE_FEE_HIGH_MAX) + 1;
            vm.expectRevert(abi.encodeWithSelector(PerformanceFeeTooLarge.selector, specification.performanceFeePct));
            factory.deploySmartVault(specification);

            specification.performanceFeePct = before;
        }

        // - validate static allocations length
        {
            address allocationProviderBefore = specification.allocationProvider;
            address riskProviderBefore = specification.riskProvider;
            int8 riskToleranceBefore = specification.riskTolerance;
            uint16a16 strategyAllocationBefore = specification.strategyAllocation;

            specification.allocationProvider = address(0);
            specification.riskProvider = address(0);
            specification.riskTolerance = 0;
            specification.strategyAllocation = Arrays.toUint16a16(FULL_PERCENT, 0);

            vm.expectRevert(InvalidStrategyAllocationsLength.selector);
            factory.deploySmartVault(specification);

            specification.allocationProvider = allocationProviderBefore;
            specification.riskProvider = riskProviderBefore;
            specification.riskTolerance = riskToleranceBefore;
            specification.strategyAllocation = strategyAllocationBefore;
        }

        // - validate static allocation sum
        {
            address allocationProviderBefore = specification.allocationProvider;
            address riskProviderBefore = specification.riskProvider;
            int8 riskToleranceBefore = specification.riskTolerance;
            uint16a16 strategyAllocationBefore = specification.strategyAllocation;

            specification.allocationProvider = address(0);
            specification.riskProvider = address(0);
            specification.riskTolerance = 0;
            specification.strategyAllocation = Arrays.toUint16a16(100, 100);

            vm.expectRevert(InvalidStaticAllocation.selector);
            factory.deploySmartVault(specification);

            specification.allocationProvider = allocationProviderBefore;
            specification.riskProvider = riskProviderBefore;
            specification.riskTolerance = riskToleranceBefore;
            specification.strategyAllocation = strategyAllocationBefore;
        }

        // - validate that static allocation and allocation provider are not both set
        {
            address riskProviderBefore = specification.riskProvider;
            int8 riskToleranceBefore = specification.riskTolerance;
            uint16a16 strategyAllocationBefore = specification.strategyAllocation;

            specification.riskProvider = address(0);
            specification.riskTolerance = 0;
            specification.strategyAllocation = Arrays.toUint16a16(FULL_PERCENT / 2, FULL_PERCENT / 2);

            vm.expectRevert(StaticAllocationAndAllocationProviderSet.selector);
            factory.deploySmartVault(specification);

            specification.riskProvider = riskProviderBefore;
            specification.riskTolerance = riskToleranceBefore;
            specification.strategyAllocation = strategyAllocationBefore;
        }

        // - validate that static allocation and risk provider are not both set
        {
            address allocationProviderBefore = specification.allocationProvider;
            int8 riskToleranceBefore = specification.riskTolerance;
            uint16a16 strategyAllocationBefore = specification.strategyAllocation;

            specification.allocationProvider = address(0);
            specification.riskTolerance = 0;
            specification.strategyAllocation = Arrays.toUint16a16(FULL_PERCENT / 2, FULL_PERCENT / 2);

            vm.expectRevert(StaticAllocationAndRiskProviderSet.selector);
            factory.deploySmartVault(specification);

            specification.allocationProvider = allocationProviderBefore;
            specification.riskTolerance = riskToleranceBefore;
            specification.strategyAllocation = strategyAllocationBefore;
        }

        // - validate that static allocation and risk tolerance are not both set
        {
            address allocationProviderBefore = specification.allocationProvider;
            address riskProviderBefore = specification.riskProvider;
            uint16a16 strategyAllocationBefore = specification.strategyAllocation;

            specification.allocationProvider = address(0);
            specification.riskProvider = address(0);
            specification.strategyAllocation = Arrays.toUint16a16(FULL_PERCENT / 2, FULL_PERCENT / 2);

            vm.expectRevert(StaticAllocationAndRiskToleranceSet.selector);
            factory.deploySmartVault(specification);

            specification.allocationProvider = allocationProviderBefore;
            specification.riskProvider = riskProviderBefore;
            specification.strategyAllocation = strategyAllocationBefore;
        }

        // - enforce static allocation is set when only one strategy in vault
        {
            address[] memory strategiesBefore = specification.strategies;

            specification.strategies = Arrays.toArray(strategy);

            vm.expectRevert(SingleStrategyDynamicAllocation.selector);
            factory.deploySmartVault(specification);

            specification.strategies = strategiesBefore;
        }
    }

    function test_deploySmartVault_shouldDeploySmartVaultWithHighPerformanceFee() public {
        SmartVaultSpecification memory specification = _getSpecification();
        specification.performanceFeePct = uint16(SV_PERFORMANCE_FEE_HIGH_MAX);

        ISmartVault mySmartVault = factory.deploySmartVault(specification);

        assertEq(mySmartVault.vaultName(), "MySmartVault");
    }

    function test_deploySmartVault_shouldIntegrateSmartVault() public {
        // - set actions
        vm.expectCall(address(actionManager), abi.encodeWithSelector(IActionManager.setActions.selector));
        // - set guards
        vm.expectCall(address(guardManager), abi.encodeWithSelector(IGuardManager.setGuards.selector));
        // - register smart vault
        vm.expectCall(
            address(smartVaultManager), abi.encodeWithSelector(ISmartVaultRegistry.registerSmartVault.selector)
        );

        factory.deploySmartVault(_getSpecification());
    }

    function test_deploySmartVault_shouldSetOwnerAndAdmin() public {
        ISmartVault smartVault = factory.deploySmartVault(_getSpecification());

        assertEq(accessControl.smartVaultOwner(address(smartVault)), address(this));
        assertTrue(accessControl.hasSmartVaultRole(address(smartVault), ROLE_SMART_VAULT_ADMIN, address(this)));
    }

    function test_deploySmartVault_shouldEmitSmartVaultDeployed() public {
        SmartVaultSpecification memory specification = _getSpecification();

        vm.expectEmit(false, false, false, false);
        emit SmartVaultDeployed(address(0x0), address(0x0));

        factory.deploySmartVault(specification);
    }

    function test_deploySmartVault_shouldNotDeployWhenDeployerIsNotAuthorized() public {
        SmartVaultSpecification memory specification = _getSpecification();

        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_HPF_SMART_VAULT_DEPLOYER, address(0xa)));
        vm.startPrank(address(0xa));
        factory.deploySmartVault(specification);
        vm.stopPrank();
    }

    function test_deploySmartVault_shouldReturnCorrectURI() public {
        SmartVaultSpecification memory specification = _getSpecification();

        ISmartVault vault = factory.deploySmartVault(specification);
        string memory uri = vault.uri(5123);
        assertEq(uri, "https://token-cdn-domain/5123.json");
    }

    function test_deploySmartVault_setBaseURI_shouldRevertMissingRole() public {
        SmartVaultSpecification memory specification = _getSpecification();

        ISmartVault vault = factory.deploySmartVault(specification);

        vm.startPrank(address(0xa));
        vm.expectRevert(
            abi.encodeWithSelector(
                MissingRole.selector, keccak256(abi.encode(address(vault), ROLE_SMART_VAULT_ADMIN)), address(0xa)
            )
        );
        vault.setBaseURI("https://token-cdn-domain/new/");
        vm.stopPrank();
    }

    function test_deploySmartVault__setBaseURI_ok() public {
        SmartVaultSpecification memory specification = _getSpecification();

        ISmartVault vault = factory.deploySmartVault(specification);

        vm.expectEmit(true, true, true, true, address(vault));
        emit BaseURIChanged("https://token-cdn-domain/new/");
        vault.setBaseURI("https://token-cdn-domain/new/");

        string memory uri = vault.uri(5123);
        assertEq(uri, "https://token-cdn-domain/new/5123.json");
    }

    /* ========== deploySmartVaultDeterministically ========== */

    function test_deploySmartVaultDeterministically_shouldDeploySmartVault() public {
        ISmartVault mySmartVault = factory.deploySmartVaultDeterministically(_getSpecification(), bytes32(uint256(123)));

        assertEq(mySmartVault.vaultName(), "MySmartVault");
    }

    function test_deploySmartVaultDeterministically_shouldValidateSpecification() public {
        SmartVaultSpecification memory specification = _getSpecification();

        // - validate asset group
        vm.expectCall(
            address(assetGroupRegistry), abi.encodeWithSelector(IAssetGroupRegistry.validateAssetGroup.selector)
        );
        factory.deploySmartVaultDeterministically(specification, bytes32(uint256(123)));

        // - validate number of strategies
        {
            address[] memory before = specification.strategies;

            specification.strategies = new address[](0);
            vm.expectRevert(SmartVaultRegistrationNoStrategies.selector);
            factory.deploySmartVaultDeterministically(specification, bytes32(uint256(123)));

            specification.strategies = new address[](STRATEGY_COUNT_CAP + 1);
            vm.expectRevert(StrategyCapExceeded.selector);
            factory.deploySmartVaultDeterministically(specification, bytes32(uint256(123)));

            specification.strategies = before;
        }

        // - validate strategy validity
        {
            vm.mockCall(
                address(accessControl),
                abi.encodeWithSelector(IAccessControlUpgradeable.hasRole.selector, ROLE_STRATEGY),
                abi.encode(false)
            );

            vm.expectRevert(abi.encodeWithSelector(InvalidStrategy.selector, strategy));
            factory.deploySmartVaultDeterministically(specification, bytes32(uint256(123)));

            vm.mockCall(
                address(accessControl),
                abi.encodeWithSelector(IAccessControlUpgradeable.hasRole.selector, ROLE_STRATEGY),
                abi.encode(true)
            );
        }

        // - validate strategies asset group
        {
            vm.mockCall(strategy, abi.encodeWithSelector(IStrategy.assetGroupId.selector), abi.encode(2));

            vm.expectRevert(NotSameAssetGroup.selector);
            factory.deploySmartVaultDeterministically(specification, bytes32(uint256(123)));

            vm.mockCall(strategy, abi.encodeWithSelector(IStrategy.assetGroupId.selector), abi.encode(1));
        }

        // - validate fees
        {
            uint16 before = specification.managementFeePct;

            specification.managementFeePct = uint16(MANAGEMENT_FEE_MAX) + 1;
            vm.expectRevert(abi.encodeWithSelector(ManagementFeeTooLarge.selector, specification.managementFeePct));
            factory.deploySmartVaultDeterministically(specification, bytes32(uint256(123)));

            specification.managementFeePct = before;

            before = specification.depositFeePct;

            specification.depositFeePct = uint16(DEPOSIT_FEE_MAX) + 1;
            vm.expectRevert(abi.encodeWithSelector(DepositFeeTooLarge.selector, specification.depositFeePct));
            factory.deploySmartVaultDeterministically(specification, bytes32(uint256(123)));

            specification.depositFeePct = before;

            before = specification.performanceFeePct;

            specification.performanceFeePct = uint16(SV_PERFORMANCE_FEE_HIGH_MAX) + 1;
            vm.expectRevert(abi.encodeWithSelector(PerformanceFeeTooLarge.selector, specification.performanceFeePct));
            factory.deploySmartVault(specification);

            specification.performanceFeePct = before;
        }
    }

    function test_deploySmartVaultDeterministically_shouldDeploySmartVaultWithHighPerformanceFee() public {
        SmartVaultSpecification memory specification = _getSpecification();
        specification.performanceFeePct = uint16(SV_PERFORMANCE_FEE_HIGH_MAX);

        ISmartVault mySmartVault = factory.deploySmartVaultDeterministically(specification, bytes32(uint256(123)));

        assertEq(mySmartVault.vaultName(), "MySmartVault");
    }

    function test_deploySmartVaultDeterministically_shouldIntegrateSmartVault() public {
        // - set actions
        vm.expectCall(address(actionManager), abi.encodeWithSelector(IActionManager.setActions.selector));
        // - set guards
        vm.expectCall(address(guardManager), abi.encodeWithSelector(IGuardManager.setGuards.selector));
        // - register smart vault
        vm.expectCall(
            address(smartVaultManager), abi.encodeWithSelector(ISmartVaultRegistry.registerSmartVault.selector)
        );

        factory.deploySmartVaultDeterministically(_getSpecification(), bytes32(uint256(123)));
    }

    function test_deploySmartVaultDeterministically_shouldEmitSmartVaultDeployed() public {
        SmartVaultSpecification memory specification = _getSpecification();

        vm.expectEmit(false, false, false, false);
        emit SmartVaultDeployed(address(0x0), address(0x0));

        factory.deploySmartVaultDeterministically(specification, bytes32(uint256(123)));
    }

    function test_deploySmartVaultDeterministically_shouldNotDeployWhenDeployerIsNotAuthorized() public {
        SmartVaultSpecification memory specification = _getSpecification();

        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_HPF_SMART_VAULT_DEPLOYER, address(0xa)));
        vm.startPrank(address(0xa));
        factory.deploySmartVaultDeterministically(specification, bytes32(uint256(123)));
        vm.stopPrank();
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

    function _getSpecification() private view returns (SmartVaultSpecification memory) {
        return SmartVaultSpecification({
            smartVaultName: "MySmartVault",
            svtSymbol: "MSV",
            baseURI: "https://token-cdn-domain/",
            assetGroupId: 1,
            strategies: Arrays.toArray(strategy, anotherStrategy),
            strategyAllocation: uint16a16.wrap(0),
            riskTolerance: 4,
            riskProvider: riskProvider,
            allocationProvider: allocProviderAddress,
            actions: new IAction[](0),
            actionRequestTypes: new RequestType[](0),
            guards: new GuardDefinition[][](0),
            guardRequestTypes: new RequestType[](0),
            managementFeePct: 0,
            depositFeePct: 0,
            performanceFeePct: 0,
            allowRedeemFor: false
        });
    }
}
