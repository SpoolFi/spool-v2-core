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
import "../src/SmartVaultBeneficiaryFactoryHpf.sol";
import "./libraries/Arrays.sol";
import "../src/managers/RiskManager.sol";
import "../src/access/SpoolAccessControl.sol";

contract SmartVaultBeneficiaryTest is Test {
    event SmartVaultDeployed(address indexed smartVault, address indexed deployer);
    event BaseURIChanged(string baseURI);

    address strategy = address(0x1);
    address anotherStrategy = address(0x11);
    address riskProvider = address(0x7);
    address allocProviderAddress = address(0x8);

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

    function test_mintVaultShares() external {
        address beneficiary = address(0x321);
        address smartVaultOwner = address(0x9876);

        address implementation = address(new SmartVaultBeneficiary(accessControl, guardManager));

        //cannot set fee more than 100%
        vm.expectRevert(abi.encodeWithSelector(ExceedMaxFeeBp.selector));
        new SmartVaultBeneficiaryFactoryHpf(
            implementation,
            accessControl,
            actionManager,
            guardManager,
            smartVaultManager,
            assetGroupRegistry,
            riskManager,
            beneficiary,
            101_00
        );
        // beneficiary cannot be zero address
        vm.expectRevert(abi.encodeWithSelector(ConfigurationAddressZero.selector));
        new SmartVaultBeneficiaryFactoryHpf(
            implementation,
            accessControl,
            actionManager,
            guardManager,
            smartVaultManager,
            assetGroupRegistry,
            riskManager,
            address(0),
            1_00
        );

        SmartVaultBeneficiaryFactoryHpf beneficiaryFactory = new SmartVaultBeneficiaryFactoryHpf(
            implementation,
            accessControl,
            actionManager,
            guardManager,
            smartVaultManager,
            assetGroupRegistry,
            riskManager,
            beneficiary,
            15_00
        );

        accessControl.grantRole(ROLE_SMART_VAULT_INTEGRATOR, address(beneficiaryFactory));
        accessControl.grantRole(ROLE_HPF_SMART_VAULT_DEPLOYER, smartVaultOwner);
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(smartVaultManager));

        SmartVaultSpecification memory specification = _getSpecification();

        vm.startPrank(smartVaultOwner);

        {
            specification.smartVaultName = "SmartVault1";
            SmartVaultBeneficiary smartVault =
                SmartVaultBeneficiary(address(beneficiaryFactory.deploySmartVault(specification)));

            // shares minted to INITIAL_LOCKED_SHARES_ADDRESS will not be shared with beneficiary
            {
                vm.startPrank(address(smartVaultManager));
                smartVault.mintVaultShares(INITIAL_LOCKED_SHARES_ADDRESS, 300_000);
                vm.stopPrank();
                assertEq(smartVault.balanceOf(INITIAL_LOCKED_SHARES_ADDRESS), 300_000);
            }

            // shares minted to smart vault will not be shared with beneficiary
            {
                vm.startPrank(address(smartVaultManager));
                smartVault.mintVaultShares(address(smartVault), 200_000);
                vm.stopPrank();
                assertEq(smartVault.balanceOf(address(smartVault)), 200_000);
            }

            // otherwise if shares are minted to smartVaultOwner beneficiary will get his share
            vm.startPrank(address(smartVaultManager));
            uint256 sharesToMint = 123456;
            smartVault.mintVaultShares(smartVaultOwner, sharesToMint);
            vm.stopPrank();
            uint256 smartVaultOwnerBalance = smartVault.balanceOf(smartVaultOwner);
            uint256 beneficiaryBalance = smartVault.balanceOf(beneficiary);

            uint256 feeInBp = smartVault.feeInBp();
            assertEq(smartVaultOwnerBalance + beneficiaryBalance, sharesToMint);
            assertApproxEqAbs(sharesToMint * feeInBp / 100_00, beneficiaryBalance, 1);
            assertApproxEqAbs(sharesToMint, smartVaultOwnerBalance * 100_00 / (100_00 - feeInBp), 1);
        }
    }

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
