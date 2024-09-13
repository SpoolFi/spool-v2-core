// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/utils/Strings.sol";

import "../../../src/DepositSwap.sol";
import "../SepoliaExtendedSetup.s.sol";

/**
 *  source .env && forge script script/sepolia/metavault/DepositSwapUpgrade.s.sol:DepositSwapUpgrade --rpc-url=$SEPOLIA_RPC_URL --with-gas-price 2000000000 --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DepositSwapUpgrade is SepoliaExtendedSetup {
    uint256 _deployerPrivateKey;

    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        vm.startBroadcast(_deployerPrivateKey);
        address implementation = address(
            new DepositSwap(IWETH9(vm.envAddress("WETH_ADDRESS")), assetGroupRegistry, smartVaultManager, swapper)
        );
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(depositSwap))), implementation);
        vm.stopBroadcast();

        contractsJson().addProxy("DepositSwap", implementation, address(depositSwap));
    }
}
