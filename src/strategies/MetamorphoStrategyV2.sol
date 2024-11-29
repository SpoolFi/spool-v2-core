// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {
    MetamorphoStrategy,
    IAssetGroupRegistry,
    ISpoolAccessControl,
    ISwapper,
    ROLE_EMERGENCY_WITHDRAWAL_EXECUTOR
} from "./MetamorphoStrategy.sol";

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

interface IMorphoWrapper {
    function depositFor(address account, uint256 value) external returns (bool);
}

contract MetamorphoStrategyV2 is MetamorphoStrategy {
    address constant LEGACY_MORPHO_TOKEN = 0x9994E35Db50125E0DF82e4c2dde62496CE330999;
    address constant MORPHO_WRAPPER = 0x9D03bb2092270648d7480049d0E58d2FcF0E5123;

    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, ISwapper swapper_)
        MetamorphoStrategy(assetGroupRegistry_, accessControl_, swapper_)
    {}

    function exchangeLegacyMorpho(address account) external onlyRole(ROLE_EMERGENCY_WITHDRAWAL_EXECUTOR, msg.sender) {
        uint256 legacyMorphoBalance = IERC20(LEGACY_MORPHO_TOKEN).balanceOf(address(this));
        IERC20(LEGACY_MORPHO_TOKEN).approve(MORPHO_WRAPPER, legacyMorphoBalance);
        IMorphoWrapper(MORPHO_WRAPPER).depositFor(account, legacyMorphoBalance);
    }
}
