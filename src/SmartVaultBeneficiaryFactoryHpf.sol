// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./SmartVaultFactoryHpf.sol";

error ExceedMaxFeeBp();
error ManagementFeeNoneZero();
error DepositFeeNoneZero();
error PerformanceFeeNotMax();

uint256 constant MAX_FEE_IN_BP = 100_00;

contract SmartVaultBeneficiaryFactoryHpf is SmartVaultFactoryHpf {
    /**
     * @notice address to receive share of SVTs from SmartVault onwer
     */
    address public immutable beneficiary;
    /**
     * @notice beneficiary fee in base points
     */
    uint256 public immutable feeInBp;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address implementation,
        ISpoolAccessControl accessControl_,
        IActionManager actionManager_,
        IGuardManager guardManager_,
        ISmartVaultRegistry smartVaultRegistry_,
        IAssetGroupRegistry assetGroupRegistry_,
        IRiskManager riskManager_,
        address beneficiary_,
        uint256 feeInBp_
    )
        SmartVaultFactoryHpf(
            implementation,
            accessControl_,
            actionManager_,
            guardManager_,
            smartVaultRegistry_,
            assetGroupRegistry_,
            riskManager_
        )
    {
        if (address(beneficiary_) == address(0)) revert ConfigurationAddressZero();
        if (feeInBp_ > MAX_FEE_IN_BP) revert ExceedMaxFeeBp();
        beneficiary = beneficiary_;
        feeInBp = feeInBp_;
    }

    function _validateSpecification(SmartVaultSpecification calldata specification) internal view override {
        if (specification.managementFeePct > 0) {
            revert ManagementFeeNoneZero();
        }
        if (specification.depositFeePct > 0) {
            revert DepositFeeNoneZero();
        }
        if (specification.performanceFeePct != SV_PERFORMANCE_FEE_HIGH_MAX) {
            revert PerformanceFeeNotMax();
        }
        super._validateSpecification(specification);
    }

    function _encodeInitializationCalldata(SmartVaultSpecification calldata specification)
        internal
        view
        virtual
        override
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "initialize(string,string,string,uint256,address,uint256)",
            specification.smartVaultName,
            specification.svtSymbol,
            specification.baseURI,
            specification.assetGroupId,
            beneficiary,
            feeInBp
        );
    }
}
