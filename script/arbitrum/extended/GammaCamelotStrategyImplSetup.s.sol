// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../ArbitrumExtendedSetup.s.sol";

contract GammaCamelotStrategyImplSetup is ArbitrumExtendedSetup {
    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        IGammaCamelotRewards rewards =
            IGammaCamelotRewards(_contractsJson.getAddress(".strategy-helpers.gamma-camelot-rewards.weth-usdc-narrow"));

        vm.broadcast(_deployerPrivateKey);
        GammaCamelotStrategy implementation = new GammaCamelotStrategy(
            assetGroupRegistry,
            spoolAccessControl,
            swapper,
            rewards
        );

        // reserialize strategies
        contractsJson().reserializeKeyAddress("strategies");

        contractsJson().addVariantStrategyImplementation(GAMMA_CAMELOT_KEY, address(implementation));
    }
}
