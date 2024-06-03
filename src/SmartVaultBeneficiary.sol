// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./SmartVault.sol";

error ExceedMaxFeeBp();

contract SmartVaultBeneficiary is SmartVault {
    uint256 internal constant MAX_FEE_IN_BP = 100_00;
    address public immutable beneficiary;
    uint256 public immutable feeInBp;

    constructor(ISpoolAccessControl accessControl_, IGuardManager guardManager_, address beneficiary_, uint256 feeInBp_)
        SmartVault(accessControl_, guardManager_)
    {
        if (address(beneficiary_) == address(0)) revert ConfigurationAddressZero();
        if (feeInBp_ > MAX_FEE_IN_BP) revert ExceedMaxFeeBp();
        beneficiary = beneficiary_;
        feeInBp = feeInBp_;

        _disableInitializers();
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
