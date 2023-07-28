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

contract E2E is ForkTestFixtureDeployment {
    MockAllocationProvider public mockAllocationProvider;

    function setUp() public {
        _deploy();

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

    function test_depositAndWithdraw_dai() public {
        uint256 assetGroupId = _getAssetGroupId(DAI_KEY);
        IERC20 asset = dai;

        address[] memory strategies;
        {
            address aaveV2Strategy = _getStrategyAddress(AAVE_V2_KEY, assetGroupId);
            address compoundV2Strategy = _getStrategyAddress(COMPOUND_V2_KEY, assetGroupId);
            address idleBysStrategy = _getStrategyAddress(IDLE_BEST_YIELD_SENIOR_KEY, assetGroupId);
            address morphoAaveV2Strategy = _getStrategyAddress(MORPHO_AAVE_V2_KEY, assetGroupId);
            address morphoCompoundV2Strategy = _getStrategyAddress(MORPHO_COMPOUND_V2_KEY, assetGroupId);
            address notionalStrategy = _getStrategyAddress(NOTIONAL_FINANCE_KEY, assetGroupId);
            address yearnV2Strategy = _getStrategyAddress(YEARN_V2_KEY, assetGroupId);

            strategies = Arrays.toArray(
                aaveV2Strategy,
                compoundV2Strategy,
                idleBysStrategy,
                morphoAaveV2Strategy,
                morphoCompoundV2Strategy,
                notionalStrategy,
                yearnV2Strategy
            );
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

    function test_depositAndWithdraw_usdc() public {
        uint256 assetGroupId = _getAssetGroupId(USDC_KEY);
        IERC20 asset = usdc;

        address[] memory strategies;
        {
            address aaveV2Strategy = _getStrategyAddress(AAVE_V2_KEY, assetGroupId);
            address compoundV2Strategy = _getStrategyAddress(COMPOUND_V2_KEY, assetGroupId);
            address idleBysStrategy = _getStrategyAddress(IDLE_BEST_YIELD_SENIOR_KEY, assetGroupId);
            address morphoAaveV2Strategy = _getStrategyAddress(MORPHO_AAVE_V2_KEY, assetGroupId);
            address morphoCompoundV2Strategy = _getStrategyAddress(MORPHO_COMPOUND_V2_KEY, assetGroupId);
            address notionalStrategy = _getStrategyAddress(NOTIONAL_FINANCE_KEY, assetGroupId);
            address yearnV2Strategy = _getStrategyAddress(YEARN_V2_KEY, assetGroupId);

            strategies = Arrays.toArray(
                aaveV2Strategy,
                compoundV2Strategy,
                idleBysStrategy,
                morphoAaveV2Strategy,
                morphoCompoundV2Strategy,
                notionalStrategy,
                yearnV2Strategy
            );
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
        _batchBalanceDiffRel(balancesBefore, balancesAfter, depositAmounts, 1e14);
    }

    function test_depositAndWithdraw_usdt() public {
        uint256 assetGroupId = _getAssetGroupId(USDT_KEY);
        IERC20 asset = usdt;

        address[] memory strategies;
        {
            address aaveV2Strategy = _getStrategyAddress(AAVE_V2_KEY, assetGroupId);
            address compoundV2Strategy = _getStrategyAddress(COMPOUND_V2_KEY, assetGroupId);
            address idleBysStrategy = _getStrategyAddress(IDLE_BEST_YIELD_SENIOR_KEY, assetGroupId);
            address morphoAaveV2Strategy = _getStrategyAddress(MORPHO_AAVE_V2_KEY, assetGroupId);
            address morphoCompoundV2Strategy = _getStrategyAddress(MORPHO_COMPOUND_V2_KEY, assetGroupId);
            address yearnV2Strategy = _getStrategyAddress(YEARN_V2_KEY, assetGroupId);

            strategies = Arrays.toArray(
                aaveV2Strategy,
                compoundV2Strategy,
                idleBysStrategy,
                morphoAaveV2Strategy,
                morphoCompoundV2Strategy,
                yearnV2Strategy
            );
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
        _batchBalanceDiffRel(balancesBefore, balancesAfter, depositAmounts, 1e14);
    }

    function test_depositAndWithdraw_weth() public {
        uint256 assetGroupId = _getAssetGroupId(WETH_KEY);
        IERC20 asset = weth;

        address[] memory strategies;
        {
            address rEthHoldingStrategy = _getStrategyAddress(RETH_HOLDING_KEY, assetGroupId);
            address sfrxEthHoldingStrategy = _getStrategyAddress(SFRXETH_HOLDING_KEY, assetGroupId);
            address stEthHoldingStrategy = _getStrategyAddress(STETH_HOLDING_KEY, assetGroupId);

            strategies = Arrays.toArray(rEthHoldingStrategy, sfrxEthHoldingStrategy, stEthHoldingStrategy);
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
        uint256[] memory depositAmounts = Arrays.toArray(1e19, 2e19, 3e19);
        uint256[] memory depositIds = _deposit(vault, users, depositAmounts);
        _flushVaults(vault);

        // DHW
        _dhw(strategies);

        // ASSERT vault asset balances after deposit and DHW
        _assertSmartVaultBalances(vault, depositAmounts, 1e16);

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
        _batchBalanceDiffRel(balancesBefore, balancesAfter, depositAmounts, 1e15);
    }

    function test_depositAndWithdraw_multi_daiUsdcUsdt() public {
        uint256 assetGroupId = _getAssetGroupId(DAI_USDC_USDT_KEY);
        address[] memory assets = _deploySpool.assetGroupRegistry().listAssetGroup(assetGroupId);

        address[] memory strategies;
        {
            address convex3poolStrategy = _getStrategyAddress(CONVEX_3POOL_KEY, assetGroupId);
            address convexAlusdStrategy = _getStrategyAddress(CONVEX_ALUSD_KEY, assetGroupId);
            address curve3poolStrategy = _getStrategyAddress(CURVE_3POOL_KEY, assetGroupId);

            strategies = Arrays.toArray(convex3poolStrategy, convexAlusdStrategy, curve3poolStrategy);
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
        (uint256[] memory depositIds, uint256[][] memory depositAmounts) =
            _depositInRatio(vault, users, Arrays.toArray(1e21, 2e21, 3e21));
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

    function test_reallocate_dai() public {
        uint256 assetGroupId = _getAssetGroupId(DAI_KEY);

        address aaveV2Strategy = _getStrategyAddress(AAVE_V2_KEY, assetGroupId);
        address compoundV2Strategy = _getStrategyAddress(COMPOUND_V2_KEY, assetGroupId);
        address idleBysStrategy = _getStrategyAddress(IDLE_BEST_YIELD_SENIOR_KEY, assetGroupId);
        address morphoAaveV2Strategy = _getStrategyAddress(MORPHO_AAVE_V2_KEY, assetGroupId);
        address morphoCompoundV2Strategy = _getStrategyAddress(MORPHO_COMPOUND_V2_KEY, assetGroupId);
        address notionalStrategy = _getStrategyAddress(NOTIONAL_FINANCE_KEY, assetGroupId);
        address yearnV2Strategy = _getStrategyAddress(YEARN_V2_KEY, assetGroupId);

        address[] memory strategies = Arrays.toArray(
            aaveV2Strategy,
            compoundV2Strategy,
            idleBysStrategy,
            morphoAaveV2Strategy,
            morphoCompoundV2Strategy,
            notionalStrategy,
            yearnV2Strategy
        );

        _setRandomRiskScores(strategies);

        mockAllocationProvider.setWeight(aaveV2Strategy, 20);
        mockAllocationProvider.setWeight(compoundV2Strategy, 20);
        mockAllocationProvider.setWeight(idleBysStrategy, 20);
        mockAllocationProvider.setWeight(morphoAaveV2Strategy, 10);
        mockAllocationProvider.setWeight(morphoCompoundV2Strategy, 10);
        mockAllocationProvider.setWeight(notionalStrategy, 10);
        mockAllocationProvider.setWeight(yearnV2Strategy, 10);

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
        mockAllocationProvider.setWeight(aaveV2Strategy, 10);
        mockAllocationProvider.setWeight(compoundV2Strategy, 15);
        mockAllocationProvider.setWeight(idleBysStrategy, 15);
        mockAllocationProvider.setWeight(morphoAaveV2Strategy, 15);
        mockAllocationProvider.setWeight(morphoCompoundV2Strategy, 15);
        mockAllocationProvider.setWeight(notionalStrategy, 15);
        mockAllocationProvider.setWeight(yearnV2Strategy, 15);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 1e7);

        // advance block number
        vm.roll(block.number + 1);

        // REALLOCATE BACK
        mockAllocationProvider.setWeight(aaveV2Strategy, 20);
        mockAllocationProvider.setWeight(compoundV2Strategy, 20);
        mockAllocationProvider.setWeight(idleBysStrategy, 20);
        mockAllocationProvider.setWeight(morphoAaveV2Strategy, 10);
        mockAllocationProvider.setWeight(morphoCompoundV2Strategy, 10);
        mockAllocationProvider.setWeight(notionalStrategy, 10);
        mockAllocationProvider.setWeight(yearnV2Strategy, 10);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 1e12);
    }

    function test_reallocate_usdc() public {
        uint256 assetGroupId = _getAssetGroupId(USDC_KEY);

        address aaveV2Strategy = _getStrategyAddress(AAVE_V2_KEY, assetGroupId);
        address compoundV2Strategy = _getStrategyAddress(COMPOUND_V2_KEY, assetGroupId);
        address idleBysStrategy = _getStrategyAddress(IDLE_BEST_YIELD_SENIOR_KEY, assetGroupId);
        address morphoAaveV2Strategy = _getStrategyAddress(MORPHO_AAVE_V2_KEY, assetGroupId);
        address morphoCompoundV2Strategy = _getStrategyAddress(MORPHO_COMPOUND_V2_KEY, assetGroupId);
        address notionalStrategy = _getStrategyAddress(NOTIONAL_FINANCE_KEY, assetGroupId);
        address yearnV2Strategy = _getStrategyAddress(YEARN_V2_KEY, assetGroupId);

        address[] memory strategies = Arrays.toArray(
            aaveV2Strategy,
            compoundV2Strategy,
            idleBysStrategy,
            morphoAaveV2Strategy,
            morphoCompoundV2Strategy,
            notionalStrategy,
            yearnV2Strategy
        );

        _setRandomRiskScores(strategies);

        mockAllocationProvider.setWeight(aaveV2Strategy, 20);
        mockAllocationProvider.setWeight(compoundV2Strategy, 20);
        mockAllocationProvider.setWeight(idleBysStrategy, 20);
        mockAllocationProvider.setWeight(morphoAaveV2Strategy, 10);
        mockAllocationProvider.setWeight(morphoCompoundV2Strategy, 10);
        mockAllocationProvider.setWeight(notionalStrategy, 10);
        mockAllocationProvider.setWeight(yearnV2Strategy, 10);

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

        _assertAllocationApproxRel(vault, 1e12);

        // REALLOCATE
        mockAllocationProvider.setWeight(aaveV2Strategy, 10);
        mockAllocationProvider.setWeight(compoundV2Strategy, 15);
        mockAllocationProvider.setWeight(idleBysStrategy, 15);
        mockAllocationProvider.setWeight(morphoAaveV2Strategy, 15);
        mockAllocationProvider.setWeight(morphoCompoundV2Strategy, 15);
        mockAllocationProvider.setWeight(notionalStrategy, 15);
        mockAllocationProvider.setWeight(yearnV2Strategy, 15);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 4e11);

        // advance block number
        vm.roll(block.number + 1);

        // REALLOCATE BACK
        mockAllocationProvider.setWeight(aaveV2Strategy, 20);
        mockAllocationProvider.setWeight(compoundV2Strategy, 20);
        mockAllocationProvider.setWeight(idleBysStrategy, 20);
        mockAllocationProvider.setWeight(morphoAaveV2Strategy, 10);
        mockAllocationProvider.setWeight(morphoCompoundV2Strategy, 10);
        mockAllocationProvider.setWeight(notionalStrategy, 10);
        mockAllocationProvider.setWeight(yearnV2Strategy, 10);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 3e12);
    }

    function test_reallocate_usdt() public {
        uint256 assetGroupId = _getAssetGroupId(USDT_KEY);

        address aaveV2Strategy = _getStrategyAddress(AAVE_V2_KEY, assetGroupId);
        address compoundV2Strategy = _getStrategyAddress(COMPOUND_V2_KEY, assetGroupId);
        address idleBysStrategy = _getStrategyAddress(IDLE_BEST_YIELD_SENIOR_KEY, assetGroupId);
        address morphoAaveV2Strategy = _getStrategyAddress(MORPHO_AAVE_V2_KEY, assetGroupId);
        address morphoCompoundV2Strategy = _getStrategyAddress(MORPHO_COMPOUND_V2_KEY, assetGroupId);
        address yearnV2Strategy = _getStrategyAddress(YEARN_V2_KEY, assetGroupId);

        address[] memory strategies = Arrays.toArray(
            aaveV2Strategy,
            compoundV2Strategy,
            idleBysStrategy,
            morphoAaveV2Strategy,
            morphoCompoundV2Strategy,
            yearnV2Strategy
        );

        _setRandomRiskScores(strategies);

        mockAllocationProvider.setWeight(aaveV2Strategy, 25);
        mockAllocationProvider.setWeight(compoundV2Strategy, 25);
        mockAllocationProvider.setWeight(idleBysStrategy, 20);
        mockAllocationProvider.setWeight(morphoAaveV2Strategy, 10);
        mockAllocationProvider.setWeight(morphoCompoundV2Strategy, 10);
        mockAllocationProvider.setWeight(yearnV2Strategy, 10);

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

        _assertAllocationApproxRel(vault, 1e12);

        // REALLOCATE
        mockAllocationProvider.setWeight(aaveV2Strategy, 15);
        mockAllocationProvider.setWeight(compoundV2Strategy, 15);
        mockAllocationProvider.setWeight(idleBysStrategy, 15);
        mockAllocationProvider.setWeight(morphoAaveV2Strategy, 15);
        mockAllocationProvider.setWeight(morphoCompoundV2Strategy, 20);
        mockAllocationProvider.setWeight(yearnV2Strategy, 20);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 3e11);

        // advance block number
        vm.roll(block.number + 1);

        // REALLOCATE BACK
        mockAllocationProvider.setWeight(aaveV2Strategy, 25);
        mockAllocationProvider.setWeight(compoundV2Strategy, 25);
        mockAllocationProvider.setWeight(idleBysStrategy, 20);
        mockAllocationProvider.setWeight(morphoAaveV2Strategy, 10);
        mockAllocationProvider.setWeight(morphoCompoundV2Strategy, 10);
        mockAllocationProvider.setWeight(yearnV2Strategy, 10);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 1e11);
    }

    function test_reallocate_weth() public {
        uint256 assetGroupId = _getAssetGroupId(WETH_KEY);

        address rEthHoldingStrategy = _getStrategyAddress(RETH_HOLDING_KEY, assetGroupId);
        address sfrxEthHoldingStrategy = _getStrategyAddress(SFRXETH_HOLDING_KEY, assetGroupId);
        address stEthHoldingStrategy = _getStrategyAddress(STETH_HOLDING_KEY, assetGroupId);

        address[] memory strategies = Arrays.toArray(rEthHoldingStrategy, sfrxEthHoldingStrategy, stEthHoldingStrategy);

        _setRandomRiskScores(strategies);

        mockAllocationProvider.setWeight(rEthHoldingStrategy, 40);
        mockAllocationProvider.setWeight(sfrxEthHoldingStrategy, 40);
        mockAllocationProvider.setWeight(stEthHoldingStrategy, 20);

        ISmartVault vault =
            _createVault(0, 0, assetGroupId, strategies, uint16a16.wrap(0), address(mockAllocationProvider));

        address alice = address(0xa);

        _dealTokens(alice);

        // DEPOSIT
        uint256 depositAmount = 10 ** 19;
        _deposit(vault, alice, depositAmount);

        // FLUSH
        _flushVaults(vault);

        // DHW
        _dhw(strategies);

        // SYNC
        _syncVaults(vault);

        // advance block number
        vm.roll(block.number + 1);

        _assertAllocationApproxRel(vault, 1e16);

        // REALLOCATE
        mockAllocationProvider.setWeight(rEthHoldingStrategy, 30);
        mockAllocationProvider.setWeight(sfrxEthHoldingStrategy, 30);
        mockAllocationProvider.setWeight(stEthHoldingStrategy, 40);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 3e15);

        // advance block number
        vm.roll(block.number + 1);

        // REALLOCATE
        mockAllocationProvider.setWeight(rEthHoldingStrategy, 40);
        mockAllocationProvider.setWeight(sfrxEthHoldingStrategy, 40);
        mockAllocationProvider.setWeight(stEthHoldingStrategy, 20);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 3e15);
    }

    function test_reallocate_multi_daiUsdcUsdt() public {
        uint256 assetGroupId = _getAssetGroupId(DAI_USDC_USDT_KEY);

        address convex3poolStrategy = _getStrategyAddress(CONVEX_3POOL_KEY, assetGroupId);
        address convexAlusdStrategy = _getStrategyAddress(CONVEX_ALUSD_KEY, assetGroupId);
        address curve3poolStrategy = _getStrategyAddress(CURVE_3POOL_KEY, assetGroupId);

        address[] memory strategies = Arrays.toArray(convex3poolStrategy, convexAlusdStrategy, curve3poolStrategy);

        _setRandomRiskScores(strategies);
        mockAllocationProvider.setWeight(convex3poolStrategy, 40);
        mockAllocationProvider.setWeight(convexAlusdStrategy, 40);
        mockAllocationProvider.setWeight(curve3poolStrategy, 20);

        ISmartVault vault =
            _createVault(0, 0, assetGroupId, strategies, uint16a16.wrap(0), address(mockAllocationProvider));

        address alice = address(0xa);

        _dealTokens(alice);

        // DEPOSIT
        uint256 depositAmount = 10 ** 21;
        _depositInRatio(vault, alice, depositAmount);

        // FLUSH
        _flushVaults(vault);

        // DHW
        _dhw(strategies);

        // SYNC
        _syncVaults(vault);

        // advance block number
        vm.roll(block.number + 1);

        _assertAllocationApproxRel(vault, 1e15);

        // REALLOCATE
        mockAllocationProvider.setWeight(convex3poolStrategy, 30);
        mockAllocationProvider.setWeight(convexAlusdStrategy, 30);
        mockAllocationProvider.setWeight(curve3poolStrategy, 40);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 2e11);

        // advance block number
        vm.roll(block.number + 1);

        // REALLOCATE BACK
        mockAllocationProvider.setWeight(convex3poolStrategy, 40);
        mockAllocationProvider.setWeight(convexAlusdStrategy, 40);
        mockAllocationProvider.setWeight(curve3poolStrategy, 20);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 1e14);
    }
}
