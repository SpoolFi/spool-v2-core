// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../MainnetExtendedSetup.s.sol";

contract GetExchangeRate is MainnetExtendedSetup {
    function execute() public override {
        //ISmartVault srEthVault = ISmartVault( 0xdD2dFC120834c769C061c1DAb7Dc5310E1c584E7 );
        //ISmartVault srEthVault = ISmartVault( 0x5d6ac99835b0dd42eD9FfC606170E59f75a88Fde );
        ISmartVault srEthVault = ISmartVault(0x1795E697C1a7803b7151ff9605E5b88841E3d325);
        //uint ethUsdPrice = usdPriceFeedManager.assetToUsd(_assets["weth"], 1 ether);
        uint256 ethUsdPrice = usdPriceFeedManager.assetToUsd(_assets["dai"], 1 ether);

        uint256[] memory assetBalances = spoolLens.getSmartVaultAssetBalances(address(srEthVault), false);
        uint256 vaultTotalSupply = spoolLens.getSVTTotalSupply(address(srEthVault)) / INITIAL_SHARE_MULTIPLIER;

        uint256 assetBalance = (assetBalances[0] * ethUsdPrice) / 1 ether;
        uint256 svtSharePrice = (assetBalance * 1 ether) / vaultTotalSupply;

        console.log("ethUsdPrice: :", ethUsdPrice);
        console.log("assetBalance: ", assetBalance);
        console.log("vaultTotalSupply: ", vaultTotalSupply);
        console.log("svtSharePrice: ", svtSharePrice);
    }

    function test_mock_GetExchangeRate() external pure {}
}
