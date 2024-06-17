// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../arbitrum/ArbitrumExtendedSetup.s.sol";

contract UpgradeGammaCamelotStrategy is ArbitrumExtendedSetup {
    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        IGammaCamelotRewards rewards =
            IGammaCamelotRewards(_contractsJson.getAddress(".strategy-helpers.gamma-camelot-rewards.weth-usdc-narrow"));

        address gammaCamelotStrategy =
            _contractsJson.getAddress(".strategies.gamma-camelot.gamma-camelot-weth-usdc-narrow");

        vm.startBroadcast(_deployerPrivateKey);
        GammaCamelotStrategy implementation = new GammaCamelotStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            swapper,
            rewards
        );

        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(gammaCamelotStrategy))), address(implementation));
    }
}
