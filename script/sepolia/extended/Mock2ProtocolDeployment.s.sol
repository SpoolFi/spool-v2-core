// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../SepoliaExtendedSetup.s.sol";

import "../../../src/strategies/mocks/MockProtocol.sol";

import "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

// source .env && FOUNDRY_PROFILE=sepolia-production forge script Mock2ProtocolDeployment --slow --broadcast --legacy
contract Mock2ProtocolDeployment is SepoliaExtendedSetup {
    uint256 privKey;

    function broadcast() public override {
        privKey = vm.envUint("PRIVATE_KEY");
    }

    function execute() public override {
        vm.startBroadcast(privKey);
        _deployProtocol("dai");
        _deployProtocol("usdc");
        _deployProtocol("usdt");
        vm.stopBroadcast();
    }

    function _deployProtocol(string memory assetKey) internal {
        address token = constantsJson().getAddress(string.concat(".assets.", assetKey, ".address"));
        uint256 apy = constantsJson().getUint256(string.concat(".strategies.mock2.", assetKey, ".apyProtocol"));

        address implementation = address(new MockProtocol());

        MockProtocol mockProtocol =
            MockProtocol(address(new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "")));

        mockProtocol.initialize(token, apy);
        console.log(
            "Deployed MockProtocol with implementation: ", implementation, " and proxy: ", address(mockProtocol)
        );
    }
}
