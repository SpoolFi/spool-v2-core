// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../../src/Strategy.sol";

contract MockStrategy is Strategy {
    uint256[] public ratios;
    uint256[] public __withdrawnAssets;
    bool public __withdrawnAssetsSet;

    constructor(string memory name_, IStrategyRegistry strategyRegistry_, IMasterWallet masterWallet_)
        Strategy(name_, strategyRegistry_, masterWallet_)
    {}

    function initialize(address[] memory assetGroup_, uint256[] memory ratios_) public virtual {
        super.initialize(assetGroup_);
        ratios = ratios_;
    }

    function assetRatio() external view override returns (uint256[] memory) {
        return ratios;
    }

    function dhw(uint256 withdrawnShares) external override returns (uint256[] memory) {
        require(__withdrawnAssetsSet, "MockStrategy::dhw: Withdrawn assets not set.");

        // withdraw from protocol
        for (uint256 i = 0; i < _assetGroup.length; i++) {
            IERC20(_assetGroup[i]).transfer(address(masterWallet), __withdrawnAssets[i]);
        }

        // burn SSTs for withdrawal
        _burn(address(this), withdrawnShares);

        __withdrawnAssetsSet = false;
        return __withdrawnAssets;
    }

    function _setWithdrawnAssets(uint256[] memory withdrawnAssets_) external {
        require(withdrawnAssets_.length == _assetGroup.length, "MockStrategy::_setWithdrawnAssets: Not correct length.");

        __withdrawnAssets = withdrawnAssets_;
        __withdrawnAssetsSet = true;
    }
}
