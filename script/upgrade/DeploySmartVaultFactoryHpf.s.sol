// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "../../src/SmartVaultFactoryHpf.sol";
import {JsonReader} from "../helper/JsonHelper.sol";

contract DeploySmartVaultFactoryHpf is Script {
    JsonReader internal _contractsJson;
    JsonReader internal _constantsJson;

    SmartVaultFactory internal smartVaultFactory;
    ISpoolAccessControl internal spoolAccessControl;
    IActionManager internal actionManager;
    IGuardManager internal guardManager;
    ISmartVaultManager internal smartVaultManager;
    IAssetGroupRegistry internal assetGroupRegistry;
    IRiskManager internal riskManager;

    address internal spoolAdmin;

    SmartVaultFactoryHpf internal smartVaultFactoryHpf;

    function run() external virtual {
        init();
        broadcast();
        execute();
        finalize();
    }

    function init() public virtual {
        _contractsJson = new JsonReader(vm, string.concat("deploy/mainnet.contracts.json"));
        _constantsJson = new JsonReader(vm, string.concat("deploy/mainnet.constants.json"));

        smartVaultFactory = SmartVaultFactory(_contractsJson.getAddress(".SmartVaultFactory"));
        spoolAccessControl = ISpoolAccessControl(_contractsJson.getAddress(".SpoolAccessControl.proxy"));
        actionManager = IActionManager(_contractsJson.getAddress(".ActionManager.proxy"));
        guardManager = IGuardManager(_contractsJson.getAddress(".GuardManager.proxy"));
        smartVaultManager = ISmartVaultManager(_contractsJson.getAddress(".SmartVaultManager.proxy"));
        assetGroupRegistry = IAssetGroupRegistry(_contractsJson.getAddress(".AssetGroupRegistry.proxy"));
        riskManager = IRiskManager(_contractsJson.getAddress(".RiskManager.proxy"));

        spoolAdmin = _constantsJson.getAddress(".spoolAdmin");
    }

    function broadcast() public virtual {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
    }

    function execute() public virtual {
        address implementation = smartVaultFactory.implementation();

        smartVaultFactoryHpf = new SmartVaultFactoryHpf(
            implementation,
            spoolAccessControl,
            actionManager,
            guardManager,
            smartVaultManager,
            assetGroupRegistry,
            riskManager
        );

        smartVaultFactoryHpf.transferOwnership(spoolAdmin);
    }

    function finalize() public virtual {
        address owner = smartVaultFactoryHpf.owner();

        console.log("SmartVaultFactoryHpf deployed at: %s", address(smartVaultFactoryHpf));
        console.log("SmartVaultFactoryHpf owner: %s", owner);
    }

    /**
     * after deploying SmartVaultFactoryHpf, follow these steps to configure the factory:
     * - grant role ROLE_SMART_VAULT_INTEGRATOR to the factory
     * - grant role ADMIN_ROLE_SMART_VAULT_ALLOW_REDEEM to the factory
     * - grant role ROLE_HPF_SMART_VAULT_DEPLOYER to whoever will deploy smart vaults using the factory
     */
}
