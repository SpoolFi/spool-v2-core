// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "@openzeppelin/token/ERC20/ERC20.sol";

import "../src/MetaVault.sol";
import "../src/MetaVaultFactory.sol";
import "../src/SmartVault.sol";
import "../src/access/SpoolAccessControl.sol";
import "../src/SpoolLens.sol";
import "./mocks/MockToken.sol";

contract MetaVaultFactoryTest is Test {
    event MetaVaultDeployed(address indexed metaVault, address indexed deployer);

    MetaVault metaVault;
    MetaVaultFactory factory;
    address[] vaults;
    uint256[] allocations;
    SpoolAccessControl accessControl;
    IAssetGroupRegistry assetGroupRegistry;
    ISpoolLens spoolLens;

    address tokenAllowed;
    address tokenForbidden;

    function setUp() public {
        tokenAllowed = address(new MockToken("allowed", "A"));
        tokenForbidden = address(new MockToken("forbidden", "F"));

        accessControl = new SpoolAccessControl();
        accessControl.initialize();

        spoolLens = ISpoolLens(address(0xa));

        SmartVault vault = SmartVault(address(0xa1));
        vm.mockCall(address(vault), abi.encodeWithSelector(ERC20.decimals.selector), abi.encode(18));

        vaults.push(address(vault));
        allocations.push(100_00);

        assetGroupRegistry = IAssetGroupRegistry(address(0x3));
        vm.mockCall(
            address(assetGroupRegistry),
            abi.encodeWithSelector(IAssetGroupRegistry.isTokenAllowed.selector, tokenAllowed),
            abi.encode(true)
        );
        vm.mockCall(
            address(assetGroupRegistry),
            abi.encodeWithSelector(IAssetGroupRegistry.isTokenAllowed.selector, tokenForbidden),
            abi.encode(false)
        );

        address[] memory tokens = new address[](1);
        tokens[0] = tokenAllowed;
        vm.mockCall(
            address(assetGroupRegistry),
            abi.encodeWithSelector(IAssetGroupRegistry.listAssetGroup.selector, 1),
            abi.encode(tokens)
        );

        ISmartVaultManager smartVaultManager = ISmartVaultManager(address(0x4));
        vm.mockCall(
            address(smartVaultManager),
            abi.encodeWithSelector(ISmartVaultManager.getSmartVaultFees.selector, address(vault)),
            abi.encode(SmartVaultFees({managementFeePct: 0, depositFeePct: 0, performanceFeePct: 80}))
        );
        vm.mockCall(
            address(smartVaultManager),
            abi.encodeWithSelector(ISmartVaultManager.assetGroupId.selector, address(vault)),
            abi.encode(1)
        );

        address implementation = address(new MetaVault(smartVaultManager, accessControl, assetGroupRegistry, spoolLens));

        factory = new MetaVaultFactory(implementation, accessControl, assetGroupRegistry);
    }

    function test_onlyDeployerRoleCanDeployMetaVault() external {
        assertFalse(accessControl.hasRole(ROLE_META_VAULT_DEPLOYER, address(this)));
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_META_VAULT_DEPLOYER, address(this)));
        factory.deployMetaVault(tokenAllowed, "test", "TST", new address[](0), new uint256[](0));

        accessControl.grantRole(ROLE_META_VAULT_DEPLOYER, address(this));

        assertTrue(accessControl.hasRole(ROLE_META_VAULT_DEPLOYER, address(this)));
        factory.deployMetaVault(tokenAllowed, "test", "TST", new address[](0), new uint256[](0));
        factory.deployMetaVault(tokenAllowed, "test", "TST", vaults, allocations);
    }

    function test_onlyDeployerRoleCanDeployMetaVaultDeterministically() external {
        assertFalse(accessControl.hasRole(ROLE_META_VAULT_DEPLOYER, address(this)));
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_META_VAULT_DEPLOYER, address(this)));
        factory.deployMetaVaultDeterministically(
            tokenAllowed, "test", "TST", keccak256("salt"), new address[](0), new uint256[](0)
        );

        accessControl.grantRole(ROLE_META_VAULT_DEPLOYER, address(this));

        assertTrue(accessControl.hasRole(ROLE_META_VAULT_DEPLOYER, address(this)));
        factory.deployMetaVaultDeterministically(
            tokenAllowed, "test", "TST", keccak256("salt"), new address[](0), new uint256[](0)
        );
        factory.deployMetaVaultDeterministically(tokenAllowed, "test", "TST", keccak256("salt"), vaults, allocations);
    }

    function test_onlyValidAssetCanBeUsedForMetaVaultDeploy() external {
        accessControl.grantRole(ROLE_META_VAULT_DEPLOYER, address(this));

        vm.expectRevert(abi.encodeWithSelector(MetaVaultFactory.UnsupportedAsset.selector));
        factory.deployMetaVault(tokenForbidden, "test", "TST", new address[](0), new uint256[](0));

        factory.deployMetaVault(tokenAllowed, "test", "TST", new address[](0), new uint256[](0));
        factory.deployMetaVault(tokenAllowed, "test", "TST", vaults, allocations);
    }

    function test_onlyValidAssetCanBeUsedForMetaVaultDeployDeterministically() external {
        accessControl.grantRole(ROLE_META_VAULT_DEPLOYER, address(this));

        vm.expectRevert(abi.encodeWithSelector(MetaVaultFactory.UnsupportedAsset.selector));
        factory.deployMetaVaultDeterministically(
            tokenForbidden, "test", "TST", keccak256("salt"), new address[](0), new uint256[](0)
        );

        factory.deployMetaVaultDeterministically(
            tokenAllowed, "test", "TST", keccak256("salt"), new address[](0), new uint256[](0)
        );
        factory.deployMetaVaultDeterministically(tokenAllowed, "test", "TST", keccak256("salt"), vaults, allocations);
    }

    function test_emitEventDeploy() external {
        accessControl.grantRole(ROLE_META_VAULT_DEPLOYER, address(this));

        vm.expectEmit(false, false, false, false);
        emit MetaVaultDeployed(address(0x0), address(0x0));
        factory.deployMetaVault(tokenAllowed, "test", "TST", new address[](0), new uint256[](0));
    }

    function test_emitEventDeployDeterministically() external {
        accessControl.grantRole(ROLE_META_VAULT_DEPLOYER, address(this));

        vm.expectEmit(false, false, false, false);
        emit MetaVaultDeployed(address(0x0), address(0x0));
        factory.deployMetaVaultDeterministically(
            tokenAllowed, "test", "TST", keccak256("salt"), new address[](0), new uint256[](0)
        );
    }

    function test_predictDeterministicAddress() external {
        accessControl.grantRole(ROLE_META_VAULT_DEPLOYER, address(this));

        address predictedAddress = factory.predictDeterministicAddress(
            tokenAllowed, "test", "TST", keccak256("salt"), new address[](0), new uint256[](0)
        );

        vm.expectEmit(false, false, false, false);
        emit MetaVaultDeployed(address(0x0), address(0x0));
        MetaVault vault = factory.deployMetaVaultDeterministically(
            tokenAllowed, "test", "TST", keccak256("salt"), new address[](0), new uint256[](0)
        );
        assertEq(predictedAddress, address(vault));
    }

    function test_upgradeMetaVault() external {
        accessControl.grantRole(ROLE_META_VAULT_DEPLOYER, address(this));
        MetaVault vault = factory.deployMetaVault(tokenAllowed, "test", "TST", new address[](0), new uint256[](0));
        vm.expectRevert();
        MetaVault2(address(vault)).version();

        /// upgrade implementation of MetaVault
        factory.upgradeTo(
            address(new MetaVault2(ISmartVaultManager(address(0x4)), accessControl, assetGroupRegistry, spoolLens))
        );
        assertEq(MetaVault2(address(vault)).version(), 2);
    }
}

contract MetaVault2 is MetaVault {
    constructor(
        ISmartVaultManager smartVaultManager_,
        ISpoolAccessControl spoolAccessControl_,
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolLens spoolLens
    ) MetaVault(smartVaultManager_, spoolAccessControl_, assetGroupRegistry_, spoolLens) {}

    function version() external pure returns (uint256) {
        return 2;
    }
}
