// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../../../src/strategies/EthenaAirdropStrategy.sol";
import "../MainnetExtendedSetup.s.sol";

contract DeployEthenaAirdropImplementation is MainnetExtendedSetup {
    function broadcast() public override {
        _deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        vm.broadcast(_deployerPrivateKey);

        address USDe = constantsJson().getAddress(".assets.usde.address");
        address sUSDe = constantsJson().getAddress(string.concat(".strategies.", ETHENA_KEY, ".sUSDe"));
        address ENAToken = constantsJson().getAddress(string.concat(".strategies.", ETHENA_KEY, ".ENA"));
        EthenaAirdropStrategy implementation = new EthenaAirdropStrategy(
                assetGroupRegistry,
                spoolAccessControl,
                IERC20Metadata(USDe),
                IsUSDe(sUSDe),
                IERC20Metadata(ENAToken),
                swapper,
                usdPriceFeedManager
        );

        // reserialize strategies
        _contractsJson.reserializeKeyAddress("strategies");
        _contractsJson.addVariantStrategyVariant("ethena", "implementation-airdrop", address(implementation));
    }
}
