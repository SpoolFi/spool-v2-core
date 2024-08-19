// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../MainnetExtendedSetup.s.sol";
import "../../../src/SmartVaultBeneficiaryFactoryHpf.sol";
import "../../../src/SmartVaultBeneficiary.sol";

contract DeploySmartVaultBeneficiaryFactoryHpf is MainnetExtendedSetup {
    address internal beneficiaryAddress;
    uint256 internal beneficiaryFee;

    SmartVaultBeneficiaryFactoryHpf internal smartVaultBeneficiaryFactoryHpf;
    SmartVaultBeneficiary internal smartVaultBeneficiary;

    address internal spoolAdmin;

    function init() public override {
        super.init();
        beneficiaryAddress = vm.envAddress("BENEFICIARY_ADDRESS");
        beneficiaryFee = vm.envUint("BENEFICIARY_FEE");
        spoolAdmin = _constantsJson.getAddress(".spoolAdmin");
    }

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        vm.startBroadcast(_deployerPrivateKey);
        smartVaultBeneficiary = new SmartVaultBeneficiary(spoolAccessControl, guardManager);

        smartVaultBeneficiaryFactoryHpf = new SmartVaultBeneficiaryFactoryHpf(
            address(smartVaultBeneficiary),
            spoolAccessControl,
            actionManager,
            guardManager,
            smartVaultManager,
            assetGroupRegistry,
            riskManager,
            beneficiaryAddress,
            beneficiaryFee
        );

        smartVaultBeneficiaryFactoryHpf.transferOwnership(spoolAdmin);
        vm.stopBroadcast();

        contractsJson().add("SmartVaultBeneficiaryFactoryHpf", address(smartVaultBeneficiaryFactoryHpf));
    }

    /**
     * after deploying SmartVaultBeneficiaryFactoryHpf, follow these steps to configure the factory:
     * - grant role ROLE_SMART_VAULT_INTEGRATOR to the factory
     * - grant role ADMIN_ROLE_SMART_VAULT_ALLOW_REDEEM to the factory
     * - grant role ROLE_HPF_SMART_VAULT_DEPLOYER to whoever will deploy smart vaults using the factory
     */
}
