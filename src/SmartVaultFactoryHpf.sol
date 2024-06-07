// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/proxy/beacon/UpgradeableBeacon.sol";
import "./interfaces/IAction.sol";
import "./interfaces/IAssetGroupRegistry.sol";
import "./interfaces/IGuardManager.sol";
import "./interfaces/IRiskManager.sol";
import "./interfaces/ISmartVault.sol";
import "./interfaces/ISmartVaultManager.sol";
import "./interfaces/ISpoolAccessControl.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/CommonErrors.sol";
import "./interfaces/Constants.sol";
import "./interfaces/RequestType.sol";
import "./access/Roles.sol";
import "./access/SpoolAccessControllable.sol";
import "./SmartVault.sol";
import "./SmartVaultFactory.sol";

/* ========== CONSTANTS ========== */

/**
 * @dev Maximal smart vault performance fee that can be set on a smart vault using this factory. Expressed in terms of FULL_PERCENT.
 */
uint256 constant SV_PERFORMANCE_FEE_HIGH_MAX = 90_00;

/**
 * @dev Grants permission to deploy smart vaults via the SmartVaultFactoryHpf.
 */
bytes32 constant ROLE_HPF_SMART_VAULT_DEPLOYER = keccak256("HPF_SMART_VAULT_DEPLOYER");

/* ========== CONTRACTS ========== */

/**
 * @notice Factory for deploying smart vaults with high performance fees.
 * @dev Requires roles:
 * - ROLE_SMART_VAULT_INTEGRATOR
 * - ADMIN_ROLE_SMART_VAULT_ALLOW_REDEEM
 */
