// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor (string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _mint(msg.sender, 1_000_000_000 ether);
    }
}