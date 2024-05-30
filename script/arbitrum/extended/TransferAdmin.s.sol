// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../ArbitrumExtendedSetup.s.sol";

contract TransferAdmin is ArbitrumExtendedSetup {
    function execute() public override {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        address keeperDoHardWorker = constantsJson().getAddress(".keeperDoHardWorker");
        address riskProvider = constantsJson().getAddress(".riskProvider");
        address ecosystemFeeReceiver = constantsJson().getAddress(".fees.ecosystemFeeReceiver");
        address treasuryFeeReceiver = constantsJson().getAddress(".fees.treasuryFeeReceiver");
        address emergencyWithdrawalWallet = constantsJson().getAddress(".emergencyWithdrawalWallet");

        // renounce DO_HARD_WORKER role
        spoolAccessControl.renounceRole(ROLE_DO_HARD_WORKER, deployerAddress);

        // set real DO_HARD_WORKER role
        spoolAccessControl.grantRole(ROLE_DO_HARD_WORKER, keeperDoHardWorker);

        // renounce RISK_PROVIDER role
        spoolAccessControl.renounceRole(ROLE_RISK_PROVIDER, deployerAddress);

        // set real RISK_PROVIDER role
        spoolAccessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);

        // set fee receivers (overrides previous)
        strategyRegistry.setEcosystemFeeReceiver(ecosystemFeeReceiver);
        strategyRegistry.setTreasuryFeeReceiver(treasuryFeeReceiver);

        // set emergencyWithdrawalWallet (overrides previous)
        strategyRegistry.setEmergencyWithdrawalWallet(emergencyWithdrawalWallet);

        // revert and set admin/deploy rights
        postDeploySpool(deployerAddress);
    }
}
