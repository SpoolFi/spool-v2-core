// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../SepoliaExtendedSetup.s.sol";

import "../../../src/guards/TimelockGuard.sol";
import "../../../src/SmartVaultFactory.sol";

import "../../helper/Arrays.sol";

contract DeployVault is SepoliaExtendedSetup {
    uint256 privKey;

    function broadcast() public override {
        privKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        // get strategies
        address[] memory strategies = _getStrategies();

        address riskProvider = _contractsJson.getAddress(".riskProviders.spoolLabs");
        address allocationProvider = address(exponentialAllocationProvider);

        GuardDefinition[][] memory guards = new GuardDefinition[][](0);
        RequestType[] memory guardRequestTypes = new RequestType[](0);

        // get spec
        SmartVaultSpecification memory spec =
            _getSpecification(strategies, guards, guardRequestTypes, riskProvider, allocationProvider);

        // create vault and transfer ownership
        vm.broadcast(privKey);
        address vault = address(smartVaultFactoryHpf.deploySmartVault(spec));

        console.log("SmartVault deployed: %s", vault);
    }

    function _getStrategies() private view returns (address[] memory) {
        // get strategy from contracts
        address[] memory strategies = new address[](2);

        strategies[0] = _contractsJson.getAddress(".strategies.mock2.mock2-usdc");
        strategies[1] = _contractsJson.getAddress(".strategies.mock-ape.mock-ape-usdc");

        return strategies;
    }

    function _getSpecification(
        address[] memory strategies,
        GuardDefinition[][] memory guards,
        RequestType[] memory guardRequestTypes,
        address riskProvider_,
        address allocationProvider_
    ) private view returns (SmartVaultSpecification memory) {
        uint256 allocation = (strategies.length == 1) ? FULL_PERCENT : 0;
        int8 riskTolerance = (strategies.length == 1) ? int8(0) : int8(10);
        address riskProvider = (strategies.length == 1) ? address(0) : riskProvider_;
        address allocationProvider = (strategies.length == 1) ? address(0) : allocationProvider_;
        return SmartVaultSpecification({
            smartVaultName: "Piggybank - USDC - 90%",
            svtSymbol: "PGB-USDC-90",
            baseURI: "https://token-cdn-domain/",
            assetGroupId: Strategy(strategies[0]).assetGroupId(),
            strategies: strategies,
            strategyAllocation: Arrays.toUint16a16(allocation),
            riskTolerance: riskTolerance,
            riskProvider: riskProvider,
            allocationProvider: allocationProvider,
            actions: new IAction[](0),
            actionRequestTypes: new RequestType[](0),
            guards: guards,
            guardRequestTypes: guardRequestTypes,
            managementFeePct: 0,
            depositFeePct: 0,
            performanceFeePct: 9000,
            allowRedeemFor: true
        });
    }
}
