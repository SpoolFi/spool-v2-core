// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {console} from "forge-std/console.sol";
import {IAction, ActionContext} from "../../src/interfaces/IAction.sol";

contract MockAction is IAction {
    mapping(address => bool) whitelist;

    function test_mock() external pure {}

    function actionType() external view {}

    function executeAction(ActionContext calldata actionCtx) external {
        console.log("MockAction.executeAction");
    }
}

contract MockActionSetAmountTo100 is IAction {
    mapping(address => bool) whitelist;

    function test_mock() external pure {}

    function actionType() external view {}

    function executeAction(ActionContext calldata actionCtx) external {
        console.log("MockActionSetAmountTo100.executeAction");
    }
}
