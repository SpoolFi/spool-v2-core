// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./helper/JsonHelper.sol";
import "./MainnetInitialSetup.s.sol";

contract LocalMainnetInitialSetup is MainnetInitialSetup {
    function init() public virtual override {
        super.init();

        _contractsJson = new JsonWriter(string.concat("deploy/local-mainnet.contracts.json"));
    }

    function test_mock_LocalMainnetInitialSetup() external pure {}
}
