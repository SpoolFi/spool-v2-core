// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/utils/Strings.sol";
import "../../src/interfaces/Constants.sol";
import "../../src/SmartVaultFactory.sol";
import "../../src/external/interfaces/chainlink/AggregatorV3Interface.sol";
import "../../script/mainnet/MainnetInitialSetup.s.sol";
import "../libraries/Arrays.sol";
import "./ForkTestFixture.sol";
import "../libraries/TimeUtils.sol";
import "../libraries/VaultValueHelpers.sol";

string constant TEST_CONSTANTS_PATH = "deploy/fork-test-mainnet.constants.json";
string constant TEST_CONTRACTS_PATH = "deploy/fork-test-mainnet.contracts.json";

contract TestMainnetInitialSetup is MainnetInitialSetup {
    function init() public virtual override {
        _constantsJson = new JsonReader(vm, TEST_CONSTANTS_PATH);
        _contractsJson = new JsonReadWriter(vm, TEST_CONTRACTS_PATH);
    }

    function postDeploySpool(address deployerAddress) public override {
        {
            // transfer ownership of ProxyAdmin
            address proxyAdminOwner = constantsJson().getAddress(".proxyAdminOwner");
            proxyAdmin.transferOwnership(proxyAdminOwner);

            // transfer ROLE_SPOOL_ADMIN
            address spoolAdmin = constantsJson().getAddress(".spoolAdmin");
            spoolAccessControl.grantRole(ROLE_SPOOL_ADMIN, spoolAdmin);
        }

        spoolAccessControl.renounceRole(ROLE_SPOOL_ADMIN, deployerAddress);
    }

    function test_mock_TestMainnetInitialSetup() external pure {}
}

struct DoHardWorkStrategyParameters {
    SwapInfo[] swapInfo;
    SwapInfo[] compoundSwapInfo;
    uint256[] strategySlippages;
    int256 baseYields;
}

