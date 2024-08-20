// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../SepoliaExtendedSetup.s.sol";

contract UpdateRewardTokenPerSecond is SepoliaExtendedSetup {
    function execute() public override {
        address[] memory strategies = new address[](4);
        strategies[0] = _contractsJson.getAddress(string.concat(".strategies.mock.mock-dai"));
        strategies[1] = _contractsJson.getAddress(string.concat(".strategies.mock.mock-usdc"));
        strategies[2] = _contractsJson.getAddress(string.concat(".strategies.mock.mock-usdt"));
        strategies[3] = _contractsJson.getAddress(string.concat(".strategies.mock.mock-weth"));

        for (uint256 i = 0; i < strategies.length; i++) {
            MockStrategy(strategies[i]).updateRewardTokenPerSecond(1);
        }
    }
}
