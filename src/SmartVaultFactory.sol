// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {BeaconProxy} from "@openzeppelin/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/proxy/beacon/UpgradeableBeacon.sol";
import {IActionManager, IAction} from "./interfaces/IAction.sol";
import {IAssetGroupRegistry} from "./interfaces/IAssetGroupRegistry.sol";
import {IGuardManager, GuardDefinition} from "./interfaces/IGuardManager.sol";
import {ISmartVault} from "./interfaces/ISmartVault.sol";
import {ISmartVaultManager, SmartVaultRegistrationForm} from "./interfaces/ISmartVaultManager.sol";
import {RequestType} from "./interfaces/RequestType.sol";
import {ISpoolAccessControl} from "./access/SpoolAccessControl.sol";
import {ROLE_SMART_VAULT} from "./access/Roles.sol";
import {SmartVault} from "./SmartVault.sol";

/* ========== STRUCTS ========== */

/**
 * @notice Specification for smart vault deployment.
 * @custom:member smartVaultName Name of the smart vault.
 * @custom:member assetGroupId ID of the asset group.
 * @custom:member strategies Strategies used by the smart vault.
 * @custom:member riskAppetite Risk appetite of the smart vault.
 * @custom:member riskProvider Risk provider used by the smart vault.
 * @custom:member actions Actions to register for the smart vault.
 * @custom:member actionRequestTypes Request types for actions.
 * @custom:member guards Guards to register for the smart vault.
 * @custom:member guardRequestTypes Request types for the smart vault.
 */
struct SmartVaultSpecification {
    string smartVaultName;
    uint256 assetGroupId;
    address[] strategies;
    uint256 riskAppetite;
    address riskProvider;
    IAction[] actions;
    RequestType[] actionRequestTypes;
    GuardDefinition[][] guards;
    RequestType[] guardRequestTypes;
}

/* ========== CONTRACTS ========== */

/**
 * @dev Requires roles:
 * - ADMIN_ROLE_SMART_VAULT
 * - ROLE_SMART_VAULT_INTEGRATOR
 */
contract SmartVaultFactory is UpgradeableBeacon {
    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when a new smart vault is deployed.
     * @param smartVault Address of the newly deployed smart vault.
     * @param deployer Address of the deployer.
     */
    event SmartVaultDeployed(address indexed smartVault, address indexed deployer);

    /* ========== CONSTANTS ========== */

    /**
     * @notice Spool access control contract.
     */
    ISpoolAccessControl immutable _accessControl;

    /**
     * @notice Action manager contract.
     */
    IActionManager immutable _actionManager;

    /**
     * @notice Guard manager contract.
     */
    IGuardManager immutable _guardManager;

    /**
     * @notice Smart vault manager contract.
     */
    ISmartVaultManager immutable _smartVaultManager;

    /**
     * @notice Asset group registry contract.
     */
    IAssetGroupRegistry immutable _assetGroupRegistry;

    /* ========== CONSTRUCTOR ========== */

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

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Deploys a new smart vault into the Spool ecosystem.
     * @param specification Specifications for the new smart vault.
     * @return smartVault Deployed smart vault.
     */
    function deploySmartVault(SmartVaultSpecification calldata specification) external returns (ISmartVault) {
        _validateSpecification(specification);

        address smartVaultAddress = address(
            new BeaconProxy(
                address(this),
                _encodeInitializationCalldata(specification)
            )
        );

        _integrateSmartVault(smartVaultAddress, specification);

        emit SmartVaultDeployed(smartVaultAddress, msg.sender);

        return ISmartVault(smartVaultAddress);
    }

    /**
     * @notice Deploys a new smart vault to a deterministic address.
     * @param specification Specifications for the new smart vault.
     * @param salt Salt for address determination.
     * @return smartVault Deployed smart vault.
     */
    function deploySmartVaultDeterministically(SmartVaultSpecification calldata specification, bytes32 salt)
        external
        returns (ISmartVault)
    {
        _validateSpecification(specification);

        address smartVaultAddress = address(
            new BeaconProxy{salt: salt}(
                address(this),
                _encodeInitializationCalldata(specification)
            )
        );

        _integrateSmartVault(smartVaultAddress, specification);

        emit SmartVaultDeployed(smartVaultAddress, msg.sender);

        return ISmartVault(smartVaultAddress);
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Predicts deployment address deterministically deployed smart vault.
     * @param specification Specifications for the new smart vault.
     * @param salt Salt for address determination.
     * @return predictedAddress Predicted address.
     */
    function predictDeterministicAddress(SmartVaultSpecification calldata specification, bytes32 salt)
        external
        view
        returns (address)
    {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(
                                abi.encodePacked(
                                    type(BeaconProxy).creationCode,
                                    abi.encode(address(this), _encodeInitializationCalldata(specification))
                                )
                            )
                        )
                    )
                )
            )
        );
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice Validates smart vault specification.
     * @param specification Specifications for the new smart vault.
     */
    function _validateSpecification(SmartVaultSpecification calldata specification) private view {
        _assetGroupRegistry.validateAssetGroup(specification.assetGroupId);
    }

    /**
     * @notice Encodes calldata for smart vault initialization.
     * @param specification Specifications for the new smart vault.
     * @return initializationCalldata Enoded initialization calldata.
     */
    function _encodeInitializationCalldata(SmartVaultSpecification calldata specification)
        private
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "initialize(string,uint256)", specification.smartVaultName, specification.assetGroupId
        );
    }

    /**
     * @notice Integrates newly created smart vault into the Spool ecosystem.
     * @param smartVaultAddress Address of created smart vault.
     * @param specification Specifications for the new smart vault.
     */
    function _integrateSmartVault(address smartVaultAddress, SmartVaultSpecification calldata specification) private {
        _accessControl.grantRole(ROLE_SMART_VAULT, smartVaultAddress);
        _actionManager.setActions(smartVaultAddress, specification.actions, specification.actionRequestTypes);
        _guardManager.setGuards(smartVaultAddress, specification.guards, specification.guardRequestTypes);

        _smartVaultManager.registerSmartVault(
            smartVaultAddress,
            SmartVaultRegistrationForm({
                assetGroupId: specification.assetGroupId,
                strategies: specification.strategies,
                riskAppetite: specification.riskAppetite,
                riskProvider: specification.riskProvider
            })
        );
    }
}
