// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../../src/SpoolLens.sol";
import "../MainnetExtendedSetup.s.sol";

/**
 *  source .env && forge script script/mainnet/metavault/SpoolLensUpgrade.s.sol:SpoolLensUpgrade --rpc-url=$MAINNET_RPC_URL --with-gas-price 10000000000 --slow --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract SpoolLensUpgrade is MainnetExtendedSetup {
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
            new SpoolLens(
                spoolAccessControl,
                assetGroupRegistry,
                riskManager,
                depositManager,
                withdrawalManager,
                strategyRegistry,
                masterWallet,
                usdPriceFeedManager,
                smartVaultManager,
                address(ghostStrategy)
            )
        );
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(spoolLens))), implementation);
        vm.stopBroadcast();

        contractsJson().addProxy("SpoolLens", implementation, address(spoolLens));
    }
}