contract SmartVaultFactoryHpf is UpgradeableBeacon, SpoolAccessControllable {
    using uint16a16Lib for uint16a16;

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when a new smart vault is deployed.
     * @param smartVault Address of the newly deployed smart vault.
     * @param deployer Address of the deployer.
     */
    event SmartVaultDeployed(address indexed smartVault, address indexed deployer);

    /* ========== CONSTANTS ========== */

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
    ISmartVaultRegistry immutable _smartVaultRegistry;

    /**
     * @notice Asset group registry contract.
     */
    IAssetGroupRegistry immutable _assetGroupRegistry;

    /**
     * @notice Risk manager contract.
     */
    IRiskManager immutable _riskManager;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address implementation,
        ISpoolAccessControl accessControl_,
        IActionManager actionManager_,
        IGuardManager guardManager_,
        ISmartVaultRegistry smartVaultRegistry_,
        IAssetGroupRegistry assetGroupRegistry_,
        IRiskManager riskManager_
    ) UpgradeableBeacon(implementation) SpoolAccessControllable(accessControl_) {
        if (address(accessControl_) == address(0)) revert ConfigurationAddressZero();
        if (address(actionManager_) == address(0)) revert ConfigurationAddressZero();
        if (address(guardManager_) == address(0)) revert ConfigurationAddressZero();
        if (address(smartVaultRegistry_) == address(0)) revert ConfigurationAddressZero();
        if (address(assetGroupRegistry_) == address(0)) revert ConfigurationAddressZero();
        if (address(riskManager_) == address(0)) revert ConfigurationAddressZero();

        _actionManager = actionManager_;
        _guardManager = guardManager_;
        _smartVaultRegistry = smartVaultRegistry_;
        _assetGroupRegistry = assetGroupRegistry_;
        _riskManager = riskManager_;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Deploys a new smart vault into the Spool ecosystem.
     * @dev Requirements:
     * - caller must have role ROLE_HPF_SMART_VAULT_DEPLOYER
     * @param specification Specifications for the new smart vault.
     * @return smartVault Deployed smart vault.
     */
    function deploySmartVault(SmartVaultSpecification calldata specification)
        external
        onlyRole(ROLE_HPF_SMART_VAULT_DEPLOYER, msg.sender)
        returns (ISmartVault)
    {
        _validateSpecification(specification);

        address smartVaultAddress =
            address(new BeaconProxy(address(this), _encodeInitializationCalldata(specification)));

        _integrateSmartVault(smartVaultAddress, specification);

        emit SmartVaultDeployed(smartVaultAddress, msg.sender);

        return ISmartVault(smartVaultAddress);
    }

    /**
     * @notice Deploys a new smart vault to a deterministic address.
     * @dev Requirements:
     * - caller must have role ROLE_HPF_SMART_VAULT_DEPLOYER
     * @param specification Specifications for the new smart vault.
     * @param salt Salt for address determination.
     * @return smartVault Deployed smart vault.
     */
    function deploySmartVaultDeterministically(SmartVaultSpecification calldata specification, bytes32 salt)
        external
        onlyRole(ROLE_HPF_SMART_VAULT_DEPLOYER, msg.sender)
        returns (ISmartVault)
    {
        _validateSpecification(specification);

        address smartVaultAddress =
            address(new BeaconProxy{salt: salt}(address(this), _encodeInitializationCalldata(specification)));

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

        if (specification.strategies.length == 0) {
            revert SmartVaultRegistrationNoStrategies();
        }
        if (specification.strategies.length > STRATEGY_COUNT_CAP) {
            revert StrategyCapExceeded();
        }

        unchecked {
            bool fixedAllocations = uint16a16.unwrap(specification.strategyAllocation) > 0;
            uint256 fullAllocation;

            if (specification.strategies.length == 1 && !fixedAllocations) {
                revert SingleStrategyDynamicAllocation();
            }

            if (fixedAllocations) {
                if (specification.riskProvider != address(0)) {
                    revert StaticAllocationAndRiskProviderSet();
                }

                if (specification.riskTolerance != 0) {
                    revert StaticAllocationAndRiskToleranceSet();
                }

                if (specification.allocationProvider != address(0)) {
                    revert StaticAllocationAndAllocationProviderSet();
                }
            }

            for (uint256 i; i < specification.strategies.length; ++i) {
                if (fixedAllocations) {
                    if (specification.strategyAllocation.get(i) == 0) {
                        revert InvalidStrategyAllocationsLength();
                    }
                    fullAllocation += specification.strategyAllocation.get(i);
                }

                if (!_accessControl.hasRole(ROLE_STRATEGY, specification.strategies[i])) {
                    revert InvalidStrategy(specification.strategies[i]);
                }

                if (IStrategy(specification.strategies[i]).assetGroupId() != specification.assetGroupId) {
                    revert NotSameAssetGroup();
                }

                for (uint256 j = i + 1; j < specification.strategies.length; ++j) {
                    if (specification.strategies[i] == specification.strategies[j]) {
                        revert StrategiesNotUnique();
                    }
                }
            }

            if (fixedAllocations && fullAllocation != FULL_PERCENT) {
                revert InvalidStaticAllocation();
            }
        }

        if (specification.managementFeePct > MANAGEMENT_FEE_MAX) {
            revert ManagementFeeTooLarge(specification.managementFeePct);
        }
        if (specification.depositFeePct > DEPOSIT_FEE_MAX) {
            revert DepositFeeTooLarge(specification.depositFeePct);
        }
        if (specification.performanceFeePct > SV_PERFORMANCE_FEE_HIGH_MAX) {
            revert PerformanceFeeTooLarge(specification.performanceFeePct);
        }
    }

    /**
     * @notice Encodes calldata for smart vault initialization.
     * @param specification Specifications for the new smart vault.
     * @return initializationCalldata Enoded initialization calldata.
     */
    function _encodeInitializationCalldata(SmartVaultSpecification calldata specification)
        internal
        view
        virtual
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "initialize(string,string,string,uint256)",
            specification.smartVaultName,
            specification.svtSymbol,
            specification.baseURI,
            specification.assetGroupId
        );
    }

    /**
     * @notice Integrates newly created smart vault into the Spool ecosystem.
     * @param smartVaultAddress Address of created smart vault.
     * @param specification Specifications for the new smart vault.
     */
    function _integrateSmartVault(address smartVaultAddress, SmartVaultSpecification calldata specification) private {
        _accessControl.grantSmartVaultOwnership(smartVaultAddress, msg.sender);
        _actionManager.setActions(smartVaultAddress, specification.actions, specification.actionRequestTypes);
        _guardManager.setGuards(smartVaultAddress, specification.guards, specification.guardRequestTypes);

        if (specification.allowRedeemFor) {
            _accessControl.grantRole(ROLE_SMART_VAULT_ALLOW_REDEEM, smartVaultAddress);
        }

        uint16a16 allocations = specification.strategyAllocation;

        // set allocation
        if (uint16a16.unwrap(allocations) == 0) {
            _riskManager.setRiskProvider(smartVaultAddress, specification.riskProvider);
            _riskManager.setRiskTolerance(smartVaultAddress, specification.riskTolerance);
            _riskManager.setAllocationProvider(smartVaultAddress, specification.allocationProvider);

            allocations = _riskManager.calculateAllocation(smartVaultAddress, specification.strategies);
        }

        _smartVaultRegistry.registerSmartVault(
            smartVaultAddress,
            SmartVaultRegistrationForm({
                assetGroupId: specification.assetGroupId,
                strategies: specification.strategies,
                strategyAllocation: allocations,
                managementFeePct: specification.managementFeePct,
                depositFeePct: specification.depositFeePct,
                performanceFeePct: specification.performanceFeePct
            })
        );
    }
}
