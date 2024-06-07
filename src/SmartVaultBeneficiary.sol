// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./SmartVault.sol";
import {MAX_FEE_IN_BP, ExceedMaxFeeBp} from "./SmartVaultBeneficiaryFactoryHpf.sol";

contract SmartVaultBeneficiary is SmartVault {
    address public beneficiary;
    uint256 public feeInBp;

    constructor(ISpoolAccessControl accessControl_, IGuardManager guardManager_)
        SmartVault(accessControl_, guardManager_)
    {
        _disableInitializers();
    }

    function initialize(
        string calldata vaultName_,
        string calldata svtSymbol,
        string calldata baseURI_,
        uint256 assetGroupId_,
        address beneficiary_,
        uint256 feeInBp_
    ) external {
        initialize(vaultName_, svtSymbol, baseURI_, assetGroupId_);
        if (address(beneficiary_) == address(0)) revert ConfigurationAddressZero();
        if (feeInBp_ > MAX_FEE_IN_BP) revert ExceedMaxFeeBp();
        beneficiary = beneficiary_;
        feeInBp = feeInBp_;
    }

    function mintVaultShares(address receiver, uint256 vaultShares)
        external
        override
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
    {
        uint256 beneficiaryShares;
        if (receiver == _accessControl.smartVaultOwner(address(this))) {
            beneficiaryShares = feeInBp * vaultShares / MAX_FEE_IN_BP;
        }
        uint256 receiverShares = vaultShares - beneficiaryShares;
        if (beneficiaryShares > 0) {
            _mint(beneficiary, beneficiaryShares);
        }
        if (receiverShares > 0) {
            _mint(receiver, receiverShares);
        }
    }
}
