// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../../../src/interfaces/Constants.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../../mocks/MockAllocationProvider.sol";
import "../ForkTestFixtureDeployment.sol";

contract E2eMainnetMetamorphoWBTCTest is ForkTestFixtureDeployment {
    MockAllocationProvider public mockAllocationProvider;

    string constant METAMORPHO_GAUNTLET_WBTC_KEY = "metamorpho-gauntlet-wbtc-core";
    string constant METAMORPHO_RE7_WBTC_KEY = "metamorpho-re7-wbtc";
    string constant METAMORPHO_MEV_CAPITAL_WBTC_KEY = "metamorpho-mev-capital-wbtc";

    function setUpForkTestFixture() internal override {
        mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK_EXTENDED_6);
    }

    function setUp() public {
        _deploy(Extended.METAMORPHO_ROUND_2);

        mockAllocationProvider = new MockAllocationProvider();
        vm.startPrank(_spoolAdmin);
        _deploySpool.spoolAccessControl().grantRole(ROLE_ALLOCATION_PROVIDER, address(mockAllocationProvider));
        vm.stopPrank();
    }

    function test_depositAndWithdraw_wbtc() public {
        uint256 assetGroupId = _getAssetGroupId(WBTC_KEY);
        IERC20 asset = wbtc;

        address[] memory strategies;
        {
            address strategyA = _getStrategyAddress(METAMORPHO_GAUNTLET_WBTC_KEY, assetGroupId);
            address strategyB = _getStrategyAddress(METAMORPHO_RE7_WBTC_KEY, assetGroupId);

            strategies = Arrays.toArray(strategyA, strategyB);
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
        uint256[] memory depositAmounts = Arrays.toArray(10 ** 11, 2 * 10 ** 11, 3 * 10 ** 11);
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

    function test_reallocate_wbtc() public {
        uint256 assetGroupId = _getAssetGroupId(WBTC_KEY);

        address strategyA = _getStrategyAddress(METAMORPHO_RE7_WBTC_KEY, assetGroupId);
        address strategyB = _getStrategyAddress(METAMORPHO_MEV_CAPITAL_WBTC_KEY, assetGroupId);

        address[] memory strategies = Arrays.toArray(strategyA, strategyB);

        _setRandomRiskScores(strategies);

        mockAllocationProvider.setWeight(strategyA, 60);
        mockAllocationProvider.setWeight(strategyB, 40);

        ISmartVault vault =
            _createVault(0, 0, assetGroupId, strategies, uint16a16.wrap(0), address(mockAllocationProvider));

        address alice = address(0xa);

        _dealTokens(alice);

        // DEPOSIT
        uint256 depositAmount = 10 ** 11;
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
        mockAllocationProvider.setWeight(strategyA, 10);
        mockAllocationProvider.setWeight(strategyB, 90);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 1e8);

        // advance block number
        vm.roll(block.number + 1);

        // REALLOCATE BACK
        mockAllocationProvider.setWeight(strategyA, 40);
        mockAllocationProvider.setWeight(strategyB, 60);

        _reallocate(vault);

        _assertAllocationApproxRel(vault, 1e12);
    }
}
