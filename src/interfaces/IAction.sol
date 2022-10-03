// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "./RequestType.sol";

struct ActionContext {
    address recipient;
    address executor;
    RequestType requestType;
    address[] tokens;
    uint256[] amounts;
}

struct ActionBag {
    address[] tokens;
    uint256[] amounts;
    bytes payload;
}

interface IAction {
    function actionType() external view;
    function executeAction(ActionContext calldata actionCtx, ActionBag calldata actionBag)
        external
        returns (ActionBag memory);
}

interface IActionManager {
    function setActions(address smartVault, IAction[] calldata actions, RequestType[] calldata requestTypes) external;
    function runActions(address smartVault, ActionContext calldata actionCtx) external;
    function whitelistAction(address action, bool whitelist) external;

    event ActionListed(address indexed action, bool whitelisted);
}
