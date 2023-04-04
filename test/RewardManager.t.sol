// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "@openzeppelin/proxy/Clones.sol";
import "../src/rewards/RewardManager.sol";
import "../src/interfaces/IRewardManager.sol";
import "./mocks/MockToken.sol";
import "./mocks/Constants.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "../src/managers/AssetGroupRegistry.sol";
import "../src/SmartVault.sol";
import "../src/access/SpoolAccessControl.sol";
import "../src/managers/GuardManager.sol";
import "./libraries/Arrays.sol";
import "./mocks/MockSmartVaultBalance.sol";

contract RewardManagerTests is Test {
    SpoolAccessControl sac;
    RewardManager rewardManager;
    AssetGroupRegistry assetGroupRegistry;
    uint256 rewardAmount = 100000 ether;
    uint256 endTimestamp;
    uint256 duration = 10 days;
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
        sac.initialize();
        assetGroupRegistry = new AssetGroupRegistry(sac);
        assetGroupRegistry.initialize(Arrays.toArray(address(underlying)));

        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(underlying)));

        address smartVaultImplementation = address(new SmartVault(sac, new GuardManager(sac)));
        SmartVault smartVault_ = SmartVault(Clones.clone(smartVaultImplementation));
        smartVault_.initialize("SmartVault", assetGroupId);

        rewardManager = new RewardManager(sac, assetGroupRegistry, false);
        rewardManager.initialize();

        // NOTE: can use days keyword
        endTimestamp = block.timestamp + duration;
        smartVault = address(smartVault_);

        sac.grantSmartVaultRole(smartVault, ROLE_SMART_VAULT_ADMIN, vaultOwner);
        sac.grantSmartVaultRole(smartVault, ROLE_SMART_VAULT_ADMIN, user);
        sac.grantRole(ROLE_SMART_VAULT_MANAGER, smartVaultManager);
    }

    function test_shouldAddOneToken() public {
        deal(address(rewardToken), vaultOwner, rewardAmount, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, endTimestamp, rewardAmount);
        vm.stopPrank();

        assertEq(1, rewardManager.rewardTokensCount(smartVault));
        assertEq(address(rewardToken), address(rewardManager.rewardTokens(smartVault, 0)));
        (
            uint32 configurationRewardsDuration,
            ,
            uint192 configurationRewardRate, // rewards per second multiplied by accuracy
        ) = rewardManager.rewardConfiguration(smartVault, IERC20(rewardToken));

        assertEq(configurationRewardsDuration, duration);

        uint256 rate = rewardAmount * 1 ether / duration;
        assertEq(rate, configurationRewardRate);

        assertEq(false, rewardManager.tokenBlacklisted(smartVault, rewardToken));
    }

    function test_addingTwoRewardTokens() public {
        MockToken r2Token = new MockToken("R2", "R2");

        deal(address(rewardToken), vaultOwner, rewardAmount, true);
        deal(address(r2Token), vaultOwner, rewardAmount, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        r2Token.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, endTimestamp, rewardAmount);
        rewardManager.addToken(smartVault, r2Token, endTimestamp, rewardAmount);
        vm.stopPrank();

        assertEq(2, rewardManager.rewardTokensCount(smartVault));
        assertEq(address(rewardToken), address(rewardManager.rewardTokens(smartVault, 0)));
        assertEq(address(r2Token), address(rewardManager.rewardTokens(smartVault, 1)));
        (
            uint32 configurationRewardsDuration,
            ,
            uint192 configurationRewardRate, // rewards per second multiplied by accuracy
        ) = rewardManager.rewardConfiguration(smartVault, IERC20(rewardToken));

        assertEq(duration, configurationRewardsDuration);

        uint256 rate = rewardAmount * 1 ether / duration;
        assertEq(rate, configurationRewardRate);

        assertEq(rewardToken.balanceOf(address(rewardManager)), rewardAmount);
        assertEq(r2Token.balanceOf(address(rewardManager)), rewardAmount);
    }

    function test_forceRemovedTokensAreNotAdded() public {
        sac.grantRole(ROLE_SPOOL_ADMIN, user);
        deal(address(rewardToken), vaultOwner, rewardAmount, true);

        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, endTimestamp, rewardAmount);
        vm.stopPrank();

        vm.prank(user);
        rewardManager.forceRemoveReward(smartVault, rewardToken);
        vm.expectRevert(abi.encodeWithSelector(RewardTokenBlacklisted.selector, address(rewardToken)));

        vm.prank(vaultOwner);
        rewardManager.addToken(smartVault, rewardToken, endTimestamp, rewardAmount);

        assertEq(true, rewardManager.tokenBlacklisted(smartVault, rewardToken));

        (
            uint32 configurationRewardsDuration,
            uint32 configurationPeriodFinish,
            uint192 configurationRewardRate, // rewards per second multiplied by accuracy
            uint32 configurationLastUpdateTime
        ) = rewardManager.rewardConfiguration(smartVault, IERC20(rewardToken));

        assertEq(0, configurationRewardsDuration);
        assertEq(0, configurationPeriodFinish);
        assertEq(0, configurationRewardRate);
        assertEq(0, configurationLastUpdateTime);
    }

    function test_extendWithoutAdd() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidRewardToken.selector, address(rewardToken)));
        rewardManager.extendRewardEmission(smartVault, rewardToken, rewardAmount, endTimestamp);
    }

    function test_addToken_invalidEndTimestamp() public {
        vm.prank(vaultOwner);
        vm.expectRevert(abi.encodeWithSelector(InvalidEndTimestamp.selector));
        rewardManager.addToken(smartVault, rewardToken, 0, rewardAmount);
    }

    function test_addToken_revertRewardEqualsUnderlying() public {
        vm.prank(vaultOwner);
        vm.expectRevert(abi.encodeWithSelector(AssetGroupToken.selector, address(underlying)));
        rewardManager.addToken(smartVault, underlying, endTimestamp, rewardAmount);
    }

    function test_extendRewardEmission_revertInvalidEndTimestamp() public {
        deal(address(rewardToken), vaultOwner, rewardAmount, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, endTimestamp, rewardAmount);

        vm.expectRevert(abi.encodeWithSelector(InvalidEndTimestamp.selector));
        rewardManager.extendRewardEmission(smartVault, rewardToken, 0, 0);
        vm.stopPrank();
    }

    function test_extendRewardEmission_revertNewRewardRateLessThanBefore() public {
        deal(address(rewardToken), vaultOwner, rewardAmount + 1 ether, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount + 1 ether);
        rewardManager.addToken(smartVault, rewardToken, endTimestamp, rewardAmount);

        vm.expectRevert(abi.encodeWithSelector(NewRewardRateLessThanBefore.selector));
        rewardManager.extendRewardEmission(smartVault, rewardToken, 1 ether, endTimestamp * 100);
        vm.stopPrank();
    }

    function test_extendRewardEmissions_shouldNotRevertIfAddedWithZeroAmount() public {
        deal(address(rewardToken), vaultOwner, 200 ether, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), 200 ether);
        rewardManager.addToken(smartVault, rewardToken, endTimestamp, 0);

        rewardManager.extendRewardEmission(smartVault, rewardToken, 1 ether, endTimestamp);
        vm.stopPrank();
    }

    function test_extendRewardEmission_ok() public {
        deal(address(rewardToken), vaultOwner, rewardAmount * 2, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount * 2);
        rewardManager.addToken(smartVault, rewardToken, endTimestamp, rewardAmount);

        rewardManager.extendRewardEmission(smartVault, rewardToken, 1 ether, endTimestamp);
        vm.stopPrank();
    }

    function test_extendRewardEmission_revertSmallerRate() public {
        deal(address(rewardToken), vaultOwner, rewardAmount * 2, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount * 2);
        rewardManager.addToken(smartVault, rewardToken, endTimestamp, rewardAmount);

        vm.expectRevert(abi.encodeWithSelector(NewPeriodFinishLessThanBefore.selector));
        rewardManager.extendRewardEmission(smartVault, rewardToken, 1 ether, endTimestamp - 5 days);
        vm.stopPrank();
    }

    function test_removeReward_revertNotFinished() public {
        deal(address(rewardToken), vaultOwner, rewardAmount, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, endTimestamp, rewardAmount);

        vm.expectRevert(abi.encodeWithSelector(RewardsNotFinished.selector));
        rewardManager.removeReward(smartVault, rewardToken);
        vm.stopPrank();
    }

    function test_removeReward_ok() public {
        deal(address(rewardToken), vaultOwner, rewardAmount, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, endTimestamp, rewardAmount);

        skip(duration + 1);

        rewardManager.removeReward(smartVault, rewardToken);
        vm.stopPrank();
    }

    function test_forceRemoveReward_ok() public {
        sac.grantRole(ROLE_SPOOL_ADMIN, address(user));
        deal(address(rewardToken), vaultOwner, rewardAmount, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, endTimestamp, rewardAmount);
        vm.stopPrank();

        vm.prank(user);
        rewardManager.forceRemoveReward(smartVault, rewardToken);
    }

    function test_removeFromBlacklist_revertMissingRole() public {
        deal(address(rewardToken), vaultOwner, rewardAmount, true);

        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, endTimestamp, rewardAmount);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SPOOL_ADMIN, user));
        rewardManager.removeFromBlacklist(smartVault, rewardToken);
    }

    function test_removeFromBlacklist_revertIfNotBlacklisted() public {
        sac.grantRole(ROLE_SPOOL_ADMIN, address(user));
        deal(address(rewardToken), vaultOwner, rewardAmount, true);

        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, endTimestamp, rewardAmount);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(TokenNotBlacklisted.selector));
        rewardManager.removeFromBlacklist(smartVault, rewardToken);
    }

    function test_removeFromBlacklist_ok() public {
        sac.grantRole(ROLE_SPOOL_ADMIN, address(user));
        deal(address(rewardToken), vaultOwner, rewardAmount, true);

        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, endTimestamp, rewardAmount);
        vm.stopPrank();

        vm.startPrank(user);
        rewardManager.forceRemoveReward(smartVault, rewardToken);
        assertTrue(rewardManager.tokenBlacklisted(smartVault, rewardToken));

        rewardManager.removeFromBlacklist(smartVault, rewardToken);
        vm.stopPrank();
        assertFalse(rewardManager.tokenBlacklisted(smartVault, rewardToken));
    }

    function test_forceRemoveReward_revertMissingRole() public {
        deal(address(rewardToken), vaultOwner, rewardAmount, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), rewardAmount);
        rewardManager.addToken(smartVault, rewardToken, endTimestamp, rewardAmount);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SPOOL_ADMIN, user));
        rewardManager.forceRemoveReward(smartVault, rewardToken);
    }

    function test_removeAndExtendRewardEmission() public {
        deal(address(rewardToken), vaultOwner, 2000 ether, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), 2000 ether);
        rewardManager.addToken(smartVault, rewardToken, block.timestamp + 20 days, 1000 ether);

        skip(30 days);

        rewardManager.removeReward(smartVault, rewardToken);
        vm.expectRevert(abi.encodeWithSelector(InvalidRewardToken.selector, address(rewardToken)));
        rewardManager.extendRewardEmission(smartVault, rewardToken, 1000 ether, block.timestamp + 60 days);
        vm.stopPrank();
    }

    function test_removeAndAddRewards() public {
        deal(address(rewardToken), vaultOwner, 2000 ether, true);
        vm.startPrank(vaultOwner);
        rewardToken.approve(address(rewardManager), 2000 ether);
        rewardManager.addToken(smartVault, rewardToken, block.timestamp + 20 days, 1000 ether);

        skip(30 days);

        rewardManager.removeReward(smartVault, rewardToken);

        skip(1 days);

        rewardManager.addToken(smartVault, rewardToken, block.timestamp + 15 days, 150 ether);
        vm.stopPrank();

        (uint32 rewardsDuration,,,) = rewardManager.rewardConfiguration(smartVault, rewardToken);
        assertEq(rewardsDuration, 15 days);
    }
}
