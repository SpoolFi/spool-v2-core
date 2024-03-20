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

        address aaveStrategy = _getStrategyAddress(AAVE_V3_AUSDC_KEY, assetGroupIdUSDC);
        address compoundStrategy = _getStrategyAddress(COMPOUND_V3_CUSDC_KEY, assetGroupIdUSDC);

        address[] memory strategies = Arrays.toArray(aaveStrategy, compoundStrategy);

        uint16a16 allocations = uint16a16Lib.set(uint16a16.wrap(0), Arrays.toArray(FULL_PERCENT / 2, FULL_PERCENT / 2));
        console.log("create vault..");
        ISmartVault vault = _createVault(0, 0, assetGroupIdUSDC, strategies, allocations, address(0));

        address alice = address(0xa);
        console.log("deal tokens..");
        _dealTokens(alice);

        // DEPOSIT
        uint256 depositAmount = 10 ** 10;
        console.log("deposit..");
        uint256 depositId = _deposit(vault, alice, depositAmount);
        console.log("flush valuts..");
        _flushVaults(vault);

        // DHW
        console.log("dhw..");
        _dhw(strategies);

        // WITHDRAWAL
        console.log("redeem nfts..");
        uint256 withdrawalId = _redeemNfts(vault, alice, depositId);
        _flushVaults(vault);

        // DHW
        console.log("dhw..");
        _dhw(strategies);

        // CLAIM
        uint256 balanceBefore = usdc.balanceOf(alice);
        console.log("claim withdrawals..");
        _claimWithdrawals(vault, alice, withdrawalId);
        uint256 balanceAfter = usdc.balanceOf(alice);

        console.log("assert..");
        assertApproxEqAbs(balanceAfter - balanceBefore, depositAmount, 3);
    }

    function test_depositAndWithdraw_usdc() public {
        uint256 assetGroupId = _getAssetGroupId(USDC_KEY);
        IERC20 asset = usdc;

        address[] memory strategies;
        {
            address aaveAusdcStrategy = _getStrategyAddress(AAVE_V3_AUSDC_KEY, assetGroupId);
            address compoundCusdcStrategy = _getStrategyAddress(COMPOUND_V3_CUSDC_KEY, assetGroupId);
            address aaveAusdceStrategy = _getStrategyAddress(AAVE_V3_AUSDCE_KEY, assetGroupId);
            address compoundCusdceStrategy = _getStrategyAddress(COMPOUND_V3_CUSDCE_KEY, assetGroupId);

            strategies = Arrays.toArray(
                aaveAusdcStrategy,
                compoundCusdcStrategy,
                aaveAusdceStrategy,
                compoundCusdceStrategy
            );
        }

        _setRandomRiskScores(strategies);
        
        console.log("create vault..");
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

        console.log("deal tokens..");
        _dealTokens(users);

        // DEPOSIT
        uint256[] memory depositAmounts = Arrays.toArray(10 ** 10, 2 * 10 ** 10, 3 * 10 ** 10);
        uint256[] memory depositIds = _deposit(vault, users, depositAmounts);
        console.log("flush vaults..");
        _flushVaults(vault);

        // DHW
        console.log("dhw..");
        _dhw(strategies);

        // ASSERT vault asset balances after deposit and DHW
        console.log("assert smart vault balances..");
        _assertSmartVaultBalances(vault, depositAmounts, 1e14);

        // advance block number between deposit and withdrawal
        vm.roll(block.number + 1);

        // WITHDRAWAL
        address[] memory withdrawalUsers = Arrays.toArray(users[0], users[1]);
        console.log("redeem nfts..");
        uint256[] memory withdrawalIds =
            _redeemNfts(vault, withdrawalUsers, Arrays.toArray(depositIds[0], depositIds[1]));
        console.log("flush vaults..");
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

    function test_depositAndWithdraw_multi_wethUsdc() public {
        uint256 assetGroupId = _getAssetGroupId(WETH_USDC_KEY);
        address[] memory assets = _deploySpool.assetGroupRegistry().listAssetGroup(assetGroupId);

        address[] memory strategies;
        {
            address gammaCamelotStrategy = _getStrategyAddress(GAMMA_CAMELOT_KEY, assetGroupId);

            strategies = Arrays.toArray(gammaCamelotStrategy);
        }

        _setRandomRiskScores(strategies);

        ISmartVault vault = _createVault(
            0, 0, assetGroupId, strategies, uint16a16.wrap(1), address(_deploySpool.uniformAllocationProvider())
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

    function test_reallocate_usdc() public {
        uint256 assetGroupId = _getAssetGroupId(USDC_KEY);

        address aaveAusdcStrategy      = _getStrategyAddress(AAVE_V3_AUSDC_KEY, assetGroupId);
        address compoundCusdcStrategy  = _getStrategyAddress(COMPOUND_V3_CUSDC_KEY, assetGroupId);
        address aaveAusdceStrategy     = _getStrategyAddress(AAVE_V3_AUSDCE_KEY, assetGroupId);
        address compoundCusdceStrategy = _getStrategyAddress(COMPOUND_V3_CUSDCE_KEY, assetGroupId);

        address[] memory strategies = Arrays.toArray(
            aaveAusdcStrategy,
            compoundCusdcStrategy,
            aaveAusdceStrategy,
            compoundCusdceStrategy
        );

        _setRandomRiskScores(strategies);

        mockAllocationProvider.setWeight(aaveAusdcStrategy, 30);
        mockAllocationProvider.setWeight(compoundCusdcStrategy, 30);
        mockAllocationProvider.setWeight(aaveAusdceStrategy, 20);
        mockAllocationProvider.setWeight(compoundCusdceStrategy, 20);

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
        mockAllocationProvider.setWeight(aaveAusdcStrategy, 20);
        mockAllocationProvider.setWeight(compoundCusdcStrategy, 20);
        mockAllocationProvider.setWeight(aaveAusdceStrategy, 30);
        mockAllocationProvider.setWeight(compoundCusdceStrategy, 30);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 4e11);

        // advance block number
        vm.roll(block.number + 1);

        // REALLOCATE BACK
        mockAllocationProvider.setWeight(aaveAusdcStrategy, 30);
        mockAllocationProvider.setWeight(compoundCusdcStrategy, 30);
        mockAllocationProvider.setWeight(aaveAusdceStrategy, 20);
        mockAllocationProvider.setWeight(compoundCusdceStrategy, 20);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 3e12);
    }
}
