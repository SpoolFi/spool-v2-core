// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../../../src/interfaces/Constants.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../../mocks/MockAllocationProvider.sol";
import "../ForkTestFixtureDeployment.sol";

contract E2E_YearnV3 is ForkTestFixtureDeployment {
    MockAllocationProvider public mockAllocationProvider;

    function setUpForkTestFixture() internal override {
        mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK_EXTENDED_2);
    }

    function setUp() public {
        _deploy(4);

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

        assertApproxEqAbs(balanceAfter - balanceBefore, depositAmount, 3);
    }

    function test_depositAndWithdraw_dai() public {
        uint256 assetGroupId = _getAssetGroupId(DAI_KEY);
        IERC20 asset = dai;

        address[] memory strategies;
        {
            address yearnV3Strategy = _getStrategyAddress(YEARN_V3_GAUGED_KEY, assetGroupId);
            address aaveV2Strategy = _getStrategyAddress(AAVE_V2_KEY, assetGroupId);
            address yearnV3Juiced = _getStrategyAddress(YEARN_V3_JUICED_KEY, assetGroupId);

            strategies = Arrays.toArray(yearnV3Strategy, aaveV2Strategy, yearnV3Juiced);
        }

        _setRandomRiskScores(strategies);

        ISmartVault vault = _createVault(
            0, 0, assetGroupId, strategies, uint16a16.wrap(0), address(_deploySpool.uniformAllocationProvider())
        );

        address[] memory users;
        address carol;
        {
            address alice = address(0xa);
            address bob = address(0xb);
            carol = address(0xc);

            users = Arrays.toArray(alice, bob, carol);
            _verifyUniqueAddresses(users);
        }

        _dealTokens(users);

        // DEPOSIT
        uint256[] memory depositAmounts = Arrays.toArray(10 ** 21, 2 * 10 ** 21, 3 * 10 ** 21);
        uint256[] memory depositIds = _deposit(vault, users, depositAmounts);
        _flushVaults(vault);

        // DHW
        _dhw(strategies);

        // ASSERT vault asset balances after deposit and DHW
        _assertSmartVaultBalances(vault, depositAmounts, 1e14);

        // advance block number between deposit and withdrawal
        vm.roll(block.number + 1);

        // WITHDRAWAL
        address[] memory withdrawalUsers = Arrays.toArray(users[0], users[1]);
        uint256[] memory withdrawalIds =
            _redeemNfts(vault, withdrawalUsers, Arrays.toArray(depositIds[0], depositIds[1]));
        _flushVaults(vault);

        // DHW
        _dhw(strategies);

        // CLAIM
        uint256[] memory balancesBefore = _getBalances(users, asset);
        _claimWithdrawals(vault, withdrawalUsers, withdrawalIds);

        // REDEEM FAST
        _redeemFast(vault, carol, depositIds[2]);

        // ASSERT
        uint256[] memory balancesAfter = _getBalances(users, asset);
        _batchBalanceDiffRel(balancesBefore, balancesAfter, depositAmounts, 1e14);
    }

    function test_reallocate_dai() public {
        uint256 assetGroupId = _getAssetGroupId(DAI_KEY);

        address yearnV3Strategy = _getStrategyAddress(YEARN_V3_GAUGED_KEY, assetGroupId);
        address aaveV2Strategy = _getStrategyAddress(AAVE_V2_KEY, assetGroupId);
        address yearnV3Juiced = _getStrategyAddress(YEARN_V3_JUICED_KEY, assetGroupId);

        address[] memory strategies = Arrays.toArray(yearnV3Strategy, aaveV2Strategy, yearnV3Juiced);

        _setRandomRiskScores(strategies);

        mockAllocationProvider.setWeight(yearnV3Strategy, 20);
        mockAllocationProvider.setWeight(aaveV2Strategy, 50);
        mockAllocationProvider.setWeight(yearnV3Juiced, 30);

        ISmartVault vault =
            _createVault(0, 0, assetGroupId, strategies, uint16a16.wrap(0), address(mockAllocationProvider));

        address alice = address(0xa);

        _dealTokens(alice);

        // DEPOSIT
        uint256 depositAmount = 10 ** 21;
        _deposit(vault, alice, depositAmount);

        // FLUSH
        _flushVaults(vault);

        // DHW
        _dhw(strategies);

        // SYNC
        _syncVaults(vault);

        // advance block number
        vm.roll(block.number + 1);

        _assertAllocationApproxRel(vault, 1e10);

        // REALLOCATE
        mockAllocationProvider.setWeight(yearnV3Strategy, 50);
        mockAllocationProvider.setWeight(aaveV2Strategy, 40);
        mockAllocationProvider.setWeight(yearnV3Juiced, 10);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 1e7);

        // advance block number
        vm.roll(block.number + 1);

        // REALLOCATE BACK
        mockAllocationProvider.setWeight(yearnV3Strategy, 20);
        mockAllocationProvider.setWeight(aaveV2Strategy, 50);
        mockAllocationProvider.setWeight(yearnV3Juiced, 30);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 1e12);
    }
}
