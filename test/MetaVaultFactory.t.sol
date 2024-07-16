// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "../src/MetaVault.sol";
import "../src/MetaVaultFactory.sol";
import "../src/access/SpoolAccessControl.sol";
import "./mocks/MockToken.sol";

contract MetaVaultFactoryTest is Test {
    event MetaVaultDeployed(address indexed metaVault, address indexed deployer);

    MetaVault metaVault;
    MetaVaultFactory factory;
    SpoolAccessControl accessControl;
    IAssetGroupRegistry assetGroupRegistry;

    address tokenAllowed;
    address tokenForbidden;

    function setUp() public {
        tokenAllowed = address(new MockToken("allowed", "A"));
        tokenForbidden = address(new MockToken("forbidden", "F"));

        accessControl = new SpoolAccessControl();
        accessControl.initialize();

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

        address implementation =
            address(new MetaVault(ISmartVaultManager(address(0x4)), accessControl, assetGroupRegistry));

        factory = new MetaVaultFactory(implementation, accessControl, assetGroupRegistry);
    }

    function test_onlyDeployerRoleCanDeployMetaVault() external {
        assertFalse(accessControl.hasRole(ROLE_META_VAULT_DEPLOYER, address(this)));
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_META_VAULT_DEPLOYER, address(this)));
        factory.deployMetaVault(tokenAllowed, "test", "TST");

        accessControl.grantRole(ROLE_META_VAULT_DEPLOYER, address(this));

        assertTrue(accessControl.hasRole(ROLE_META_VAULT_DEPLOYER, address(this)));
        factory.deployMetaVault(tokenAllowed, "test", "TST");
    }

    function test_onlyDeployerRoleCanDeployMetaVaultDeterministically() external {
        assertFalse(accessControl.hasRole(ROLE_META_VAULT_DEPLOYER, address(this)));
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_META_VAULT_DEPLOYER, address(this)));
        factory.deployMetaVaultDeterministically(tokenAllowed, "test", "TST", keccak256("salt"));

        accessControl.grantRole(ROLE_META_VAULT_DEPLOYER, address(this));

        assertTrue(accessControl.hasRole(ROLE_META_VAULT_DEPLOYER, address(this)));
        factory.deployMetaVaultDeterministically(tokenAllowed, "test", "TST", keccak256("salt"));
    }

    function test_onlyValidAssetCanBeUsedForMetaVaultDeploy() external {
        accessControl.grantRole(ROLE_META_VAULT_DEPLOYER, address(this));

        vm.expectRevert(abi.encodeWithSelector(MetaVaultFactory.UnsupportedAsset.selector));
        factory.deployMetaVault(tokenForbidden, "test", "TST");

        factory.deployMetaVault(tokenAllowed, "test", "TST");
    }

    function test_onlyValidAssetCanBeUsedForMetaVaultDeployDeterministically() external {
        accessControl.grantRole(ROLE_META_VAULT_DEPLOYER, address(this));

        vm.expectRevert(abi.encodeWithSelector(MetaVaultFactory.UnsupportedAsset.selector));
        factory.deployMetaVaultDeterministically(tokenForbidden, "test", "TST", keccak256("salt"));

        factory.deployMetaVaultDeterministically(tokenAllowed, "test", "TST", keccak256("salt"));
    }

    function test_emitEventDeploy() external {
        accessControl.grantRole(ROLE_META_VAULT_DEPLOYER, address(this));

        vm.expectEmit(false, false, false, false);
        emit MetaVaultDeployed(address(0x0), address(0x0));
        factory.deployMetaVault(tokenAllowed, "test", "TST");
    }

    function test_emitEventDeployDeterministically() external {
        accessControl.grantRole(ROLE_META_VAULT_DEPLOYER, address(this));

        vm.expectEmit(false, false, false, false);
        emit MetaVaultDeployed(address(0x0), address(0x0));
        factory.deployMetaVaultDeterministically(tokenAllowed, "test", "TST", keccak256("salt"));
    }

    function test_predictDeterministicAddress() external {
        accessControl.grantRole(ROLE_META_VAULT_DEPLOYER, address(this));

        address predictedAddress = factory.predictDeterministicAddress(tokenAllowed, "test", "TST", keccak256("salt"));

        vm.expectEmit(false, false, false, false);
        emit MetaVaultDeployed(address(0x0), address(0x0));
        MetaVault vault = factory.deployMetaVaultDeterministically(tokenAllowed, "test", "TST", keccak256("salt"));
        assertEq(predictedAddress, address(vault));
    }

    function test_upgradeMetaVault() external {
        accessControl.grantRole(ROLE_META_VAULT_DEPLOYER, address(this));
        MetaVault vault = factory.deployMetaVault(tokenAllowed, "test", "TST");
        vm.expectRevert();
        MetaVault2(address(vault)).version();

        /// upgrade implementation of MetaVault
        factory.upgradeTo(address(new MetaVault2(ISmartVaultManager(address(0x4)), accessControl, assetGroupRegistry)));
        assertEq(MetaVault2(address(vault)).version(), 2);
    }
}

contract MetaVault2 is MetaVault {
    constructor(
        ISmartVaultManager smartVaultManager_,
        ISpoolAccessControl spoolAccessControl_,
        IAssetGroupRegistry assetGroupRegistry_
    ) MetaVault(smartVaultManager_, spoolAccessControl_, assetGroupRegistry_) {}

    function version() external pure returns (uint256) {
        return 2;
    }
}
