// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../../src/strategies/ERC4626Strategy.sol";

contract MockERC4626ReInitializer is ERC4626Strategy {
    string public message;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        IERC4626 vault_
    ) ERC4626Strategy(assetGroupRegistry_, accessControl_, vault_) {
        _disableInitializers();
    }

    function reinitialize(string calldata message_) external reinitializer(2) {
        message = message_;
    }
}
