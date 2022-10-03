// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {console} from "forge-std/console.sol";
import {IAction, ActionContext, ActionBag} from "../../src/interfaces/IAction.sol";
contract MockAction is IAction {
    mapping(address => bool) whitelist;

    function actionType() external view
    {
        
    }
    function executeAction(ActionContext calldata actionCtx, ActionBag calldata executionBag)
        external
        returns (ActionBag memory) 
    {
       console.log("MockAction.executeAction");
       return executionBag;
    }
}

contract MockActionSetAmountTo100 is IAction {
    mapping(address => bool) whitelist;

    function actionType() external view
    {
        
    }
    function executeAction(ActionContext calldata actionCtx, ActionBag memory actionBag)
        external
        returns (ActionBag memory) 
    {
        console.log("MockActionSetAmountTo100.executeAction");
        actionBag.amounts[0]=100;
        
        return actionBag;
    }
}