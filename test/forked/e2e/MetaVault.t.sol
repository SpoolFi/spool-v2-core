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
import "../../../src/libraries/ListMap.sol";

contract MetaVaultTest is ForkTestFixtureDeployment {
    MockAllocationProvider public mockAllocationProvider;
    MetaVault public metaVault;
    ISmartVault public vault1;
    ISmartVault public vault2;

    address[] public strategies;

    address owner = address(0x19);
    address user1 = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        _deploy(Extended.INITIAL); // deploy just initial strategies

        mockAllocationProvider = new MockAllocationProvider();
        vm.startPrank(_spoolAdmin);
        _deploySpool.spoolAccessControl().grantRole(ROLE_ALLOCATION_PROVIDER, address(mockAllocationProvider));
        vm.stopPrank();

        uint256 assetGroupIdUSDC = _getAssetGroupId(USDC_KEY);

        address strategy1 = _getStrategyAddress(AAVE_V2_KEY, assetGroupIdUSDC);
        address strategy2 = _getStrategyAddress(COMPOUND_V2_KEY, assetGroupIdUSDC);
        strategies.push(strategy1);
        strategies.push(strategy2);

        uint16a16 allocations = uint16a16Lib.set(uint16a16.wrap(0), Arrays.toArray(FULL_PERCENT));
        vault1 = _createVault(assetGroupIdUSDC, Arrays.toArray(strategy1), allocations, address(0), 0, 0, 100);
        vault2 = _createVault(assetGroupIdUSDC, Arrays.toArray(strategy2), allocations, address(0), 0, 0, 100);

        _dealTokens(user1);
        _dealTokens(user2);
        _dealTokens(owner);

        vm.startPrank(owner);
        address metaVaultImpl = address(
            new MetaVault(_smartVaultManager, _deploySpool.spoolAccessControl(), _deploySpool.assetGroupRegistry())
        );
        metaVault = MetaVault(address(new ERC1967Proxy(metaVaultImpl, "")));
        metaVault.initialize(address(usdc), "MetaVault", "M");
        vm.stopPrank();

        vm.startPrank(user1);
        usdc.approve(address(metaVault), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(user2);
        usdc.approve(address(metaVault), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);
        usdc.approve(address(metaVault), type(uint256).max);
        vm.stopPrank();
    }

    function test_smartVaultIsValid() external {
        // same asset group, zero management and deposit fee vault is valid
        assertTrue(metaVault.smartVaultIsValid(address(vault1)));
        assertTrue(metaVault.smartVaultIsValid(address(vault2)));
        // different asset group is not valid
        {
            uint256 assetGroup = _getAssetGroupId(USDT_KEY);
            address vault = address(
                _createVault(
                    assetGroup,
                    Arrays.toArray(_getStrategyAddress(AAVE_V2_KEY, assetGroup)),
                    uint16a16Lib.set(uint16a16.wrap(0), Arrays.toArray(FULL_PERCENT)),
                    address(0),
                    0,
                    0,
                    100
                )
            );
            vm.expectRevert(MetaVault.InvalidVaultAsset.selector);
            metaVault.smartVaultIsValid(vault);
        }
        // non zero management fee is not valid
        {
            uint256 assetGroup = _getAssetGroupId(USDC_KEY);
            address vault = address(
                _createVault(
                    assetGroup,
                    Arrays.toArray(_getStrategyAddress(AAVE_V2_KEY, assetGroup)),
                    uint16a16Lib.set(uint16a16.wrap(0), Arrays.toArray(FULL_PERCENT)),
                    address(0),
                    10,
                    0,
                    100
                )
            );
            vm.expectRevert(MetaVault.InvalidVaultManagementFee.selector);
            metaVault.smartVaultIsValid(vault);
        }
        // non zero deposit fee is not valid
        {
            uint256 assetGroup = _getAssetGroupId(USDC_KEY);
            address vault = address(
                _createVault(
                    assetGroup,
                    Arrays.toArray(_getStrategyAddress(AAVE_V2_KEY, assetGroup)),
                    uint16a16Lib.set(uint16a16.wrap(0), Arrays.toArray(FULL_PERCENT)),
                    address(0),
                    0,
                    10,
                    100
                )
            );
            vm.expectRevert(MetaVault.InvalidVaultDepositFee.selector);
            metaVault.smartVaultIsValid(vault);
        }
    }

    function test_addSmartVaults() external {
        // owner can add smart vault
        {
            address[] memory vaults = new address[](1);
            vaults[0] = address(vault1);
            uint256[] memory allocations = new uint256[](1);
            allocations[0] = 100_00;
            vm.startPrank(owner);
            metaVault.addSmartVaults(vaults, allocations);
            vm.stopPrank();
            assertEq(metaVault.getSmartVaults(), vaults);
        }
        // owner cannot add the same vault second time
        {
            address[] memory vaults = new address[](1);
            vaults[0] = address(vault1);
            uint256[] memory allocations = new uint256[](2);
            allocations[0] = 50_00;
            allocations[1] = 50_00;
            vm.startPrank(owner);
            vm.expectRevert(ElementAlreadyInList.selector);
            metaVault.addSmartVaults(vaults, allocations);
            vm.stopPrank();
        }
        // not owner cannot add vault
        {
            address[] memory vaults = new address[](1);
            vaults[0] = address(vault2);
            uint256[] memory allocations = new uint256[](2);
            allocations[0] = 50_00;
            allocations[1] = 50_00;
            vm.expectRevert("Ownable: caller is not the owner");
            metaVault.addSmartVaults(vaults, allocations);
        }
        // max amount of managed vaults cannot exceed MAX_SMART_VAULT_AMOUNT
        {
            uint256 vaultsToAddAmount = metaVault.MAX_SMART_VAULT_AMOUNT() - metaVault.getSmartVaults().length + 1;
            address[] memory vaultsToAdd = new address[](vaultsToAddAmount);
            uint256 assetGroup = _getAssetGroupId(USDC_KEY);
            for (uint256 i; i < vaultsToAddAmount; i++) {
                vaultsToAdd[i] = address(
                    _createVault(
                        assetGroup,
                        Arrays.toArray(_getStrategyAddress(AAVE_V2_KEY, assetGroup)),
                        uint16a16Lib.set(uint16a16.wrap(0), Arrays.toArray(FULL_PERCENT)),
                        address(0),
                        0,
                        0,
                        100
                    )
                );
            }
            vm.startPrank(owner);
            vm.expectRevert(MetaVault.MaxSmartVaultAmount.selector);
            metaVault.addSmartVaults(vaultsToAdd, new uint256[](1));
            vm.stopPrank();
        }
    }

    function test_setSmartVaultAllocations() external {
        {
            address[] memory vaults = new address[](2);
            vaults[0] = address(vault1);
            vaults[1] = address(vault2);
            uint256[] memory allocations = new uint256[](2);
            allocations[0] = 50_00;
            allocations[1] = 50_00;
            vm.startPrank(owner);
            metaVault.addSmartVaults(vaults, allocations);
            vm.stopPrank();
        }
        //  owner cannot set wrong allocation
        {
            uint256[] memory allocations = new uint256[](2);
            allocations[0] = 50_00;
            allocations[1] = 40_00;
            vm.startPrank(owner);
            vm.expectRevert(MetaVault.WrongAllocation.selector);
            metaVault.setSmartVaultAllocations(allocations);
            vm.stopPrank();
        }
        //  owner cannot set wrong allocation
        {
            uint256[] memory allocations = new uint256[](1);
            allocations[0] = 100_00;
            vm.startPrank(owner);
            vm.expectRevert(MetaVault.ArgumentLengthMismatch.selector);
            metaVault.setSmartVaultAllocations(allocations);
            vm.stopPrank();
        }
        //  owner cannot set wrong allocation
        {
            uint256[] memory allocations = new uint256[](3);
            allocations[0] = 20_00;
            allocations[1] = 30_00;
            allocations[2] = 50_00;
            vm.startPrank(owner);
            vm.expectRevert(MetaVault.ArgumentLengthMismatch.selector);
            metaVault.setSmartVaultAllocations(allocations);
            vm.stopPrank();
        }
        //  not owner cannot change allocation
        {
            uint256[] memory allocations = new uint256[](2);
            allocations[0] = 10_00;
            allocations[1] = 90_00;
            vm.expectRevert("Ownable: caller is not the owner");
            metaVault.setSmartVaultAllocations(allocations);
        }
    }

    function test_smartVaultSupported() external {
        assertFalse(metaVault.smartVaultSupported(address(vault1)));
        {
            address[] memory vaults = new address[](1);
            vaults[0] = address(vault1);
            uint256[] memory allocations = new uint256[](1);
            allocations[0] = 100_00;
            vm.startPrank(owner);
            metaVault.addSmartVaults(vaults, allocations);
            vm.stopPrank();
        }
        assertTrue(metaVault.smartVaultSupported(address(vault1)));
        assertFalse(metaVault.smartVaultSupported(address(vault2)));
    }

    function test_removeSmartVaults() external {
        {
            address[] memory vaults = new address[](2);
            vaults[0] = address(vault1);
            vaults[1] = address(vault2);
            uint256[] memory allocations = new uint256[](2);
            allocations[0] = 90_00;
            allocations[1] = 10_00;
            vm.startPrank(owner);
            metaVault.addSmartVaults(vaults, allocations);
            vm.stopPrank();
        }
        // vault cannot be removed if its allocation is non zero
        {
            address[] memory vaults = new address[](2);
            vaults[0] = address(vault1);
            vaults[1] = address(vault2);
            uint256[] memory allocations = new uint256[](2);
            allocations[0] = 90_00;
            allocations[1] = 10_00;
            vm.startPrank(owner);
            vm.expectRevert(MetaVault.NonZeroAllocation.selector);
            metaVault.removeSmartVaults(vaults);
            vm.stopPrank();
        }
        // remove vault
        {
            uint256[] memory allocations = new uint256[](2);
            allocations[0] = 0;
            allocations[1] = 100_00;
            vm.startPrank(owner);
            metaVault.setSmartVaultAllocations(allocations);
            address[] memory vaults = new address[](1);
            vaults[0] = address(vault1);
            metaVault.removeSmartVaults(vaults);
            vaults[0] = address(vault2);
            vm.stopPrank();
            assertEq(metaVault.getSmartVaults(), vaults);
        }
    }

    // function test_metaVault_simpleFlow() public {
    //     ISmartVault[] memory vaults = new ISmartVault[](2);
    //     vaults[0] = vault1;
    //     vaults[1] = vault2;

    //     vm.startPrank(user1);
    //     metaVault.mint(100e6);
    //     assertEq(metaVault.balanceOf(user1), 100e6);
    //     assertEq(metaVault.availableAssets(), 100e6);
    //     assertEq(metaVault.positionTotal(), 0);
    //     assertEq(usdc.balanceOf(address(metaVault)), 100e6);
    //     vm.stopPrank();

    //     {
    //         vm.startPrank(owner);
    //         address[] memory v = new address[](2);
    //         v[0] = address(vault1);
    //         v[1] = address(vault2);
    //         uint256[] memory a = new uint256[](2);
    //         a[0] = 20_00;
    //         a[1] = 80_00;
    //         metaVault.addSmartVaults(v, a);
    //         assertEq(metaVault.getSmartVaults(), v);
    //         vm.stopPrank();
    //     }

    //     metaVault.flushDeposit();
    //     _flushVaults(vaults);
    //     _dhw(strategies);
    //     _syncVaults(vaults);
    //     metaVault.syncDeposit();

    //     assertEq(metaVault.availableAssets(), 0);
    //     assertEq(usdc.balanceOf(address(metaVault)), 0);
    //     assertEq(metaVault.positionTotal(), 100e6);

    //     uint256 withdrawalIndex = metaVault.currentWithdrawalIndex();
    //     uint256 svts1Before = vault1.balanceOf(address(metaVault));
    //     uint256 svts2Before = vault2.balanceOf(address(metaVault));
    //     assertTrue(svts1Before > 0);
    //     assertTrue(svts2Before > 0);

    //     {
    //         vm.startPrank(user1);
    //         metaVault.redeem(20e6);
    //         uint256 currentWithdrawalIndex = metaVault.currentWithdrawalIndex();
    //         uint256 totalRequested = metaVault.withdrawalIndexToRedeemedShares(currentWithdrawalIndex);
    //         uint256 userRequested = metaVault.userToWithdrawalIndexToRedeemedShares(user1, currentWithdrawalIndex);
    //         assertEq(20e6, userRequested);
    //         assertEq(totalRequested, userRequested);
    //         vm.expectRevert(MetaVault.RedeemRequestNotFulfilled.selector);
    //         // user cannot withdraw if request is not fulfilled
    //         metaVault.withdraw(currentWithdrawalIndex);
    //         vm.stopPrank();
    //     }

    //     metaVault.flushWithdrawal();

    //     assertTrue(vault1.balanceOf(address(metaVault)) > 0);
    //     assertTrue(vault2.balanceOf(address(metaVault)) > 0);
    //     assertEq(metaVault.getSmartVaultWithdrawalNftIds(address(vault1)).length, 1);
    //     assertEq(metaVault.getSmartVaultWithdrawalNftIds(address(vault2)).length, 1);

    //     assertApproxEqAbs(
    //         vault2.balanceOf(address(metaVault)) * 100_00 / vault1.balanceOf(address(metaVault)),
    //         metaVault.smartVaultToAllocation(address(vault2)) * 100_00
    //             / metaVault.smartVaultToAllocation(address(vault1)),
    //         1
    //     );
    //     assertEq(withdrawalIndex + 1, metaVault.currentWithdrawalIndex());
    //     assertEq(metaVault.getSmartVaultWithdrawalNftIds(address(vault1)).length, 1);
    //     assertEq(metaVault.getSmartVaultWithdrawalNftIds(address(vault2)).length, 1);

    //     _flushVaults(vaults);
    //     _dhw(strategies);
    //     _syncVaults(vaults);

    //     {
    //         uint256 lastFulfilledWithdrawalIndex = metaVault.lastFulfilledWithdrawalIndex();
    //         metaVault.syncWithdrawal();
    //         uint256 svts1Withdrawn = svts1Before - vault1.balanceOf(address(metaVault));
    //         uint256 svts2Withdrawn = svts2Before - vault2.balanceOf(address(metaVault));
    //         assertEq(svts1Withdrawn * 100 / svts1Before, svts2Withdrawn * 100 / svts2Before);
    //         assertEq(svts1Withdrawn * 100 / svts1Before, 20);

    //         assertEq(lastFulfilledWithdrawalIndex + 1, metaVault.lastFulfilledWithdrawalIndex());
    //         assertEq(metaVault.positionTotal(), 80e6);
    //         assertEq(metaVault.getSmartVaultWithdrawalNftIds(address(vault1)).length, 0);
    //         assertEq(metaVault.getSmartVaultWithdrawalNftIds(address(vault2)).length, 0);
    //     }

    //     {
    //         vm.startPrank(user1);
    //         uint256 userBalanceBefore = usdc.balanceOf(user1);
    //         metaVault.withdraw(1);
    //         uint256 userBalanceAfter = usdc.balanceOf(user1);
    //         assertApproxEqAbs(userBalanceAfter - userBalanceBefore, 20e6, 2);
    //         assertEq(userBalanceAfter - userBalanceBefore, metaVault.withdrawalIndexToWithdrawnAssets(1));
    //         vm.stopPrank();
    //     }
    // }

    function _createVault(
        uint256 assetGroupId,
        address[] memory strategies_,
        uint16a16 allocations,
        address allocationProvider,
        uint16 managementFeePct,
        uint16 depositFeePct,
        uint16 performanceFeePct
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
                strategies: strategies_,
                strategyAllocation: allocations,
                riskTolerance: 0,
                riskProvider: riskProvider,
                managementFeePct: managementFeePct,
                depositFeePct: depositFeePct,
                allocationProvider: allocationProvider,
                performanceFeePct: performanceFeePct,
                allowRedeemFor: false
            })
        );
    }
}
