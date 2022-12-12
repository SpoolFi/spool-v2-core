// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "@openzeppelin/proxy/Clones.sol";
import "../src/managers/RewardManager.sol";
import "../src/interfaces/IRewardManager.sol";
import "./mocks/MockToken.sol";
import "./mocks/Constants.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "../src/managers/AssetGroupRegistry.sol";
import "../src/SmartVault.sol";
import "../src/managers/GuardManager.sol";
import "./libraries/Arrays.sol";

contract RewardManagerTests is Test, SpoolAccessRoles {
    SpoolAccessControl sac;
    RewardManager rewardManager;
    IAssetGroupRegistry assetGroupRegistry;
    uint256 rewardAmount = 100000 ether;
    uint32 rewardDuration;
    address vaultOwner = address(100);
    address user = address(101);
    address smartVaultManager = address(102);
    address smartVault;
    MockToken rewardToken;
    MockToken underlying;

    function setUp() public {
        rewardToken = new MockToken("R", "R");
        underlying = new MockToken("U", "U");

        sac = new SpoolAccessControl();
        assetGroupRegistry = new AssetGroupRegistry();

        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(underlying)));

        address smartVaultImplementation = address(new SmartVault(sac, new GuardManager(sac)));
        SmartVault smartVault_ = SmartVault(Clones.clone(smartVaultImplementation));
        smartVault_.initialize("SmartVault", assetGroupId);

        rewardManager = new RewardManager(sac, assetGroupRegistry);
        rewardDuration = SECONDS_IN_DAY * 10;
        smartVault = address(smartVault_);

        sac.grantSmartVaultRole(smartVault, ROLE_SMART_VAULT_ADMIN, vaultOwner);
        sac.grantSmartVaultRole(smartVault, ROLE_SMART_VAULT_ADMIN, user);
        sac.grantRole(ROLE_SMART_VAULT_MANAGER, smartVaultManager);
    }

    function test_mock() external pure {}
}
