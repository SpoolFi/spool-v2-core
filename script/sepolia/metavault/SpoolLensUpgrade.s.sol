// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../../src/SpoolLens.sol";
import "../SepoliaExtendedSetup.s.sol";

/**
 *  source .env && forge script script/sepolia/metavault/SpoolLensUpgrade.s.sol:SpoolLensUpgrade --rpc-url=$SEPOLIA_RPC_URL --with-gas-price 2000000000 --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract SpoolLensUpgrade is SepoliaExtendedSetup {
    uint256 _deployerPrivateKey;

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
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
