// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../../../src/interfaces/Constants.sol";
import "../../../src/strategies/AaveV2Strategy.sol";
import "../../../src/strategies/CompoundV2Strategy.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../../mocks/MockAllocationProvider.sol";
import "../ForkTestFixtureDeployment.sol";

import "@openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

import "../../../src/MetaVault.sol";

contract MetaVaultTest is ForkTestFixtureDeployment {
    MockAllocationProvider public mockAllocationProvider;

    function setUp() public {
        _deploy(Extended.INITIAL); // deploy just initial strategies

        mockAllocationProvider = new MockAllocationProvider();
        vm.startPrank(_spoolAdmin);
        _deploySpool.spoolAccessControl().grantRole(ROLE_ALLOCATION_PROVIDER, address(mockAllocationProvider));
        vm.stopPrank();
    }

    function test_deploySpool() public {
        uint256 assetGroupIdUSDC = _getAssetGroupId(USDC_KEY);

        address aaveStrategy = _getStrategyAddress(AAVE_V2_KEY, assetGroupIdUSDC);
        address compoundV2Strategy = _getStrategyAddress(COMPOUND_V2_KEY, assetGroupIdUSDC);

        address[] memory strategies = Arrays.toArray(aaveStrategy, compoundV2Strategy);

        uint16a16 allocations = uint16a16Lib.set(uint16a16.wrap(0), Arrays.toArray(FULL_PERCENT / 2, FULL_PERCENT / 2));
        ISmartVault vault = _createVault(0, 0, assetGroupIdUSDC, strategies, allocations, address(0));

        address alice = address(0xa);
        _dealTokens(alice);

        // DEPOSIT
        uint256 depositAmount = 10 ** 10;
        uint256 depositId = _deposit(vault, alice, depositAmount);
        _flushVaults(vault);

        // DHW
        _dhw(strategies);

        // WITHDRAWAL
        uint256 withdrawalId = _redeemNfts(vault, alice, depositId);
        _flushVaults(vault);

        // DHW
        _dhw(strategies);

        // CLAIM
        uint256 balanceBefore = usdc.balanceOf(alice);
        _claimWithdrawals(vault, alice, withdrawalId);
        uint256 balanceAfter = usdc.balanceOf(alice);

        assertApproxEqAbs(balanceAfter - balanceBefore, depositAmount, 2);
    }

    function test_metaVault_simpleFlow() public {
        uint256 assetGroupIdUSDC = _getAssetGroupId(USDC_KEY);

        address strategy1 = _getStrategyAddress(AAVE_V2_KEY, assetGroupIdUSDC);

        uint16a16 allocations = uint16a16Lib.set(uint16a16.wrap(0), Arrays.toArray(FULL_PERCENT));
        ISmartVault vault1 = _createVault(assetGroupIdUSDC, Arrays.toArray(strategy1), allocations, address(0));

        address owner = address(0x19);
        address user1 = address(0x1);
        _dealTokens(user1);
        _dealTokens(owner);

        uint256 initialUser1Balance = usdc.balanceOf(user1);

        vm.startPrank(owner);
        address metaVaultImpl = address(new MetaVault(address(_smartVaultManager), address(usdc)));
        MetaVault metaVault = MetaVault(address(new ERC1967Proxy(metaVaultImpl, "")));
        metaVault.initialize("MetaVault", "M");
        vm.stopPrank();

        vm.startPrank(user1);
        usdc.approve(address(metaVault), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);
        usdc.approve(address(metaVault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user1);
        metaVault.deposit(100e6);
        assertEq(metaVault.balanceOf(user1), 100e6);
        assertEq(metaVault.availableAssets(), 100e6);
        assertEq(usdc.balanceOf(address(metaVault)), 100e6);
        vm.stopPrank();

        vm.startPrank(owner);
        uint256 depositNft = metaVault.spoolDeposit(address(vault1), 80e6, true);
        assertEq(metaVault.availableAssets(), 20e6);
        assertEq(usdc.balanceOf(address(metaVault)), 20e6);
        vm.stopPrank();

        _dhw(strategy1);
        {
            vm.startPrank(user1);
            metaVault.redeemRequest(20e6);
            uint256 currentWithdrawalIndex = metaVault.currentWithdrawalIndex();
            uint256 totalRequested = metaVault.withdrawalIndexToRequestedAmount(currentWithdrawalIndex);
            uint256 userRequested = metaVault.userToWithdrawalIndexToRequestedAmount(user1, currentWithdrawalIndex);
            assertEq(20e6, userRequested);
            assertEq(totalRequested, userRequested);
            assertEq(metaVault.availableAssets(), 20e6);
            assertEq(metaVault.balanceOf(user1), 80e6);
            vm.expectRevert(MetaVault.RedeemRequestNotFulfilled.selector);
            metaVault.withdraw(currentWithdrawalIndex);
            vm.stopPrank();

            vm.startPrank(owner);
            metaVault.fulfillWithdraw();
            assertEq(metaVault.availableAssets(), 0);
            assertEq(currentWithdrawalIndex + 1, metaVault.currentWithdrawalIndex());
            assertEq(currentWithdrawalIndex, metaVault.lastFulfilledWithdrawalIndex());
            assertEq(usdc.balanceOf(address(metaVault)), 20e6);
            vm.stopPrank();

            vm.startPrank(user1);
            uint256 userBalanceBefore = usdc.balanceOf(user1);
            metaVault.withdraw(currentWithdrawalIndex);
            uint256 userBalanceAfter = usdc.balanceOf(user1);
            assertEq(metaVault.availableAssets(), 0);
            assertEq(currentWithdrawalIndex + 1, metaVault.currentWithdrawalIndex());
            assertEq(currentWithdrawalIndex, metaVault.lastFulfilledWithdrawalIndex());
            assertEq(usdc.balanceOf(address(metaVault)), 0);
            assertEq(userBalanceAfter, userBalanceBefore + 20e6);
            vm.stopPrank();
        }

        {
            vm.startPrank(user1);
            metaVault.redeemRequest(80e6);
            uint256 currentWithdrawalIndex = metaVault.currentWithdrawalIndex();
            uint256 totalRequested = metaVault.withdrawalIndexToRequestedAmount(currentWithdrawalIndex);
            uint256 userRequested = metaVault.userToWithdrawalIndexToRequestedAmount(user1, currentWithdrawalIndex);
            assertEq(80e6, userRequested);
            assertEq(totalRequested, userRequested);
            assertEq(metaVault.availableAssets(), 0);
            assertEq(metaVault.balanceOf(user1), 0);
        }

        {
            // deposit by owner is not possible if there are unfulfilled redeem requests
            vm.startPrank(owner);
            vm.expectRevert(MetaVault.PendingRedeemRequests.selector);
            metaVault.spoolDeposit(address(vault1), 80e6, true);
            vm.stopPrank();
        }

        {
            vm.startPrank(owner);
            metaVault.claimSmartVaultTokens(
                address(vault1), Arrays.toArray(depositNft), Arrays.toArray(NFT_MINTED_SHARES)
            );
            uint256 withdrawalNft = metaVault.spoolRedeem(
                RedeemBag(address(vault1), vault1.balanceOf(address(metaVault)), new uint256[](0), new uint256[](0)),
                true
            );
            _dhw(strategy1);
            _syncVaults(vault1);
            vm.startPrank(owner);
            uint256[] memory nftIds = new uint256[](1);
            nftIds[0] = withdrawalNft;
            uint256[] memory nftAmounts = new uint256[](1);
            nftAmounts[0] = vault1.balanceOfFractional(address(metaVault), withdrawalNft);
            metaVault.spoolClaimWithdrawal(address(vault1), nftIds, nftAmounts);
            vm.stopPrank();

            assertEq(usdc.balanceOf(address(metaVault)), metaVault.availableAssets());
            assertApproxEqAbs(metaVault.availableAssets(), 80e6, 1);
        }

        {
            vm.startPrank(owner);
            // there might be rounding down error for withdrawal so we top up assets a little bit
            metaVault.pumpAssets(1);
            metaVault.fulfillWithdraw();
            assertApproxEqAbs(metaVault.availableAssets(), 0, 1);
            vm.stopPrank();
        }

        {
            vm.startPrank(user1);
            metaVault.withdraw(metaVault.lastFulfilledWithdrawalIndex());
            assertApproxEqAbs(usdc.balanceOf(address(metaVault)), 0, 1);
            assertApproxEqAbs(metaVault.availableAssets(), 0, 1);
            assertEq(usdc.balanceOf(user1), initialUser1Balance);
        }
    }

    function _createVault(
        uint256 assetGroupId,
        address[] memory strategies,
        uint16a16 allocations,
        address allocationProvider
    ) internal returns (ISmartVault smartVault) {
        address riskProvider = _riskProvider;

        if (uint16a16.unwrap(allocations) > 0) {
            riskProvider = address(0);
        }

        smartVault = _deploySpool.smartVaultFactory().deploySmartVault(
            SmartVaultSpecification({
                smartVaultName: "MySmartVault",
                svtSymbol: "MSV",
                baseURI: "https://token-cdn-domain/",
                assetGroupId: assetGroupId,
                actions: new IAction[](0),
                actionRequestTypes: new RequestType[](0),
                guards: new GuardDefinition[][](0),
                guardRequestTypes: new RequestType[](0),
                strategies: strategies,
                strategyAllocation: allocations,
                riskTolerance: 0,
                riskProvider: riskProvider,
                managementFeePct: 0,
                depositFeePct: 0,
                allocationProvider: allocationProvider,
                performanceFeePct: 100,
                allowRedeemFor: false
            })
        );
    }
}
