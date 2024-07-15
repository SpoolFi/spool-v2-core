// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../MainnetExtendedSetup.s.sol";

contract GetDepositMetadata is MainnetExtendedSetup {
    function execute() public override {
        SmartVault vault = SmartVault(0x0836685D2dbC79E5a5a34874249dBAed6B03a0cA);
        uint[] memory nftIds = new uint[](1);
        nftIds[0] = 130;

        bytes[] memory metadataEncoded = vault.getMetadata(nftIds);
        bytes memory nftMetadataEncoded = metadataEncoded[0];

        DepositMetadata memory nftMetadata = abi.decode(nftMetadataEncoded, (DepositMetadata));

        console.log("number of assets: %d", nftMetadata.assets.length);
        for (uint i = 0; i < nftMetadata.assets.length; i++) {
            console.log("asset amount (index %d): %d", i, nftMetadata.assets[i]);
        }
    }
}
