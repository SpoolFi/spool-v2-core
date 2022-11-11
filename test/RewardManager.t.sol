// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/managers/RewardManager.sol";
import "../src/interfaces/IRewardManager.sol";
import "./mocks/MockToken.sol";
import "./mocks/Constants.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

contract RewardManagerTests is Test, SpoolAccessRoles {
    SpoolAccessControl sac;
    RewardManager rewardManager;
    uint256 rewardAmount;
    uint32 rewardDuration;
    address vaultOwner;
    address smartVault;
    MockToken rewardToken;
    address user;

    function setUp() public {
        sac = new SpoolAccessControl();
        rewardManager = new RewardManager(sac);
        rewardAmount = 100000 ether;
        rewardDuration = SECONDS_IN_DAY * 10;
        MockToken smartVaultToken = new MockToken("SVT", "SVT");
        smartVault = address(smartVaultToken);
        vaultOwner = address(100);

        sac.grantSmartVaultRole(smartVault, ROLE_SMART_VAULT_ADMIN, vaultOwner);
        rewardToken = new MockToken("R", "R");

        user = address(101);
    }
}
