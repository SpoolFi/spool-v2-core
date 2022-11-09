// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "./RequestType.sol";

error InvalidAction(address address_);
error ActionStatusAlreadySet();
error ActionsInitialized(address smartVault);
error ActionsNotInitialized(address smartVault);

/**
 * @param recipient In case of deposit, recipient of deposit NFT; in case of withdrawal, recipient of assets.
 * @param executor In case of deposit, executor of deposit action; in case of withdrawal, executor of claimWithdrawal action.
 * @param owner In case of deposit, owner of assets; in case of withdrawal, owner of withdrawal NFT.
 */
struct ActionContext {
    address recipient;
    address executor;
    address owner;
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
