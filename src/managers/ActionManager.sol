// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {console} from "forge-std/console.sol";
import "@0xsequence/sstore2/SSTORE2.sol";
import "../interfaces/IAction.sol";

contract ActionManager is IActionManager {
    /* ========== STATE VARIABLES ========== */

    // @notice True if actions for given smart vault were already initialized
    mapping(address => bool) public actionsInitialized;

    // @notice Action address whitelist
    mapping(address => bool) public actionWhitelisted;

    // @notice Action registry
    mapping(address => mapping(uint256 => address[])) public actions;

    constructor() {}

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice TODO
     * @param smartVault TODO
     * @param actions_ TODO
     * @param requestTypes TODO
     */
    function setActions(address smartVault, IAction[] calldata actions_, RequestType[] calldata requestTypes)
        external
        notInitialized(smartVault)
    {
        for (uint256 i; i < actions_.length; i++) {
            IAction action = actions_[i];
            _onlyWhitelistedAction(address(action));
            actions[smartVault][uint8(requestTypes[i])].push(address(action));
        }

        actionsInitialized[smartVault] = true;
    }

    /**
     * @notice TODO
     * @param smartVault TODO
     * @param actionCtx TODO
     */
    function runActions(address smartVault, ActionContext calldata actionCtx) external {
        if (!actionsInitialized[smartVault]) {
            return;
        }

        address[] memory actions_ = actions[smartVault][uint8(actionCtx.requestType)];
        ActionBag memory bag = ActionBag(actionCtx.tokens, actionCtx.amounts, "");

        for (uint256 i; i < actions_.length; i++) {
            bag = _executeAction(smartVault, actions_[i], actionCtx, bag);
        }
    }

    /**
     * @notice TODO
     * @param action TODO
     * @param whitelist TODO
     */
    function whitelistAction(address action, bool whitelist) external 
    // TODO MISSING MODIFIER FOR ACCESS CONTROL
    {
        if (actionWhitelisted[action] == whitelist) revert ActionStatusAlreadySet();
        actionWhitelisted[action] = whitelist;

        emit ActionListed(action, whitelist);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _executeAction(address smartVault, address action_, ActionContext memory actionCtx, ActionBag memory bag)
        private
        returns (ActionBag memory)
    {
        return IAction(action_).executeAction(actionCtx, bag);
    }

    function _isInitialized(address smartVault, bool initialized) private view {
        if (initialized && actionsInitialized[smartVault] != initialized) {
            revert ActionsInitialized({smartVault: smartVault});
        }
        if (!initialized && actionsInitialized[smartVault] != initialized) {
            revert ActionsNotInitialized({smartVault: smartVault});
        }
    }

    function _onlyWhitelistedAction(address action) private view {
        if (!actionWhitelisted[action]) {
            revert InvalidAction({address_: action});
        }
    }

    /* ========== MODIFIERS ========== */

    /**
     * @notice TODO
     */
    modifier notInitialized(address smartVault) {
        _isInitialized(smartVault, false);
        _;
    }

    /**
     * @notice TODO
     */
    modifier areActionsInitialized(address smartVault) {
        _isInitialized(smartVault, true);
        _;
    }
}
