// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/utils/Strings.sol";

import "../../../src/DepositSwap.sol";
import "../MainnetExtendedSetup.s.sol";

/**
 *  source .env && forge script script/mainnet/metavault/DepositSwapUpgrade.s.sol:DepositSwapUpgrade --rpc-url=$MAINNET_RPC_URL --with-gas-price 2000000000 --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DepositSwapUpgrade is MainnetExtendedSetup {
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
            new DepositSwap(IWETH9(vm.envAddress("WETH_ADDRESS")), assetGroupRegistry, smartVaultManager, swapper)
        );
        if (Strings.equal(vm.envString("FOUNDRY_PROFILE"), "mainnet-staging")) {
            proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(depositSwap))), implementation);
        }
        vm.stopBroadcast();

        contractsJson().addProxy("DepositSwap", implementation, address(depositSwap));
    }
}
