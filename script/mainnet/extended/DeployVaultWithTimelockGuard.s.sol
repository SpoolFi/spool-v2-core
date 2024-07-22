// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../MainnetExtendedSetup.s.sol";

import "../../../src/guards/TimelockGuard.sol";
import "../../../src/SmartVaultFactory.sol";

import "../../helper/Arrays.sol";

contract DeployVaultWithTimelockGuard is MainnetExtendedSetup {
    address smartVaultOwner = 0x7D965039141418D6F8C0d534f3d86c4b53e2fd4d;

    uint256 privKey;

    function broadcast() public override {
        privKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        // deploy TimelockGuard contract
        TimelockGuard guard = new TimelockGuard(spoolAccessControl);

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
        address vault = address(smartVaultFactory.deploySmartVault(spec));
        spoolAccessControl.transferSmartVaultOwnership(vault, smartVaultOwner);
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
        address[] memory strategies = new address[](3);

        strategies[0] = _contractsJson.getAddress(".strategies.gearbox-v3.gearbox-v3-usdc");
        strategies[1] = _contractsJson.getAddress(".strategies.ethena.ethena-usdc");
        strategies[2] = _contractsJson.getAddress(".strategies.yearn-v3-gauged.yearn-v3-gauged-usdc");

        return strategies;
    }

    function _getSpecification(
        address[] memory strategies,
        GuardDefinition[][] memory guards,
        RequestType[] memory guardRequestTypes,
        address riskProvider,
        address allocationProvider
    ) private view returns (SmartVaultSpecification memory) {
        return SmartVaultSpecification({
            smartVaultName: "Spool (Deposit Lock)",
            svtSymbol: "SPOOLDEPLOCK",
            baseURI: "https://token-cdn-domain/",
            assetGroupId: Strategy(strategies[0]).assetGroupId(),
            strategies: strategies,
            strategyAllocation: Arrays.toUint16a16(0),
            riskTolerance: 10,
            riskProvider: riskProvider,
            allocationProvider: allocationProvider,
            actions: new IAction[](0),
            actionRequestTypes: new RequestType[](0),
            guards: guards,
            guardRequestTypes: guardRequestTypes,
            managementFeePct: 0,
            depositFeePct: 0,
            performanceFeePct: 0,
            allowRedeemFor: false
        });
    }
}
