// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../../src/managers/SmartVaultManager.sol";
import "../SepoliaExtendedSetup.s.sol";

/**
 *  source .env && forge script script/sepolia/metavault/SmartVaultManagerUpgrade.s.sol:SmartVaultManagerUpgrade --rpc-url=$SEPOLIA_RPC_URL --with-gas-price 2000000000 --slow --broadcast --optimizer-runs 200 --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract SmartVaultManagerUpgrade is SepoliaExtendedSetup {
    uint256 _deployerPrivateKey;

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
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
