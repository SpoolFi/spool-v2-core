// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../helper/JsonHelper.sol";
import "./ArbitrumInitialSetup.s.sol";

contract LocalArbitrumInitialSetup is ArbitrumInitialSetup {
    function init() public virtual override {
        super.init();

        _contractsJson = new JsonReadWriter(vm, string.concat("deploy/local-arbitrum.contracts.json"));
    }

    function test_mock_LocalArbitrumInitialSetup() external pure {}
}
