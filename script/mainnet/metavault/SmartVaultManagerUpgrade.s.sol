// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../../src/managers/SmartVaultManager.sol";
import "../MainnetExtendedSetup.s.sol";

/**
 *  source .env && forge script script/mainnet/metavault/SmartVaultManagerUpgrade.s.sol:SmartVaultManagerUpgrade --rpc-url=$MAINNET_RPC_URL --with-gas-price 10000000000 --slow --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract SmartVaultManagerUpgrade is MainnetExtendedSetup {
    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function doSetup() public override {
        loadSpool();
        loadAssets(assetGroupRegistry, Extended.INITIAL);
    }

    function execute() public override {
        vm.startBroadcast(_deployerPrivateKey);
        address implementation = address(
            new SmartVaultManager(
                spoolAccessControl,
                assetGroupRegistry,
                riskManager,
                depositManager,
                withdrawalManager,
                strategyRegistry,
                masterWallet,
                usdPriceFeedManager,
                address(ghostStrategy)
            )
        );
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(smartVaultManager))), implementation);
        vm.stopBroadcast();

        contractsJson().addProxy("SmartVaultManager", implementation, address(smartVaultManager));
    }
}
