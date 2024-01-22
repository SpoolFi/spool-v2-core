// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../MainnetExtendedSetup.s.sol";
import "../../src/managers/UsdPriceFeedManager.sol";
import "@openzeppelin/proxy/transparent/ProxyAdmin.sol";
import "forge-std/Script.sol";

contract UpgradeUsdPriceFeedManager is MainnetExtendedSetup {
    function execute() public override {
        UsdPriceFeedManager implementation = new UsdPriceFeedManager(spoolAccessControl);

        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(usdPriceFeedManager))), address(implementation));

        uint256 daiTimeLimit = constantsJson().getUint256(string.concat(".assets.dai.priceAggregator.timeLimit"));
        uint256 usdcTimeLimit = constantsJson().getUint256(string.concat(".assets.usdc.priceAggregator.timeLimit"));
        uint256 usdtTimeLimit = constantsJson().getUint256(string.concat(".assets.usdt.priceAggregator.timeLimit"));
        uint256 wethTimeLimit = constantsJson().getUint256(string.concat(".assets.weth.priceAggregator.timeLimit"));

        usdPriceFeedManager.updateAssetTimeLimit(_assets["dai"], daiTimeLimit);
        usdPriceFeedManager.updateAssetTimeLimit(_assets["usdc"], usdcTimeLimit);
        usdPriceFeedManager.updateAssetTimeLimit(_assets["usdt"], usdtTimeLimit);
        usdPriceFeedManager.updateAssetTimeLimit(_assets["weth"], wethTimeLimit);
    }
}
