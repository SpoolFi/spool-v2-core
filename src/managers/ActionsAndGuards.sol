// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "../interfaces/IGuardManager.sol";
import "../interfaces/IAction.sol";
import "../interfaces/RequestType.sol";
import "../interfaces/IGuardManager.sol";

abstract contract ActionsAndGuards {
    // @notice Guard manager
    IGuardManager internal immutable _guardManager;

    // @notice Action manager
    IActionManager internal immutable _actionManager;

    constructor(IGuardManager guardManager_, IActionManager actionManager_) {
        _guardManager = guardManager_;
        _actionManager = actionManager_;
    }

    function _runGuards(
        address smartVault,
        address executor,
        address receiver,
        address owner,
        uint256[] memory assets,
        address[] memory assetGroup,
        RequestType requestType
    ) internal view {
        RequestContext memory context = RequestContext(receiver, executor, owner, requestType, assets, assetGroup);
        _guardManager.runGuards(smartVault, context);
    }

    function _runActions(
        address smartVault,
        address executor,
        address recipient,
        address owner,
        uint256[] memory assets,
        address[] memory assetGroup,
        RequestType requestType
    ) internal {
        ActionContext memory context = ActionContext(recipient, executor, owner, requestType, assetGroup, assets);
        _actionManager.runActions(smartVault, context);
    }
}
