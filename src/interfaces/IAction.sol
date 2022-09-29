// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

enum ActionType {
    Deposit,
    Withdrawal
}

struct ActionContext {
    address smartVault;
    address recipient;
    address executor;
    ActionType actionType;
}

struct ActionBag {
    address[] tokens;
    uint256[] amounts;
    bytes payload;
}

interface IAction {
    function actionType() external view;
    function executeAction(ActionContext calldata actionCtx, ActionBag calldata executionBag) external returns (ActionBag memory);
}


interface IActionManager {
    function setActions(address smartVault, IAction[] calldata actions, ActionType[] calldata actionTypes) external;
    function executeActions(address smartVault, ActionContext calldata actionCtx) external;

    event ActionListed(address indexed action, bool whitelisted);
}