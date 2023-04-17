// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../../../src/interfaces/Constants.sol";
import "../../../src/strategies/AaveV2Strategy.sol";
import "../../../src/strategies/CompoundV2Strategy.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../../fixtures/TestFixture.sol";
import "../ForkTestFixtureDeployment.sol";

contract E2E is ForkTestFixtureDeployment {
    function setUp() public {
        _deploy();
    }

    function test_deploySpool() public {
        vm.startPrank(_spoolAdmin);

        uint256 assetGroupIdUSDC = _deploySpool.assetGroups("usdc");

        ILendingPoolAddressesProvider lendingPoolAddressesProvider =
            ILendingPoolAddressesProvider(AAVE_V2_LENDING_POOL_ADDRESSES_PROVIDER);

        AaveV2Strategy aaveStrategy = new AaveV2Strategy(
            _deploySpool.assetGroupRegistry(),
            _deploySpool.spoolAccessControl(),
            lendingPoolAddressesProvider
        );

        aaveStrategy.initialize("AAVE-v2-USDC-strategy", assetGroupIdUSDC);
        _deploySpool.strategyRegistry().registerStrategy(address(aaveStrategy), 1);

        CompoundV2Strategy compoundV2Strategy = new CompoundV2Strategy(
            _deploySpool.assetGroupRegistry(),
            _deploySpool.spoolAccessControl(),
            _deploySpool.swapper(),
            IComptroller(COMPTROLLER)
        );

        compoundV2Strategy.initialize("Compound-v2-USDC-strategy", assetGroupIdUSDC, ICErc20(cUSDC));
        _deploySpool.strategyRegistry().registerStrategy(address(compoundV2Strategy), 2);

        vm.stopPrank();

        address[] memory strategies = Arrays.toArray(address(aaveStrategy), address(compoundV2Strategy));

        uint16a16 allocations = uint16a16Lib.set(uint16a16.wrap(0), Arrays.toArray(1, 2));
        ISmartVault vault = _createVault(0, 0, assetGroupIdUSDC, strategies, allocations);

        address alice = address(0xa);
        _dealTokens(alice);

        // DEPOSIT
        uint256 depositAmount = 10 ** 10;
        uint256 depositId = _deposit(vault, alice, depositAmount);
        _flushVaults(vault);

        // DHW
        _dhw(strategies);

        // WITHDRAWAL
        uint256 withdrawalId = _redeemNft(vault, alice, depositId);
        _flushVaults(vault);

        // DHW
        _dhw(strategies);

        // CLAIM
        uint256 balanceBefore = usdc.balanceOf(alice);
        _claimWithdrawal(vault, alice, withdrawalId);
        uint256 balanceAfter = usdc.balanceOf(alice);

        assertApproxEqAbs(balanceAfter - balanceBefore, depositAmount, 1);
    }
}
