// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../SepoliaExtendedSetup.s.sol";

import "../../../src/guards/TimelockGuard.sol";
import "../../../src/SmartVaultFactory.sol";

import "../../helper/Arrays.sol";

contract DeployVaultWithTimelockGuard is SepoliaExtendedSetup {
    uint256 privKey;

    function broadcast() public override {
        privKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        TimelockGuard guard = TimelockGuard(_contractsJson.getAddress(".guards.TimelockGuard.proxy"));

        // get guard data
        (GuardDefinition[][] memory guards, RequestType[] memory guardRequestTypes) = _getGuardData(guard);

        // get strategies
        address[] memory strategies = _getStrategies();

        address riskProvider = _contractsJson.getAddress(".riskProviders.spoolLabs");
        address allocationProvider = address(exponentialAllocationProvider);

        // get spec
        SmartVaultSpecification memory spec =
            _getSpecification(strategies, guards, guardRequestTypes, riskProvider, allocationProvider);

        // create vault and transfer ownership
        vm.startBroadcast(privKey);
        address vault = address(smartVaultFactoryHpf.deploySmartVault(spec));
        guard.updateTimelock(vault, 1 days);
        vm.stopBroadcast();

        console.log("SmartVault deployed: %s", vault);
    }

    function _getGuardData(TimelockGuard guard)
        private
        pure
        returns (GuardDefinition[][] memory guards, RequestType[] memory requestTypes)
    {
        // define the vault guard
        guards = new GuardDefinition[][](1);
        guards[0] = new GuardDefinition[](1);
        GuardParamType[] memory guardParamTypes = new GuardParamType[](2);
        guardParamTypes[0] = GuardParamType.VaultAddress;
        guardParamTypes[1] = GuardParamType.Assets;

        // define the guard
        guards[0][0] = GuardDefinition({ // guard checking the timelock of the nftIds passed for the receiver
            contractAddress: address(guard),
            methodSignature: "checkTimelock(address,uint256[])",
            operator: "",
            expectedValue: 0,
            methodParamTypes: guardParamTypes,
            methodParamValues: new bytes[](0)
        });

        requestTypes = new RequestType[](1);
        requestTypes[0] = RequestType.BurnNFT;
    }

    function _getStrategies() private view returns (address[] memory) {
        // get strategy from contracts
        address[] memory strategies = new address[](1);

        strategies[0] = _contractsJson.getAddress(".strategies.mock2.mock2-usdc");

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
            smartVaultName: "Piggybank - USDC (1 day deposit lock)",
            svtSymbol: "PGB-USDC-L-1D",
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
