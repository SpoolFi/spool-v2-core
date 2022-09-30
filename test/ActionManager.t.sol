// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/ActionManager.sol";

contract ActionManagerTest is Test {
    IActionManager actionManager;

    function setUp() public {
        actionManager = new ActionManager();
    }
}
