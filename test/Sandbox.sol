// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";

contract A {
    mapping(address => uint256) private _balances;

    function balanceOf(address addr) public {
        _balances[addr] = 10;
    }

    function displayBalance2(address addr) public returns (uint256) {
        return _balances[addr];
    }
}

contract B {
    mapping(uint256 => mapping(address => uint256)) private _balances;

    function balanceOf(address addr, uint256 b) public {
        _balances[0][addr] = b;
    }

    function displayBalance(address addr) public returns (uint256) {
        return _balances[0][addr];
    }
}

contract C is A, B {}

interface ISingleFunction {
    function SomeRandomFunctionName(address token) view external returns (bool);
}

contract ImpSF is ISingleFunction {
    mapping(address => bool) public SomeRandomFunctionName;
}

contract ActionManagerTest is Test {
    function testA() public {
        address user = address(256);
        C c = new C();
        c.balanceOf(user, 100);
        c.balanceOf(user);

        uint256 balance1 = c.displayBalance(user);
        uint256 balance2 = c.displayBalance2(user);

        console.log(balance1);

        console.log(balance2);
    }
}
