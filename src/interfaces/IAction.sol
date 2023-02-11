// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "./RequestType.sol";

error InvalidAction(address address_);
error ActionStatusAlreadySet();
error ActionsAlreadyInitialized(address smartVault);

/**
 * @custom:member recipient In case of deposit, recipient of deposit NFT; in case of withdrawal, recipient of assets.
 * @custom:member executor In case of deposit, executor of deposit action; in case of withdrawal, executor of claimWithdrawal action.
 * @custom:member owner In case of deposit, owner of assets; in case of withdrawal, owner of withdrawal NFT.
 */
struct ActionContext {
    address smartVault;
    address recipient;
    address executor;
    address owner;
    RequestType requestType;
    address[] tokens;
    uint256[] amounts;
}

interface IAction {
    function actionType() external view;
    function executeAction(ActionContext calldata actionCtx) external;
}

interface IActionManager {
    function setActions(address smartVault, IAction[] calldata actions, RequestType[] calldata requestTypes) external;
    function runActions(ActionContext calldata actionCtx) external;
    function whitelistAction(address action, bool whitelist) external;

    event ActionListed(address indexed action, bool whitelisted);
}
