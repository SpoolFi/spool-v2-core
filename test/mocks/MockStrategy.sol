// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../../src/Strategy.sol";

contract MockStrategy is Strategy {
    uint256[] public ratios;

    constructor(string memory name_, IStrategyRegistry strategyRegistry_) Strategy(name_, strategyRegistry_) {}

    function initialize(address[] memory assetGroup_, uint256[] memory ratios_) public virtual {
        super.initialize(assetGroup_);
        ratios = ratios_;
    }

    function assetRatio() external view override returns (uint256[] memory) {
        return ratios;
    }
}
