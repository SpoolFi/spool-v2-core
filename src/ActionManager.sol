// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "@0xsequence/sstore2/contracts/SSTORE2.sol";
import "./interfaces/IAction.sol";

contract ActionManager is IActionManager {

    /* ========== STATE VARIABLES ========== */

    mapping(address => bool) public actionsInitialized;
    mapping(address => bool) public actionWhitelisted;
    mapping(address => mapping(uint256 => address[])) public actions;

    constructor() {}

    /* ========== EXTERNAL FUNCTIONS ========== */

    function setActions(
        address smartVault,
        IAction[] calldata actions_,
        ActionType[] calldata actionTypes
    )
        external 
        notInitialized(smartVault)
    {
        for(uint256 i; i < actions_.length; i++) {
            IAction action = actions_[i];
            _onlyWhitelistedAction(address(action));
            actions[smartVault][uint8(actionTypes[i])].push(address(action));
        }

        actionsInitialized[smartVault] = true;
    }

    function executeActions(address smartVault, ActionContext calldata actionCtx) 
        external
        areActionsInitialized(smartVault)
    {
        address[] memory actions_ = actions[smartVault][uint8(actionCtx.actionType)];
        ActionBag memory bag;
        
        for(uint256 i; i < actions_.length; i++) {
            bag = _executeAction(smartVault, actions_[i], actionCtx, bag);
        }
    }

    function whitelistAction(address action, bool whitelist)
        external
    {
        require(actionWhitelisted[action] == whitelist, "ActionManager::whitelistAction: Action status already set.");
        actionWhitelisted[action] = whitelist;

        emit ActionListed(action, whitelist);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _executeAction(
        address smartVault,
        address action_,
        ActionContext memory actionCtx,
        ActionBag memory bag
    )
        private
        returns (ActionBag memory)
    {
        return ActionBag(new address[](0), new uint256[](0), "");
    }

    function _isInitialized(address smartVault, bool initialized) private view {
        require(
            actionsInitialized[smartVault] == initialized, 
            initialized 
                ? "ActionManager::notInitialized: Smart Vaults has actions initialized." 
                : "ActionManager::notInitialized: Smart Vaults has no actions initialized."
        );
    }

    function _onlyWhitelistedAction(address action) private  view {
        require(actionWhitelisted[action], "ActionManager::");
    }

 
 
    /* ========== MODIFIERS ========== */

    modifier notInitialized(address smartVault) {
        _isInitialized(smartVault,false);
        _;
    }
    
    modifier areActionsInitialized(address smartVault) 
    {
        _isInitialized(smartVault,true);
        _;
    }
    
}
