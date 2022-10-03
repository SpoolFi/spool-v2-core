// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/ActionManager.sol";
import "../src/mocks/MockToken.sol";
import {MockAction,MockActionSetAmountTo100} from "./mocks/MockAction.sol";

contract ActionManagerTest is Test {
    IActionManager actionManager;
    IAction mockAction;
    MockToken mockToken;

    address smartVaultId = address(1);
    address user = address(256);

    function setUp() public {
        actionManager = new ActionManager();
        mockAction = new MockAction();
        mockToken = new MockToken("MCK", "MCK");
    }

    function test_whitelistAction_addressIsNotWhitelisted() public {
        actionManager.whitelistAction(address(mockAction), true);
        vm.expectRevert("ActionManager::whitelistAction: Action status already set.");
        actionManager.whitelistAction(address(mockAction), true);
    }

    function test_setAction_tryAddingBlacklistedAction() public {
        IAction[] memory actions = new IAction[](1);
        actions[0] = mockAction;
        RequestType[] memory requestTypes = new RequestType[](1);
        requestTypes[0] = RequestType.Deposit;
        // actionManager.whitelistAction(address(mockAction), false);
        
        vm.expectRevert("ActionManager::");
        actionManager.setActions(smartVaultId, actions, requestTypes);
    }

    function test_setAction() public {
         
        IAction[] memory actions = new IAction[](2);
        actions[0] = mockAction;
        RequestType[] memory requestTypes = new RequestType[](2);
        requestTypes[0] = RequestType.Deposit;
        requestTypes[1] = RequestType.Deposit;
        
        IAction mockActionSetsAmountsTo100 = new MockActionSetAmountTo100();
        actions[1] = mockActionSetsAmountsTo100;
      
        actionManager.whitelistAction(address(mockAction), true);
        actionManager.whitelistAction(address(mockActionSetsAmountsTo100), true);

        actionManager.setActions(smartVaultId, actions, requestTypes);
        
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        
        ActionContext memory actionContext = ActionContext(address(user), address(user), RequestType.Deposit, tokens, amounts);
        actionManager.runActions(smartVaultId, actionContext);
    }
}