abstract contract ForkTestFixtureDeployment is ForkTestFixture {
    using uint16a16Lib for uint16a16;
    using SafeERC20 for IERC20;

    address internal constant _deployer = address(0xdeee);
    address internal constant _spoolAdmin = address(0xad1);
    address internal constant _doHardWorker = address(0xdddd);
    address internal constant _reallocator = address(0xeac);
    address internal constant _riskProvider = address(0x9876);
    address internal constant _emergencyWallet = address(0xeeee);
    address internal constant _feeRecipient = address(0xffff);

    bytes32 internal constant EVENT_SLIPPAGES_TOPIC = keccak256("Slippages(bool,uint256,bytes)");
    bytes32 internal constant EVENT_BEFORE_DEPOSIT_CHECK_SLIPPAGES = keccak256("BeforeDepositCheckSlippages(uint256[])");
    bytes32 internal constant EVENT_BEFORE_REDEEMAL_CHECK_SLIPPAGES = keccak256("BeforeRedeemalCheckSlippages(uint256)");

    TestMainnetInitialSetup internal _deploySpool;

    SmartVaultManager internal _smartVaultManager;
    StrategyRegistry internal _strategyRegistry;

    IERC20 internal dai;
    IERC20 internal usdc;
    IERC20 internal usdt;
    IERC20 internal weth;

    uint256 private _rn = 10;

    string config;

    function _setConfig() internal virtual {
        config = vm.readFile(string.concat("deploy/mainnet-production.constants.json"));
    }

    function _deploy(Extended extended) internal {
        setUpForkTestFixture();
        vm.selectFork(mainnetForkId);
        _setConfig();

        vm.writeJson(config, TEST_CONSTANTS_PATH);
        vm.writeJson(Strings.toHexString(_spoolAdmin), TEST_CONSTANTS_PATH, ".proxyAdminOwner");
        vm.writeJson(Strings.toHexString(_spoolAdmin), TEST_CONSTANTS_PATH, ".spoolAdmin");
        vm.writeJson(Strings.toHexString(_emergencyWallet), TEST_CONSTANTS_PATH, ".emergencyWithdrawalWallet");
        vm.writeJson(Strings.toHexString(_feeRecipient), TEST_CONSTANTS_PATH, ".fees.ecosystemFeeReceiver");
        vm.writeJson(Strings.toHexString(_feeRecipient), TEST_CONSTANTS_PATH, ".fees.treasuryFeeReceiver");

        // TestMainnetInitialSetup is expecting this file to exist
        vm.writeJson("{}", TEST_CONTRACTS_PATH);

        _deploySpool = new TestMainnetInitialSetup();
        _deploySpool.init();
        _deploySpool.doSetup(address(_deploySpool), extended);

        {
            uint256 assetGroupId;
            address[] memory assetGroup;

            assetGroupId = _deploySpool.assetGroups(DAI_KEY);
            assetGroup = _deploySpool.assetGroupRegistry().listAssetGroup(assetGroupId);
            dai = IERC20(assetGroup[0]);

            assetGroupId = _deploySpool.assetGroups(USDC_KEY);
            assetGroup = _deploySpool.assetGroupRegistry().listAssetGroup(assetGroupId);
            usdc = IERC20(assetGroup[0]);

            assetGroupId = _deploySpool.assetGroups(USDT_KEY);
            assetGroup = _deploySpool.assetGroupRegistry().listAssetGroup(assetGroupId);
            usdt = IERC20(assetGroup[0]);

            assetGroupId = _deploySpool.assetGroups(WETH_KEY);
            assetGroup = _deploySpool.assetGroupRegistry().listAssetGroup(assetGroupId);
            weth = IERC20(assetGroup[0]);
        }

        _smartVaultManager = _deploySpool.smartVaultManager();
        _strategyRegistry = _deploySpool.strategyRegistry();

        vm.allowCheatcodes(_spoolAdmin);
        startHoax(_spoolAdmin);
        _deploySpool.spoolAccessControl().grantRole(ROLE_DO_HARD_WORKER, _doHardWorker);
        _deploySpool.spoolAccessControl().grantRole(ROLE_REALLOCATOR, _reallocator);
        _deploySpool.spoolAccessControl().grantRole(ROLE_RISK_PROVIDER, _riskProvider);

        vm.stopPrank();
    }

    function _getStrategyAddress(string memory strategyKey, uint256 assetGroupId) internal view returns (address) {
        return _deploySpool.strategies(strategyKey, assetGroupId);
    }

    function _getStrategyAddress(string memory strategyKey, string memory assetGroupKey)
        internal
        view
        returns (address)
    {
        return _getStrategyAddress(strategyKey, _getAssetGroupId(assetGroupKey));
    }

    function _getAssetGroupId(string memory assetGroupKey) internal view returns (uint256) {
        return _deploySpool.assetGroups(assetGroupKey);
    }

    function _flushVaults(ISmartVault[] memory vaults) internal {
        for (uint256 i; i < vaults.length; ++i) {
            _flushVaults(vaults[i]);
        }
    }

    function _flushVaults(ISmartVault vault) internal {
        _smartVaultManager.flushSmartVault(address(vault));
    }

    function _syncVaults(ISmartVault[] memory vaults) internal {
        for (uint256 i; i < vaults.length; ++i) {
            _syncVaults(vaults[i]);
        }
    }

    function _syncVaults(ISmartVault vault) internal {
        _smartVaultManager.syncSmartVault(address(vault), true);
    }

    function _dhw(address strategy) internal {
        _dhw(Arrays.toArray(strategy));
    }

    function _dhw(address[] memory strategies) internal {
        // first run is to get parameters
        // - create a snapshot
        uint256 snapshot = vm.snapshot();
        // - generate default DHW parameters
        DoHardWorkParameterBag memory parameters = _generateDhwParameterBag(strategies);
        // - record logs
        vm.recordLogs();
        // - run DHW as address(0) which skips few checks
        _prankOrigin(address(0), address(0));
        _strategyRegistry.doHardWork(parameters);
        vm.stopPrank();
        // - get recorded logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // - restore the state to snapshot
        vm.revertTo(snapshot);

        // next run is with correct parameters
        // - update parameters
        _updateDhwParameterBag(parameters, logs);
        // - run DHW as do-hard-worker with correct parametes
        _prank(_doHardWorker);
        _strategyRegistry.doHardWork(parameters);
        vm.stopPrank();
    }

    function _deposit(ISmartVault vault, address[] memory users, uint256[][] memory amounts)
        internal
        returns (uint256[] memory depositIds)
    {
        depositIds = new uint256[](users.length);
        for (uint256 i; i < users.length; ++i) {
            depositIds[i] = _deposit(vault, users[i], amounts[i]);
        }
    }

    function _deposit(ISmartVault vault, address[] memory users, uint256[] memory amounts)
        internal
        returns (uint256[] memory depositIds)
    {
        uint256[][] memory amountsDouble = new uint256[][](amounts.length);
        for (uint256 i; i < amounts.length; ++i) {
            amountsDouble[i] = Arrays.toArray(amounts[i]);
        }

        return _deposit(vault, users, amountsDouble);
    }

    function _depositInRatio(ISmartVault vault, address[] memory users, uint256[] memory amounts)
        internal
        returns (uint256[] memory depositIds, uint256[][] memory amountsDouble)
    {
        uint256[] memory assetRatio = _smartVaultManager.depositRatio(address(vault));

        amountsDouble = new uint256[][](amounts.length);
        for (uint256 i; i < amounts.length; ++i) {
            amountsDouble[i] = new uint256[](assetRatio.length);

            for (uint256 j; j < assetRatio.length; ++j) {
                amountsDouble[i][j] = amounts[i] * assetRatio[j] / assetRatio[0];
            }
        }

        depositIds = _deposit(vault, users, amountsDouble);

        return (depositIds, amountsDouble);
    }

    function _depositInRatio(ISmartVault vault, address user, uint256 amount)
        internal
        returns (uint256 depositId, uint256[] memory amounts)
    {
        uint256[] memory assetRatio = _smartVaultManager.depositRatio(address(vault));

        amounts = new uint256[](assetRatio.length);

        for (uint256 i; i < assetRatio.length; ++i) {
            amounts[i] = amount * assetRatio[i] / assetRatio[0];
        }

        depositId = _deposit(vault, user, amounts);
    }

    function _deposit(ISmartVault vault, address user, uint256[] memory amounts)
        internal
        prank(user)
        returns (uint256 depositId)
    {
        address[] memory assets = _deploySpool.assetGroupRegistry().listAssetGroup(vault.assetGroupId());
        require(amounts.length == assets.length, "_deposit: Bad amounts length for vault");
        for (uint256 i; i < amounts.length; ++i) {
            IERC20(assets[i]).safeApprove(address(_smartVaultManager), amounts[i]);
        }

        depositId = _smartVaultManager.deposit(DepositBag(address(vault), amounts, user, address(0), false));
    }

    function _deposit(ISmartVault vault, address user, uint256 amount) internal returns (uint256 depositId) {
        return _deposit(vault, user, Arrays.toArray(amount));
    }

    // TODO: add one tx NFT withdrawal
    function _redeemNfts(ISmartVault vault, address user, uint256 depositNftId)
        internal
        prank(user)
        returns (uint256 withdrawalNftId)
    {
        _smartVaultManager.claimSmartVaultTokens(
            address(vault), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
        );

        uint256 userShares = vault.balanceOf(user);

        withdrawalNftId = _smartVaultManager.redeem(
            RedeemBag(address(vault), userShares, new uint256[](0), new uint256[](0)), user, false
        );
    }

    function _redeemNfts(ISmartVault vault, address[] memory users, uint256[] memory depositNftIds)
        internal
        returns (uint256[] memory withdrawalNftIds)
    {
        withdrawalNftIds = new uint256[](users.length);
        for (uint256 i; i < users.length; ++i) {
            withdrawalNftIds[i] = _redeemNfts(vault, users[i], depositNftIds[i]);
        }
    }

    function _claimWithdrawals(ISmartVault vault, address user, uint256 withdrawalNftId) internal prank(user) {
        _smartVaultManager.claimWithdrawal(
            address(vault), Arrays.toArray(withdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), user
        );
    }

    function _claimWithdrawals(ISmartVault vault, address[] memory users, uint256[] memory withdrawalNftId) internal {
        for (uint256 i; i < users.length; ++i) {
            _claimWithdrawals(vault, users[i], withdrawalNftId[i]);
        }
    }

    function _redeemFast(ISmartVault vault, address[] memory users, uint256[] memory depositNftIds) internal {
        for (uint256 i; i < users.length; ++i) {
            _redeemFast(vault, users[i], depositNftIds[i]);
        }
    }

    function _redeemFast(ISmartVault vault, address user, uint256 depositNftId) internal prank(user) {
        _smartVaultManager.claimSmartVaultTokens(
            address(vault), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
        );

        uint256 userShares = vault.balanceOf(user);

        _smartVaultManager.redeemFast(
            RedeemBag(address(vault), userShares, new uint256[](0), new uint256[](0)),
            _getRedeemFastSlippages(vault, userShares)
        );
    }

    function _getBalances(address[] memory users, IERC20 token) internal view returns (uint256[] memory balances) {
        balances = new uint256[](users.length);
        for (uint256 i; i < users.length; ++i) {
            balances[i] = token.balanceOf(users[i]);
        }
    }

    function _getBalances(address[] memory users, address[] memory tokens)
        internal
        view
        returns (uint256[][] memory balances)
    {
        balances = new uint256[][](users.length);

        for (uint256 i; i < users.length; ++i) {
            balances[i] = new uint256[](tokens.length);

            for (uint256 j; j < tokens.length; ++j) {
                balances[i][j] = IERC20(tokens[j]).balanceOf(users[i]);
            }
        }
    }

    function _assertSmartVaultBalances(ISmartVault smartVault, uint256[][] memory depositAmounts, uint256 maxDelta)
        internal
    {
        uint256 snapshot = vm.snapshot();

        uint256[] memory balances = _deploySpool.spoolLens().getSmartVaultAssetBalances(address(smartVault), false);

        uint256[] memory depositAmountsSum = new uint256[](balances.length);

        for (uint256 i; i < depositAmounts.length; ++i) {
            for (uint256 j; j < depositAmountsSum.length; ++j) {
                depositAmountsSum[j] += depositAmounts[i][j];
            }
        }

        _batchAssertApproxEqRel(balances, depositAmountsSum, maxDelta);

        vm.revertTo(snapshot);
    }

    function _assertSmartVaultBalances(ISmartVault smartVault, uint256[] memory depositAmounts, uint256 maxDelta)
        internal
    {
        uint256[][] memory depositAmountsDoubleArray = new uint256[][](depositAmounts.length);

        for (uint256 i; i < depositAmounts.length; ++i) {
            depositAmountsDoubleArray[i] = Arrays.toArray(depositAmounts[i]);
        }

        _assertSmartVaultBalances(smartVault, depositAmountsDoubleArray, maxDelta);
    }

    function _verifyUniqueAddresses(address[] memory addresses) internal pure {
        for (uint256 i; i < addresses.length; ++i) {
            for (uint256 j = i + 1; j < addresses.length; ++j) {
                require(addresses[i] != addresses[j], "_verifyUniqueAddresses: Addresses not unique");
            }
        }
    }

    function _batchBalanceDiffAbs(
        uint256[] memory balanceBefore,
        uint256[] memory balanceAfter,
        uint256[] memory b,
        uint256 maxDelta
    ) internal {
        require(balanceBefore.length == balanceAfter.length, "_batchBalanceDiffAbs: Array are not of the same length");

        uint256[] memory diff = new uint256[](balanceBefore.length);

        for (uint256 i; i < balanceBefore.length; ++i) {
            diff[i] = balanceAfter[i] - balanceBefore[i];
        }

        _batchAssertApproxEqAbs(diff, b, maxDelta);
    }

    function _batchBalanceDiffRel(
        uint256[] memory balanceBefore,
        uint256[] memory balanceAfter,
        uint256[] memory b,
        uint256 maxDelta
    ) internal {
        require(balanceBefore.length == balanceAfter.length, "_batchBalanceDiffRel: Array are not of the same length");

        uint256[] memory diff = new uint256[](balanceBefore.length);

        for (uint256 i; i < balanceBefore.length; ++i) {
            diff[i] = balanceAfter[i] - balanceBefore[i];
        }

        _batchAssertApproxEqRel(diff, b, maxDelta);
    }

    function _batchBalanceDiffRel(
        uint256[][] memory balanceBefore,
        uint256[][] memory balanceAfter,
        uint256[][] memory b,
        uint256 maxDelta
    ) internal {
        require(
            balanceBefore.length == balanceAfter.length && balanceBefore.length == b.length,
            "_batchBalanceDiffRel: Array are not of the same length"
        );

        for (uint256 i; i < balanceBefore.length; ++i) {
            require(
                balanceBefore[i].length == balanceAfter[i].length && balanceBefore[i].length == b[i].length,
                "_batchBalanceDiffRel: Array are not of the same length"
            );

            for (uint256 j; j < balanceBefore[i].length; ++j) {
                assertApproxEqRel(
                    balanceAfter[i][j] - balanceBefore[i][j],
                    b[i][j],
                    maxDelta,
                    string.concat(
                        "_batchAssertApproxEqAbs:: user ", Strings.toString(i), " asset ", Strings.toString(j)
                    )
                );
            }
        }
    }

    function _batchAssertApproxEqAbs(uint256[] memory a, uint256[] memory b, uint256 maxDelta) internal {
        require(a.length == b.length, "_batchAssertApproxEqAbs: Array are not of the same length");

        for (uint256 i; i < a.length; ++i) {
            assertApproxEqAbs(
                a[i], b[i], maxDelta, string.concat("_batchAssertApproxEqAbs:: index: ", Strings.toString(i))
            );
        }
    }

    function _batchAssertApproxEqRel(uint256[] memory a, uint256[] memory b, uint256 maxDelta) internal {
        require(a.length == b.length, "_batchAssertApproxEqRel: Array are not of the same length");

        for (uint256 i; i < a.length; ++i) {
            assertApproxEqRel(
                a[i], b[i], maxDelta, string.concat("_batchAssertApproxEqRel:: index: ", Strings.toString(i))
            );
        }
    }

    function _assertAllocationApproxRel(ISmartVault vault, uint256 maxDelta) internal {
        uint16a16 setAllocation = _smartVaultManager.allocations(address(vault));
        address[] memory strategies = _smartVaultManager.strategies(address(vault));
        uint256 totalUsdValue = VaultValueHelpers.getVaultTotalUsdValue(
            vm,
            vault,
            _deploySpool.assetGroupRegistry(),
            _deploySpool.usdPriceFeedManager(),
            _deploySpool.smartVaultManager()
        );

        uint256 totalAllocation;
        for (uint256 i; i < strategies.length; ++i) {
            totalAllocation += setAllocation.get(i);
        }

        for (uint256 i; i < strategies.length; ++i) {
            uint256 targetValue = totalUsdValue * setAllocation.get(i) / totalAllocation;
            uint256 actualValue = VaultValueHelpers.getVaultStrategyUsdValue(
                vm,
                vault,
                _deploySpool.assetGroupRegistry(),
                _deploySpool.usdPriceFeedManager(),
                _deploySpool.smartVaultManager(),
                IStrategy(strategies[i])
            );

            assertApproxEqRel(
                actualValue,
                targetValue,
                maxDelta,
                string.concat("_assertAllocationApproxRel:: index: ", Strings.toString(i))
            );
        }
    }

    function _createVault(
        uint16 managementFeePct,
        uint16 depositFeePct,
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
                managementFeePct: managementFeePct,
                depositFeePct: depositFeePct,
                allocationProvider: allocationProvider,
                performanceFeePct: 0,
                allowRedeemFor: false
            })
        );
    }

    function _dealTokens(address[] memory accounts) internal {
        for (uint256 i; i < accounts.length; ++i) {
            _dealTokens(accounts[i]);
        }
    }

    function _dealTokens(address account) internal {
        deal(address(dai), account, 1e18 * 1e6, true);
        // TODO: forge throw errors on dealing USDC (somehow related to proxy https://github.com/foundry-rs/forge-std/issues/318)
        vm.startPrank(USDC_WHALE);
        IERC20(usdc).transfer(account, 1e6 * 1e6);
        vm.stopPrank();
        // deal(address(usdc), account, 1e6 * 1e6, true);
        deal(address(usdt), account, 1e6 * 1e6, true);

        IWETH9(address(weth)).deposit{value: 1e18 * 1e6}();
        weth.safeTransfer(address(account), 1e18 * 1e6);
    }

    function _setRiskScores(uint8[] memory risks, address[] memory strategies) internal prank(_riskProvider) {
        _deploySpool.riskManager().setRiskScores(risks, strategies);
    }

    function _setRandomRiskScores(address[] memory strategies) internal {
        uint8[] memory risks = new uint8[](strategies.length);

        for (uint256 i; i < strategies.length; ++i) {
            risks[i] = uint8(_randomNumber(1, 10_0));
        }

        _setRiskScores(risks, strategies);
    }

    function _randomNumber(uint256 max) internal returns (uint256) {
        return _randomNumber(0, max);
    }

    function _randomNumber(uint256 min, uint256 max) internal returns (uint256) {
        require(min < max, "_randomNumber: Min should be less than max");

        _rn++;
        uint256 random = uint256(keccak256(abi.encode(_rn)));

        uint256 diff = max - min;

        return (random % (diff + 1)) + min;
    }

    modifier prank(address executor) {
        _prank(executor);
        _;
        vm.stopPrank();
    }

    modifier prankOrigin(address executor, address origin) {
        _prankOrigin(executor, origin);
        _;
        vm.stopPrank();
    }

    function _prank(address executor) internal {
        if (executor.balance > 0) {
            vm.startPrank(executor);
        } else {
            vm.allowCheatcodes(executor);
            startHoax(executor);
        }
    }

    function _prankOrigin(address executor, address origin) internal {
        if (executor.balance > 0) {
            vm.startPrank(executor, origin);
        } else {
            vm.allowCheatcodes(executor);
            startHoax(executor, origin);
        }
    }

    function test_mock() external pure {}

    /* ========== DHW ========== */

    function _generateDhwParameterBag(address[] memory strategies)
        internal
        view
        returns (DoHardWorkParameterBag memory)
    {
        DoHardWorkParameterBag memory parameters = _generateDefaultDhwParameterBag(strategies);

        // loop over strategy groups
        for (uint256 i; i < parameters.strategies.length; ++i) {
            // loop over strategies in a group
            for (uint256 j; j < parameters.strategies[i].length; ++j) {
                address strategy = parameters.strategies[i][j];

                string memory strategyKey = _deploySpool.addressToStrategyKey(strategy);

                if (Strings.equal(strategyKey, AAVE_V2_KEY)) {
                    // continue
                } else if (Strings.equal(strategyKey, COMPOUND_V2_KEY)) {
                    // continue
                } else if (Strings.equal(strategyKey, CONVEX_3POOL_KEY)) {
                    _setInitialDhwParametersGeneric(parameters, i, j, 12);
                } else if (Strings.equal(strategyKey, CONVEX_ALUSD_KEY)) {
                    _setInitialDhwParametersGeneric(parameters, i, j, 14);
                } else if (Strings.equal(strategyKey, CURVE_3POOL_KEY)) {
                    _setInitialDhwParametersGeneric(parameters, i, j, 12);
                } else if (Strings.equal(strategyKey, IDLE_BEST_YIELD_SENIOR_KEY)) {
                    _setInitialDhwParametersGeneric(parameters, i, j, 5);
                } else if (Strings.equal(strategyKey, MORPHO_AAVE_V2_KEY)) {
                    // continue
                } else if (Strings.equal(strategyKey, MORPHO_COMPOUND_V2_KEY)) {
                    // continue
                } else if (Strings.equal(strategyKey, NOTIONAL_FINANCE_KEY)) {
                    // continue
                } else if (Strings.equal(strategyKey, RETH_HOLDING_KEY)) {
                    _setInitialDhwParametersGeneric(parameters, i, j, 7);
                } else if (Strings.equal(strategyKey, SFRXETH_HOLDING_KEY)) {
                    _setInitialDhwParametersGeneric(parameters, i, j, 4);
                } else if (Strings.equal(strategyKey, STETH_HOLDING_KEY)) {
                    _setInitialDhwParametersGeneric(parameters, i, j, 4);
                } else if (Strings.equal(strategyKey, YEARN_V2_KEY)) {
                    _setInitialDhwParametersGeneric(parameters, i, j, 4);
                } else if (Strings.equal(strategyKey, METAMORPHO_KEY)) {
                    _setInitialDhwParametersGeneric(parameters, i, j, 6);
                } else if (Strings.equal(strategyKey, YEARN_V3_GAUGED_KEY)) {
                    _setInitialDhwParametersGeneric(parameters, i, j, 6);
                } else if (Strings.equal(strategyKey, YEARN_V3_JUICED_KEY)) {
                    _setInitialDhwParametersGeneric(parameters, i, j, 6);
                } else {
                    revert(string.concat("_generateDhwParameterBag: Strategy '", strategyKey, "' not handled."));
                }
            }
        }

        return parameters;
    }

    function _updateDhwParameterBag(DoHardWorkParameterBag memory parameters, Vm.Log[] memory logs) internal view {
        // loop over strategy groups
        for (uint256 i; i < parameters.strategies.length; ++i) {
            // loop over strategies in a group
            for (uint256 j; j < parameters.strategies[i].length; ++j) {
                address strategy = parameters.strategies[i][j];

                string memory strategyKey = _deploySpool.addressToStrategyKey(strategy);

                if (Strings.equal(strategyKey, AAVE_V2_KEY)) {
                    // continue
                } else if (Strings.equal(strategyKey, COMPOUND_V2_KEY)) {
                    // continue
                } else if (Strings.equal(strategyKey, CONVEX_3POOL_KEY)) {
                    _updateDhwParametersGeneric(parameters, i, j, strategy, logs, 1);
                } else if (Strings.equal(strategyKey, CONVEX_ALUSD_KEY)) {
                    _updateDhwParametersGeneric(parameters, i, j, strategy, logs, 1);
                } else if (Strings.equal(strategyKey, CURVE_3POOL_KEY)) {
                    _updateDhwParametersGeneric(parameters, i, j, strategy, logs, 1);
                } else if (Strings.equal(strategyKey, IDLE_BEST_YIELD_SENIOR_KEY)) {
                    _updateDhwParametersGeneric(parameters, i, j, strategy, logs, 1);
                } else if (Strings.equal(strategyKey, MORPHO_AAVE_V2_KEY)) {
                    // continue
                } else if (Strings.equal(strategyKey, MORPHO_COMPOUND_V2_KEY)) {
                    // continue
                } else if (Strings.equal(strategyKey, NOTIONAL_FINANCE_KEY)) {
                    // continue
                } else if (Strings.equal(strategyKey, RETH_HOLDING_KEY)) {
                    _updateDhwParametersGeneric(parameters, i, j, strategy, logs, 0);
                } else if (Strings.equal(strategyKey, SFRXETH_HOLDING_KEY)) {
                    // not production ready - approximation
                    _updateDhwParametersGeneric(parameters, i, j, strategy, logs, 0);
                } else if (Strings.equal(strategyKey, STETH_HOLDING_KEY)) {
                    // not production ready - approximation
                    _updateDhwParametersGeneric(parameters, i, j, strategy, logs, 0);
                } else if (Strings.equal(strategyKey, YEARN_V2_KEY)) {
                    _updateDhwParametersGeneric(parameters, i, j, strategy, logs, 0);
                } else if (Strings.equal(strategyKey, METAMORPHO_KEY)) {
                    _updateDhwParametersGeneric(parameters, i, j, strategy, logs, 1);
                } else if (Strings.equal(strategyKey, YEARN_V3_GAUGED_KEY)) {
                    _updateDhwParametersGeneric(parameters, i, j, strategy, logs, 0);
                } else if (Strings.equal(strategyKey, YEARN_V3_JUICED_KEY)) {
                    _updateDhwParametersGeneric(parameters, i, j, strategy, logs, 0);
                } else {
                    revert(string.concat("_updateDhwParameterBag: Strategy '", strategyKey, "' not handled."));
                }
            }
        }
    }

    function _generateDefaultDhwParameterBag(address[] memory strategies)
        internal
        view
        returns (DoHardWorkParameterBag memory)
    {
        require(strategies.length > 0, "_generateDhwParameterBag: No strategies");

        address[][] memory strategyGroups = new address[][](1);
        strategyGroups[0] = strategies;

        SwapInfo[][][] memory swapInfo = new SwapInfo[][][](1);
        swapInfo[0] = new SwapInfo[][](strategies.length);
        SwapInfo[][][] memory compoundSwapInfo = new SwapInfo[][][](1);
        compoundSwapInfo[0] = new SwapInfo[][](strategies.length);

        uint256[][][] memory strategySlippages = new uint256[][][](1);
        strategySlippages[0] = new uint256[][](strategies.length);

        uint256 assetGroupId = IStrategy(strategies[0]).assetGroupId();
        for (uint256 i; i < strategies.length; ++i) {
            require(
                assetGroupId == IStrategy(strategies[i]).assetGroupId(),
                "_generateDhwParameterBag: Accepts only same asset group id strategies"
            );
            swapInfo[0][i] = new SwapInfo[](0);
            compoundSwapInfo[0][i] = new SwapInfo[](0);
            strategySlippages[0][i] = new uint256[](10);
        }

        address[] memory tokens = IStrategy(strategies[0]).assets();

        uint256[2][] memory exchangeRateSlippages = new uint256[2][](tokens.length);

        for (uint256 i; i < tokens.length; ++i) {
            exchangeRateSlippages[i][0] = 0;
            exchangeRateSlippages[i][1] = type(uint256).max;
        }

        int256[][] memory baseYields = new int256[][](1);
        baseYields[0] = new int256[](strategies.length);

        return DoHardWorkParameterBag({
            strategies: strategyGroups,
            swapInfo: swapInfo,
            compoundSwapInfo: compoundSwapInfo,
            strategySlippages: strategySlippages,
            tokens: tokens,
            exchangeRateSlippages: exchangeRateSlippages,
            baseYields: baseYields,
            validUntil: TimeUtils.getTimestampInInfiniteFuture()
        });
    }

    function _setInitialDhwParametersGeneric(
        DoHardWorkParameterBag memory parameters,
        uint256 strategyGroupIdx,
        uint256 strategyIdx,
        uint256 numberOfSlippages
    ) internal pure {
        parameters.strategySlippages[strategyGroupIdx][strategyIdx] = new uint256[](numberOfSlippages);
    }

    function _updateDhwParametersGeneric(
        DoHardWorkParameterBag memory parameters,
        uint256 strategyGroupIdx,
        uint256 strategyIdx,
        address strategy,
        Vm.Log[] memory logs,
        uint256 numberOfCompoundSlippages
    ) internal pure {
        uint256[] memory strategySlippages = parameters.strategySlippages[strategyGroupIdx][strategyIdx];

        uint256 currentSlippageIndex = 1;
        {
            // beforeDepositCheck slippages
            bool found = false;

            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].emitter != strategy || logs[i].topics[0] != EVENT_BEFORE_DEPOSIT_CHECK_SLIPPAGES) {
                    continue;
                }

                (uint256[] memory amounts) = abi.decode(logs[i].data, (uint256[]));

                for (uint256 j; j < amounts.length; ++j) {
                    strategySlippages[currentSlippageIndex++] = Arrays.toPackedRange(amounts[j], amounts[j]);
                }

                found = true;
                break;
            }

            if (!found) {
                revert("_updateReallocateParamsGeneric:: EVENT_BEFORE_DEPOSIT_CHECK_SLIPPAGES not found.");
            }
        }

        {
            // beforeRedeemalCheck slippages
            bool found = false;

            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].emitter != strategy || logs[i].topics[0] != EVENT_BEFORE_REDEEMAL_CHECK_SLIPPAGES) {
                    continue;
                }

                (uint256 ssts) = abi.decode(logs[i].data, (uint256));

                strategySlippages[currentSlippageIndex++] = Arrays.toPackedRange(ssts, ssts);

                found = true;
                break;
            }

            if (!found) {
                revert("_updateReallocateParamsGeneric:: EVENT_BEFORE_REDEEMAL_CHECK_SLIPPAGES not found.");
            }
        }

        currentSlippageIndex += numberOfCompoundSlippages;
        {
            // _depositToProtocol / _redeemFromProtocol slippages
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].emitter != strategy || logs[i].topics[0] != EVENT_SLIPPAGES_TOPIC) {
                    continue;
                }

                (bool isDeposit, uint256 slippage, bytes memory data) = abi.decode(logs[i].data, (bool, uint256, bytes));

                if (data.length == 0) {
                    strategySlippages[currentSlippageIndex++] = slippage;
                } else {
                    (uint256[] memory slippages) = abi.decode(data, (uint256[]));

                    for (uint256 j; j < slippages.length; ++j) {
                        strategySlippages[currentSlippageIndex++] = slippages[j];
                    }
                }

                if (!isDeposit) {
                    strategySlippages[0] = 1;
                }

                break;
            }
        }

        parameters.strategySlippages[strategyGroupIdx][strategyIdx] = strategySlippages;
    }

    /* ========== REDEEM FAST ========== */

    function _getRedeemFastSlippages(ISmartVault vault, uint256)
        private
        view
        returns (uint256[][] memory strategySlippages)
    {
        address[] memory strategies = _smartVaultManager.strategies(address(vault));

        strategySlippages = new uint256[][](strategies.length);

        for (uint256 i; i < strategies.length; ++i) {
            string memory strategyKey = _deploySpool.addressToStrategyKey(strategies[i]);

            if (Strings.equal(strategyKey, AAVE_V2_KEY)) {
                // continue
            } else if (Strings.equal(strategyKey, CONVEX_3POOL_KEY)) {
                strategySlippages[i] = _getRedeemFastSlippagesSimple(strategies[i]);
            } else if (Strings.equal(strategyKey, CONVEX_ALUSD_KEY)) {
                strategySlippages[i] = _getRedeemFastSlippagesSimple(strategies[i]);
            } else if (Strings.equal(strategyKey, CURVE_3POOL_KEY)) {
                strategySlippages[i] = _getRedeemFastSlippagesSimple(strategies[i]);
            } else if (Strings.equal(strategyKey, COMPOUND_V2_KEY)) {
                // continue
            } else if (Strings.equal(strategyKey, IDLE_BEST_YIELD_SENIOR_KEY)) {
                strategySlippages[i] = _getRedeemFastSlippagesSimple(strategies[i]);
            } else if (Strings.equal(strategyKey, MORPHO_AAVE_V2_KEY)) {
                // continue
            } else if (Strings.equal(strategyKey, MORPHO_COMPOUND_V2_KEY)) {
                // continue
            } else if (Strings.equal(strategyKey, NOTIONAL_FINANCE_KEY)) {
                // continue
            } else if (Strings.equal(strategyKey, RETH_HOLDING_KEY)) {
                strategySlippages[i] = _getRedeemFastSlippagesREthHoldingStrategy(strategies[i]);
            } else if (Strings.equal(strategyKey, SFRXETH_HOLDING_KEY)) {
                strategySlippages[i] = _getRedeemFastSlippagesSimple(strategies[i]);
            } else if (Strings.equal(strategyKey, STETH_HOLDING_KEY)) {
                strategySlippages[i] = _getRedeemFastSlippagesSimple(strategies[i]);
            } else if (Strings.equal(strategyKey, YEARN_V2_KEY)) {
                strategySlippages[i] = _getRedeemFastSlippagesSimple(strategies[i]);
            } else if (Strings.equal(strategyKey, METAMORPHO_KEY)) {
                strategySlippages[i] = _getRedeemFastSlippagesSimple(strategies[i]);
            } else if (Strings.equal(strategyKey, YEARN_V3_GAUGED_KEY)) {
                strategySlippages[i] = _getRedeemFastSlippagesSimple(strategies[i]);
            } else if (Strings.equal(strategyKey, YEARN_V3_JUICED_KEY)) {
                strategySlippages[i] = _getRedeemFastSlippagesSimple(strategies[i]);
            } else {
                revert(string.concat("_getRedeemFastSlippages: Strategy '", strategyKey, "' not handled."));
            }
        }
    }

    function _getRedeemFastSlippagesSimple(address strategy) private view returns (uint256[] memory slippages) {
        address[] memory assets = IStrategy(strategy).assets();

        slippages = new uint256[](2 + assets.length);
        slippages[0] = 3;
    }

    function _getRedeemFastSlippagesREthHoldingStrategy(address) private pure returns (uint256[] memory slippages) {
        slippages = new uint256[](5);
        slippages[0] = 3;

        // - set to swap everything via uniswap
        slippages[1] = 100; // uniswap portion
        slippages[2] = 0; // balancer portion
        slippages[3] = 0; // min tokens out
        slippages[4] = type(uint256).max; // ideal tokens out - set to max to prevent internal swapping
    }

    /* ========== REALLOCATION ========== */

    function _reallocate(ISmartVault vault) internal {
        // first run is to get parameters
        // - create a snapshot
        uint256 snapshot = vm.snapshot();
        // - generate initial paramaters
        ReallocateParamBag memory params = _generateReallocateParamBag(vault);
        // - record logs
        vm.recordLogs();
        // - run reallocation as address(0)
        _prankOrigin(address(0), address(0));
        _smartVaultManager.reallocate(params);
        vm.stopPrank();
        // - get recorded logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // - restore the state to snapshot
        vm.revertTo(snapshot);

        // next run is with correct parameters
        // - update parameters
        _updateReallocateParamBag(params, logs);
        // - run reallocation as reallocator with correct parameters
        _prank(_reallocator);
        _smartVaultManager.reallocate(params);
        vm.stopPrank();
    }

    function _generateReallocateParamBag(ISmartVault vault) internal view returns (ReallocateParamBag memory params) {
        address[] memory strategies = _smartVaultManager.strategies(address(vault));
        address[] memory assets = _deploySpool.assetGroupRegistry().listAssetGroup(vault.assetGroupId());

        params.validUntil = TimeUtils.getTimestampInInfiniteFuture();

        params.smartVaults = new address[](1);
        params.smartVaults[0] = address(vault);

        params.strategies = _smartVaultManager.strategies(address(vault));

        params.swapInfo = new SwapInfo[][](strategies.length);

        params.depositSlippages = new uint256[][](strategies.length);

        params.withdrawalSlippages = new uint256[][](strategies.length);

        params.exchangeRateSlippages = new uint256[2][](assets.length);
        uint256[] memory exchangeRates = SpoolUtils.getExchangeRates(assets, _deploySpool.usdPriceFeedManager());
        for (uint256 i; i < assets.length; ++i) {
            params.exchangeRateSlippages[i][0] = exchangeRates[i];
            params.exchangeRateSlippages[i][1] = exchangeRates[i];
        }

        for (uint256 i; i < strategies.length; ++i) {
            string memory strategyKey = _deploySpool.addressToStrategyKey(strategies[i]);

            if (Strings.equal(strategyKey, AAVE_V2_KEY)) {
                // continue
            } else if (Strings.equal(strategyKey, COMPOUND_V2_KEY)) {
                // continue
            } else if (Strings.equal(strategyKey, CONVEX_3POOL_KEY)) {
                _setInitialReallocateParamsGeneric(params, i, 8, 5);
            } else if (Strings.equal(strategyKey, CONVEX_ALUSD_KEY)) {
                _setInitialReallocateParamsGeneric(params, i, 10, 5);
            } else if (Strings.equal(strategyKey, CURVE_3POOL_KEY)) {
                _setInitialReallocateParamsGeneric(params, i, 8, 5);
            } else if (Strings.equal(strategyKey, IDLE_BEST_YIELD_SENIOR_KEY)) {
                _setInitialReallocateParamsGeneric(params, i, 3, 3);
            } else if (Strings.equal(strategyKey, MORPHO_AAVE_V2_KEY)) {
                // continue
            } else if (Strings.equal(strategyKey, MORPHO_COMPOUND_V2_KEY)) {
                // continue
            } else if (Strings.equal(strategyKey, NOTIONAL_FINANCE_KEY)) {
                // continue
            } else if (Strings.equal(strategyKey, RETH_HOLDING_KEY)) {
                _setInitialReallocateParamsGeneric(params, i, 6, 6);
            } else if (Strings.equal(strategyKey, SFRXETH_HOLDING_KEY)) {
                _setInitialReallocateParamsGeneric(params, i, 3, 3);
            } else if (Strings.equal(strategyKey, STETH_HOLDING_KEY)) {
                _setInitialReallocateParamsGeneric(params, i, 3, 3);
            } else if (Strings.equal(strategyKey, YEARN_V2_KEY)) {
                _setInitialReallocateParamsGeneric(params, i, 3, 3);
            } else if (Strings.equal(strategyKey, METAMORPHO_KEY)) {
                _setInitialReallocateParamsGeneric(params, i, 3, 3);
            } else if (Strings.equal(strategyKey, YEARN_V3_GAUGED_KEY)) {
                _setInitialReallocateParamsGeneric(params, i, 3, 3);
            } else if (Strings.equal(strategyKey, YEARN_V3_JUICED_KEY)) {
                _setInitialReallocateParamsGeneric(params, i, 3, 3);
            } else {
                revert(string.concat("_generateReallocateParamBag:: Strategy '", strategyKey, "' not handled."));
            }
        }
    }

    function _updateReallocateParamBag(ReallocateParamBag memory params, Vm.Log[] memory logs) internal view {
        // loop over strategies
        for (uint256 i; i < params.strategies.length; ++i) {
            address strategy = params.strategies[i];
            string memory strategyKey = _deploySpool.addressToStrategyKey(strategy);

            // strategy specific update
            if (Strings.equal(strategyKey, AAVE_V2_KEY)) {
                // continue
            } else if (Strings.equal(strategyKey, COMPOUND_V2_KEY)) {
                // continue
            } else if (Strings.equal(strategyKey, CONVEX_3POOL_KEY)) {
                _updateReallocateParamsGeneric(params, i, strategy, logs);
            } else if (Strings.equal(strategyKey, CONVEX_ALUSD_KEY)) {
                _updateReallocateParamsGeneric(params, i, strategy, logs);
            } else if (Strings.equal(strategyKey, CURVE_3POOL_KEY)) {
                _updateReallocateParamsGeneric(params, i, strategy, logs);
            } else if (Strings.equal(strategyKey, IDLE_BEST_YIELD_SENIOR_KEY)) {
                _updateReallocateParamsGeneric(params, i, strategy, logs);
            } else if (Strings.equal(strategyKey, MORPHO_AAVE_V2_KEY)) {
                // continue
            } else if (Strings.equal(strategyKey, MORPHO_COMPOUND_V2_KEY)) {
                // continue
            } else if (Strings.equal(strategyKey, NOTIONAL_FINANCE_KEY)) {
                // continue
            } else if (Strings.equal(strategyKey, RETH_HOLDING_KEY)) {
                _updateReallocateParamsGeneric(params, i, strategy, logs);
            } else if (Strings.equal(strategyKey, SFRXETH_HOLDING_KEY)) {
                // not production ready - approximation
                _updateReallocateParamsGeneric(params, i, strategy, logs);
            } else if (Strings.equal(strategyKey, STETH_HOLDING_KEY)) {
                // not production ready - approximation
                _updateReallocateParamsGeneric(params, i, strategy, logs);
            } else if (Strings.equal(strategyKey, YEARN_V2_KEY)) {
                _updateReallocateParamsGeneric(params, i, strategy, logs);
            } else if (Strings.equal(strategyKey, METAMORPHO_KEY)) {
                _updateReallocateParamsGeneric(params, i, strategy, logs);
            } else if (Strings.equal(strategyKey, YEARN_V3_GAUGED_KEY)) {
                _updateReallocateParamsGeneric(params, i, strategy, logs);
            } else if (Strings.equal(strategyKey, YEARN_V3_JUICED_KEY)) {
                _updateReallocateParamsGeneric(params, i, strategy, logs);
            } else {
                revert(string.concat("_updateReallocateParamBag:: Strategy '", strategyKey, "' not handled."));
            }
        }
    }

    function _setInitialReallocateParamsGeneric(
        ReallocateParamBag memory params,
        uint256 strategyIdx,
        uint256 numberOfDepositSlippages,
        uint256 numberOfWithdrawalSlippages
    ) internal pure {
        uint256[] memory depositSlippages = new uint256[](numberOfDepositSlippages);
        uint256[] memory withdrawalSlippages = new uint256[](numberOfWithdrawalSlippages);

        depositSlippages[0] = 2;
        withdrawalSlippages[0] = 2;

        params.depositSlippages[strategyIdx] = depositSlippages;
        params.withdrawalSlippages[strategyIdx] = withdrawalSlippages;
    }

    function _updateReallocateParamsGeneric(
        ReallocateParamBag memory params,
        uint256 strategyIdx,
        address strategy,
        Vm.Log[] memory logs
    ) internal pure {
        uint256[] memory depositSlippages = params.depositSlippages[strategyIdx];
        uint256[] memory withdrawalSlippages = params.withdrawalSlippages[strategyIdx];

        uint256 currentSlippageIndex = 1;
        {
            // beforeDepositCheck slippages
            bool found = false;

            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].emitter != strategy || logs[i].topics[0] != EVENT_BEFORE_DEPOSIT_CHECK_SLIPPAGES) {
                    continue;
                }

                (uint256[] memory amounts) = abi.decode(logs[i].data, (uint256[]));

                for (uint256 j; j < amounts.length; ++j) {
                    depositSlippages[currentSlippageIndex++] = Arrays.toPackedRange(amounts[j], amounts[j]);
                }

                found = true;
                break;
            }

            if (!found) {
                revert("_updateReallocateParamsGeneric:: EVENT_BEFORE_DEPOSIT_CHECK_SLIPPAGES not found.");
            }
        }

        {
            // _depositToProtocol slippages
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].emitter != strategy || logs[i].topics[0] != EVENT_SLIPPAGES_TOPIC) {
                    continue;
                }

                (bool isDeposit, uint256 slippage, bytes memory data) = abi.decode(logs[i].data, (bool, uint256, bytes));

                if (!isDeposit) {
                    continue;
                }

                if (data.length == 0) {
                    depositSlippages[currentSlippageIndex++] = slippage;
                } else {
                    (uint256[] memory slippages) = abi.decode(data, (uint256[]));

                    for (uint256 j; j < slippages.length; ++j) {
                        depositSlippages[currentSlippageIndex++] = slippages[j];
                    }
                }

                break;
            }
        }

        currentSlippageIndex = 1;
        {
            // beforeRedeemalCheck slippages
            bool found = false;

            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].emitter != strategy || logs[i].topics[0] != EVENT_BEFORE_REDEEMAL_CHECK_SLIPPAGES) {
                    continue;
                }

                (uint256 ssts) = abi.decode(logs[i].data, (uint256));

                withdrawalSlippages[currentSlippageIndex++] = Arrays.toPackedRange(ssts, ssts);

                found = true;
                break;
            }

            if (!found) {
                revert("_updateReallocateParamsGeneric:: EVENT_BEFORE_REDEEMAL_CHECK_SLIPPAGES not found.");
            }
        }

        {
            // _redeemFromProtocol slippages
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].emitter != strategy || logs[i].topics[0] != EVENT_SLIPPAGES_TOPIC) {
                    continue;
                }

                (bool isDeposit, uint256 slippage, bytes memory data) = abi.decode(logs[i].data, (bool, uint256, bytes));

                if (isDeposit) {
                    continue;
                }

                if (data.length == 0) {
                    withdrawalSlippages[currentSlippageIndex++] = slippage;
                } else {
                    (uint256[] memory slippages) = abi.decode(data, (uint256[]));

                    for (uint256 j; j < slippages.length; ++j) {
                        withdrawalSlippages[currentSlippageIndex++] = slippages[j];
                    }
                }

                break;
            }
        }

        params.depositSlippages[strategyIdx] = depositSlippages;
        params.withdrawalSlippages[strategyIdx] = withdrawalSlippages;
    }
}
