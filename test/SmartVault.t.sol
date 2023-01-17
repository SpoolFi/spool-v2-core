// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/proxy/Clones.sol";
import {GuardFailed, RequestContext, IGuardManager} from "../src/interfaces/IGuardManager.sol";
import {
    InvalidNftTransferAmount,
    DepositMetadata,
    WithdrawalMetadata,
    NFT_MINTED_SHARES
} from "../src/interfaces/ISmartVault.sol";
import {SpoolAccessControl, MissingRole} from "../src/access/SpoolAccessControl.sol";
import {ROLE_SMART_VAULT_MANAGER} from "../src/access/Roles.sol";
import {SmartVault} from "../src/SmartVault.sol";

contract SmartVaultTest is Test {
    address alice;
    address bob;
    address smartVaultManager;

    SmartVault smartVault;

    SpoolAccessControl accessControl;
    MockGuardManager guardManager;

    function setUp() public {
        alice = address(0xa);
        bob = address(0xb);

        accessControl = new SpoolAccessControl();
        accessControl.initialize();

        smartVaultManager = address(0x1);
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, smartVaultManager);

        guardManager = new MockGuardManager();

        SmartVault smartVaultImplementation = new SmartVault(accessControl, IGuardManager(address(guardManager)));
        smartVault = SmartVault(Clones.clone(address(smartVaultImplementation)));
        smartVault.initialize("SmartVault", 1);
    }

    function test_transferNft_shouldTransferFullBalance() public {
        // mint deposit NFT
        DepositMetadata memory depositMetadata =
            DepositMetadata({assets: new uint256[](0), initiated: 0, flushIndex: 0});
        vm.prank(smartVaultManager);
        uint256 depositNftId = smartVault.mintDepositNFT(alice, depositMetadata);
        // mint withdrawal NFT
        WithdrawalMetadata memory withdrawalMetadata = WithdrawalMetadata({vaultShares: 0, flushIndex: 0});
        vm.prank(smartVaultManager);
        uint256 withdrawalNftId = smartVault.mintWithdrawalNFT(alice, withdrawalMetadata);

        vm.prank(alice);
        smartVault.safeTransferFrom(alice, bob, depositNftId, NFT_MINTED_SHARES, "");
        vm.prank(alice);
        smartVault.safeTransferFrom(alice, bob, withdrawalNftId, NFT_MINTED_SHARES, "");

        assertEq(smartVault.balanceOf(alice, depositNftId), 0);
        assertEq(smartVault.balanceOfFractional(bob, depositNftId), NFT_MINTED_SHARES);
        assertEq(smartVault.balanceOf(alice, withdrawalNftId), 0);
        assertEq(smartVault.balanceOfFractional(bob, withdrawalNftId), NFT_MINTED_SHARES);
    }

    function test_transferNft_shouldRevertWhenTransferingPartialBalance() public {
        // mint deposit NFT
        DepositMetadata memory depositMetadata =
            DepositMetadata({assets: new uint256[](0), initiated: 0, flushIndex: 0});
        vm.prank(smartVaultManager);
        uint256 depositNftId = smartVault.mintDepositNFT(alice, depositMetadata);
        // mint withdrawal NFT
        WithdrawalMetadata memory withdrawalMetadata = WithdrawalMetadata({vaultShares: 0, flushIndex: 0});
        vm.prank(smartVaultManager);
        uint256 withdrawalNftId = smartVault.mintWithdrawalNFT(alice, withdrawalMetadata);

        vm.expectRevert(abi.encodeWithSelector(InvalidNftTransferAmount.selector, 1, NFT_MINTED_SHARES));
        vm.prank(alice);
        smartVault.safeTransferFrom(alice, bob, depositNftId, 1, "");
        vm.expectRevert(abi.encodeWithSelector(InvalidNftTransferAmount.selector, 1, NFT_MINTED_SHARES));
        vm.prank(alice);
        smartVault.safeTransferFrom(alice, bob, withdrawalNftId, 1, "");
    }

    function test_transferNft_shouldRevertWhenGuardsFail() public {
        // mint deposit NFT
        DepositMetadata memory depositMetadata =
            DepositMetadata({assets: new uint256[](0), initiated: 0, flushIndex: 0});
        vm.prank(smartVaultManager);
        uint256 depositNftId = smartVault.mintDepositNFT(alice, depositMetadata);
        // mint withdrawal NFT
        WithdrawalMetadata memory withdrawalMetadata = WithdrawalMetadata({vaultShares: 0, flushIndex: 0});
        vm.prank(smartVaultManager);
        uint256 withdrawalNftId = smartVault.mintWithdrawalNFT(alice, withdrawalMetadata);

        guardManager.setShouldRevert(true);

        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 0));
        vm.prank(alice);
        smartVault.safeTransferFrom(alice, bob, depositNftId, NFT_MINTED_SHARES, "");
        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 0));
        vm.prank(alice);
        smartVault.safeTransferFrom(alice, bob, withdrawalNftId, NFT_MINTED_SHARES, "");
    }

    function test_transferFromSpender_shouldTransferWhenFromEqualsSpender() public {
        // give Alice SVTs
        deal(address(smartVault), alice, 1_000_000, true);

        // Alice transfers her tokens to Bob
        vm.prank(smartVaultManager);
        smartVault.transferFromSpender(alice, bob, 1_000_000, alice);

        assertEq(smartVault.balanceOf(alice), 0);
        assertEq(smartVault.balanceOf(bob), 1_000_000);
    }

    function test_transferFromSpender_shouldTransferWhenAllowanceIsSetForSpender() public {
        // give Alice SVTs
        deal(address(smartVault), alice, 1_000_000, true);

        // Alice approves Bob to spend her tokens
        vm.prank(alice);
        smartVault.approve(bob, 1_000_000);

        // Bob transfers Alices tokens to Bob
        vm.prank(smartVaultManager);
        smartVault.transferFromSpender(alice, bob, 1_000_000, bob);

        assertEq(smartVault.balanceOf(alice), 0);
        assertEq(smartVault.balanceOf(bob), 1_000_000);
        assertEq(smartVault.allowance(alice, bob), 0);
    }

    function test_transferFromSpender_shouldRevertWhenNotCalledBySmartVaultManager() public {
        // give Alice SVTs
        deal(address(smartVault), alice, 1_000_000, true);

        // Alice tries transfers her tokens to Bob herself
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SMART_VAULT_MANAGER, alice));
        vm.prank(alice);
        smartVault.transferFromSpender(alice, bob, 1_000_000, alice);
    }

    function test_transferFromSpender_shouldRevertWhenAllowanceIsNotSetForSpender() public {
        // give Alice SVTs
        deal(address(smartVault), alice, 1_000_000, true);

        // Bob transfers Alices tokens to Bob without approval
        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(smartVaultManager);
        smartVault.transferFromSpender(alice, bob, 1_000_000, bob);
    }

    function test_transferFromSpender_shouldRevertWhenGuardsFail() public {
        // give Alice SVTs
        deal(address(smartVault), alice, 1_000_000, true);

        guardManager.setShouldRevert(true);

        // Alice tries to transfer her tokens to Bob
        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 0));
        vm.prank(smartVaultManager);
        smartVault.transferFromSpender(alice, bob, 1_000_000, alice);
    }

    function test_transferFromSpender_shouldNotRevertWhenGuardsFailWhenToEqualsSmartVault() public {
        // give Alice SVTs
        deal(address(smartVault), alice, 1_000_000, true);

        guardManager.setShouldRevert(true);

        // Alice transfers her tokens to SmartVault as part of redeemal
        vm.prank(smartVaultManager);
        smartVault.transferFromSpender(alice, address(smartVault), 1_000_000, alice);

        assertEq(smartVault.balanceOf(alice), 0);
        assertEq(smartVault.balanceOf(address(smartVault)), 1_000_000);
    }
}

contract MockGuardManager {
    bool _shouldRevert;

    function test_mock() external pure {}

    function setShouldRevert(bool shouldRevert_) external {
        _shouldRevert = shouldRevert_;
    }

    function runGuards(address, RequestContext calldata) external view {
        if (_shouldRevert) {
            revert GuardFailed(0);
        }
    }
}
