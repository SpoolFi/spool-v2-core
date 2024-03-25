// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../../../../src/interfaces/Constants.sol";
import "../../../../src/strategies/arbitrum/AaveV3Strategy.sol";
import "../../../../src/strategies/arbitrum/CompoundV3Strategy.sol";
import "../../../libraries/Arrays.sol";
import "../../../libraries/Constants.sol";
import "../../../fixtures/TestFixture.sol";
import "../../../mocks/MockAllocationProvider.sol";
import "../ForkTestFixtureDeployment.sol";

contract E2E is ForkTestFixtureDeployment {
    MockAllocationProvider public mockAllocationProvider;

    function _setConfig() internal override {
        config = vm.readFile("deploy/arbitrum.constants.json");
    }

    function setUp() public {
        _deploy();

        mockAllocationProvider = new MockAllocationProvider();
        vm.startPrank(_spoolAdmin);
        _deploySpool.spoolAccessControl().grantRole(ROLE_ALLOCATION_PROVIDER, address(mockAllocationProvider));
        vm.stopPrank();
    }

    function test_deploySpool() public {
        uint256 assetGroupIdUSDC = _getAssetGroupId(USDC_KEY);

        address aaveStrategy = _getStrategyAddress(AAVE_V3_KEY, assetGroupIdUSDC);
        address compoundStrategy = _getStrategyAddress(COMPOUND_V3_KEY, assetGroupIdUSDC);

        address[] memory strategies = Arrays.toArray(aaveStrategy, compoundStrategy);

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

    function test_depositAndWithdraw_usdc() public {
        uint256 assetGroupId = _getAssetGroupId(USDC_KEY);
        IERC20 asset = usdc;

        address[] memory strategies;
        {
            address aaveStrategy = _getStrategyAddress(AAVE_V3_KEY, assetGroupId);
            address compoundStrategy = _getStrategyAddress(COMPOUND_V3_KEY, assetGroupId);
            address aaveSwapStrategy = _getStrategyAddress(AAVE_V3_SWAP_KEY, assetGroupId);
            address compoundSwapStrategy = _getStrategyAddress(COMPOUND_V3_SWAP_KEY, assetGroupId);

            strategies = Arrays.toArray(aaveStrategy, compoundStrategy, aaveSwapStrategy, compoundSwapStrategy);
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
        uint256[] memory depositAmounts = Arrays.toArray(10 ** 10, 2 * 10 ** 10, 3 * 10 ** 10);
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
        _batchBalanceDiffRel(balancesBefore, balancesAfter, depositAmounts, 2e14);
    }

    function test_depositAndWithdraw_multi_wethUsdc() public {
        uint256 assetGroupId = _getAssetGroupId(WETH_USDC_KEY);
        address[] memory assets = _deploySpool.assetGroupRegistry().listAssetGroup(assetGroupId);

        address[] memory strategies;
        {
            address gammaCamelotStrategy = _getStrategyAddress(GAMMA_CAMELOT_KEY, assetGroupId);

            strategies = Arrays.toArray(gammaCamelotStrategy);
        }

        _setRandomRiskScores(strategies);

        ISmartVault vault = _createVault(0, 0, assetGroupId, strategies, uint16a16.wrap(FULL_PERCENT), address(0));

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

        uint256[] memory amounts = Arrays.toArray(1e21, 2e21, 3e21);

        uint256[] memory assetRatio = _getDepositRatio(vault);

        uint256[][] memory depositAmounts = new uint256[][](amounts.length);
        for (uint256 i; i < amounts.length; ++i) {
            depositAmounts[i] = new uint256[](assetRatio.length);

            depositAmounts[i][0] = assetRatio[0] / 1000000;
            depositAmounts[i][1] = assetRatio[1] / 1000000;
        }

        uint256[] memory depositIds = _deposit(vault, users, depositAmounts);

        _flushVaults(vault);

        // DHW
        _dhw(strategies);

        // ASSERT vault asset balances after deposit and DHW
        _assertSmartVaultBalances(vault, depositAmounts, 1e15);

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
        uint256[][] memory balancesBefore = _getBalances(users, assets);
        _claimWithdrawals(vault, withdrawalUsers, withdrawalIds);

        // REDEEM FAST
        _redeemFast(vault, carol, depositIds[2]);

        // ASSERT
        uint256[][] memory balancesAfter = _getBalances(users, assets);
        _batchBalanceDiffRel(balancesBefore, balancesAfter, depositAmounts, 2e14);
    }

    function test_reallocate_usdc() public {
        uint256 assetGroupId = _getAssetGroupId(USDC_KEY);

        address aaveStrategy = _getStrategyAddress(AAVE_V3_KEY, assetGroupId);
        address compoundStrategy = _getStrategyAddress(COMPOUND_V3_KEY, assetGroupId);
        address aaveSwapStrategy = _getStrategyAddress(AAVE_V3_SWAP_KEY, assetGroupId);
        address compoundSwapStrategy = _getStrategyAddress(COMPOUND_V3_SWAP_KEY, assetGroupId);

        address[] memory strategies =
            Arrays.toArray(aaveStrategy, compoundStrategy, aaveSwapStrategy, compoundSwapStrategy);

        _setRandomRiskScores(strategies);

        mockAllocationProvider.setWeight(aaveStrategy, 30);
        mockAllocationProvider.setWeight(compoundStrategy, 30);
        mockAllocationProvider.setWeight(aaveSwapStrategy, 20);
        mockAllocationProvider.setWeight(compoundSwapStrategy, 20);

        ISmartVault vault =
            _createVault(0, 0, assetGroupId, strategies, uint16a16.wrap(0), address(mockAllocationProvider));

        address alice = address(0xa);

        _dealTokens(alice);

        // DEPOSIT
        uint256 depositAmount = 10 ** 10;
        _deposit(vault, alice, depositAmount);

        // FLUSH
        _flushVaults(vault);

        // DHW
        _dhw(strategies);

        // SYNC
        _syncVaults(vault);

        // advance block number
        vm.roll(block.number + 1);

        _assertAllocationApproxRel(vault, 2e14);

        // REALLOCATE
        mockAllocationProvider.setWeight(aaveStrategy, 20);
        mockAllocationProvider.setWeight(compoundStrategy, 20);
        mockAllocationProvider.setWeight(aaveSwapStrategy, 30);
        mockAllocationProvider.setWeight(compoundSwapStrategy, 30);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 4e13);

        // advance block number
        vm.roll(block.number + 1);

        // REALLOCATE BACK
        mockAllocationProvider.setWeight(aaveStrategy, 30);
        mockAllocationProvider.setWeight(compoundStrategy, 30);
        mockAllocationProvider.setWeight(aaveSwapStrategy, 20);
        mockAllocationProvider.setWeight(compoundSwapStrategy, 20);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 3e12);
    }
}
