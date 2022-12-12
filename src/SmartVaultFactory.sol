// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {BeaconProxy} from "@openzeppelin/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/proxy/beacon/UpgradeableBeacon.sol";
import {IActionManager, IAction} from "./interfaces/IAction.sol";
import {IAssetGroupRegistry} from "./interfaces/IAssetGroupRegistry.sol";
import {IGuardManager, GuardDefinition} from "./interfaces/IGuardManager.sol";
import {ISmartVault} from "./interfaces/ISmartVault.sol";
import {ISmartVaultManager, SmartVaultRegistrationForm} from "./interfaces/ISmartVaultManager.sol";
import {RequestType} from "./interfaces/RequestType.sol";
import {ISpoolAccessControl, SpoolAccessRoles} from "./access/SpoolAccessControl.sol";
import {SmartVault} from "./SmartVault.sol";

struct SmartVaultSpecification {
    uint256 assetGroupId;
    string smartVaultName;
    IAction[] actions;
    RequestType[] actionRequestTypes;
    GuardDefinition[][] guards;
    RequestType[] guardRequestTypes;
    address[] strategies;
    uint256[] strategyAllocations;
    address riskProvider;
}

/**
 * @dev Requires roles:
 * - ADMIN_ROLE_SMART_VAULT
 * - ROLE_SMART_VAULT_INTEGRATOR
 */
contract SmartVaultFactory is UpgradeableBeacon, SpoolAccessRoles {
    ISpoolAccessControl immutable _accessControl;
    IActionManager immutable _actionManager;
    IGuardManager immutable _guardManager;
    ISmartVaultManager immutable _smartVaultManager;
    IAssetGroupRegistry immutable _assetGroupRegistry;

    constructor(
        address implementation,
        ISpoolAccessControl accessControl_,
        IActionManager actionManager_,
        IGuardManager guardManager_,
        ISmartVaultManager smartVaultManager_,
        IAssetGroupRegistry assetGroupRegistry_
    ) UpgradeableBeacon(implementation) {
        _accessControl = accessControl_;
        _actionManager = actionManager_;
        _guardManager = guardManager_;
        _smartVaultManager = smartVaultManager_;
        _assetGroupRegistry = assetGroupRegistry_;
    }

    // check asset group id
    function deploySmartVault(SmartVaultSpecification calldata specification) external returns (ISmartVault) {
        _assetGroupRegistry.validateAssetGroup(specification.assetGroupId);

        address smartVaultAddress = address(
            new BeaconProxy(
                address(this),
                abi.encodeWithSignature(
                    "initialize(string,uint256)",
                    specification.smartVaultName,
                    specification.assetGroupId
                )
            )
        );

        _accessControl.grantRole(ROLE_SMART_VAULT, smartVaultAddress);
        _actionManager.setActions(smartVaultAddress, specification.actions, specification.actionRequestTypes);
        _guardManager.setGuards(smartVaultAddress, specification.guards, specification.guardRequestTypes);

        _smartVaultManager.registerSmartVault(
            smartVaultAddress,
            SmartVaultRegistrationForm({
                assetGroupId: specification.assetGroupId,
                strategies: specification.strategies,
                strategyAllocations: specification.strategyAllocations,
                riskProvider: specification.riskProvider
            })
        );

        return ISmartVault(smartVaultAddress);
    }
}
