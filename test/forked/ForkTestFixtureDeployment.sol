// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/utils/Strings.sol";
import "../../src/interfaces/Constants.sol";
import "../../src/SmartVaultFactory.sol";
import "../../src/external/interfaces/chainlink/AggregatorV3Interface.sol";
import "../../script/MainnetInitialSetup.s.sol";
import "../libraries/Arrays.sol";
import "./ForkTestFixture.sol";

string constant TEST_CONSTANTS_PATH = "deploy/fork-test.constants.json";
string constant TEST_CONTRACTS_PATH = "deploy/fork-test.contracts.json";

contract TestMainnetInitialSetup is MainnetInitialSetup {
    function init() public virtual override {
        super.init();

        _constantsJson = new JsonReader(vm, TEST_CONSTANTS_PATH);
        _contractsJson = new JsonWriter(TEST_CONTRACTS_PATH);
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
}

contract ForkTestFixtureDeployment is ForkTestFixture {
    address internal constant _deployer = address(0xdeee);
    address internal constant _spoolAdmin = address(0xad1);
    address internal constant _doHardWorker = address(0xdddd);
    address internal constant _emergencyWallet = address(0xeeee);
    address internal constant _feeRecipient = address(0xffff);

    TestMainnetInitialSetup internal _deploySpool;

    SmartVaultManager private smartVaultManager;
    IERC20 internal usdc;

    function _deploy() internal {
        setUpForkTestFixture();

        string memory config = vm.readFile("deploy/mainnet.constants.json");

        vm.writeJson(config, TEST_CONSTANTS_PATH);
        vm.writeJson(Strings.toHexString(_spoolAdmin), TEST_CONSTANTS_PATH, ".proxyAdminOwner");
        vm.writeJson(Strings.toHexString(_spoolAdmin), TEST_CONSTANTS_PATH, ".spoolAdmin");
        vm.writeJson(Strings.toHexString(_emergencyWallet), TEST_CONSTANTS_PATH, ".emergencyWithdrawalWallet");
        vm.writeJson(Strings.toHexString(_feeRecipient), TEST_CONSTANTS_PATH, ".fees.ecosystemFeeReceiver");
        vm.writeJson(Strings.toHexString(_feeRecipient), TEST_CONSTANTS_PATH, ".fees.treasuryFeeReceiver");

        _deploySpool = new TestMainnetInitialSetup();
        _deploySpool.init();
        _deploySpool.doSetup(address(_deploySpool));

        uint256 assetGroupIdUSDC = _deploySpool.assetGroups("usdc");
        address[] memory assetGroupUSDC = _deploySpool.assetGroupRegistry().listAssetGroup(assetGroupIdUSDC);
        usdc = IERC20(assetGroupUSDC[0]);

        smartVaultManager = _deploySpool.smartVaultManager();

        vm.allowCheatcodes(_spoolAdmin);
        startHoax(_spoolAdmin);
        _deploySpool.spoolAccessControl().grantRole(ROLE_DO_HARD_WORKER, _doHardWorker);

        _deploySpool.usdPriceFeedManager().setAsset(
            address(usdc), 6, AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6), true
        );

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

    function _generateDhwParameterBag(address[] memory strategies)
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
            strategySlippages[0][i] = new uint256[](0);
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
            baseYields: baseYields
        });
    }

    function _flushVaults(ISmartVault[] memory vaults) internal {
        for (uint256 i; i < vaults.length; ++i) {
            _flushVaults(vaults[i]);
        }
    }

    function _flushVaults(ISmartVault vault) internal {
        smartVaultManager.flushSmartVault(address(vault));
    }

    function _syncVaults(ISmartVault[] memory vaults) internal {
        for (uint256 i; i < vaults.length; ++i) {
            _syncVaults(vaults[i]);
        }
    }

    function _syncVaults(ISmartVault vault) internal {
        smartVaultManager.syncSmartVault(address(vault), true);
    }

    function _dhw(address strategy) internal {
        _dhw(Arrays.toArray(strategy));
    }

    function _dhw(address[] memory strategies) internal prank(_doHardWorker) {
        _deploySpool.strategyRegistry().doHardWork(_generateDhwParameterBag(strategies));
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

    function _deposit(ISmartVault vault, address user, uint256[] memory amounts)
        internal
        prank(user)
        returns (uint256 depositId)
    {
        address[] memory assets = _deploySpool.assetGroupRegistry().listAssetGroup(vault.assetGroupId());
        require(amounts.length == assets.length, "_deposit: Bad amounts length for vault");
        for (uint256 i; i < amounts.length; ++i) {
            IERC20(assets[i]).approve(address(smartVaultManager), amounts[i]);
        }

        depositId = smartVaultManager.deposit(DepositBag(address(vault), amounts, user, address(0), false));
    }

    function _deposit(ISmartVault vault, address user, uint256 amount) internal returns (uint256 depositId) {
        return _deposit(vault, user, Arrays.toArray(amount));
    }

    function _redeemNft(ISmartVault vault, address user, uint256 depositNftId)
        internal
        prank(user)
        returns (uint256 withdrawalNftId)
    {
        smartVaultManager.claimSmartVaultTokens(
            address(vault), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
        );

        uint256 userShares = vault.balanceOf(user);

        withdrawalNftId = smartVaultManager.redeem(
            RedeemBag(address(vault), userShares, new uint256[](0), new uint256[](0)), user, false
        );
    }

    function _claimWithdrawal(ISmartVault vault, address user, uint256 withdrawalNftId) internal prank(user) {
        smartVaultManager.claimWithdrawal(
            address(vault), Arrays.toArray(withdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), user
        );
    }

    function _createVault(
        uint16 managementFeePct,
        uint16 depositFeePct,
        uint256 assetGroupId,
        address[] memory strategies,
        uint16a16 allocations
    ) internal returns (ISmartVault smartVault) {
        smartVault = _deploySpool.smartVaultFactory().deploySmartVault(
            SmartVaultSpecification({
                smartVaultName: "MySmartVault",
                assetGroupId: assetGroupId,
                actions: new IAction[](0),
                actionRequestTypes: new RequestType[](0),
                guards: new GuardDefinition[][](0),
                guardRequestTypes: new RequestType[](0),
                strategies: strategies,
                strategyAllocation: allocations,
                riskTolerance: 0,
                riskProvider: address(0),
                managementFeePct: managementFeePct,
                depositFeePct: depositFeePct,
                allocationProvider: address(0),
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
        deal(address(usdc), account, 1e18, true);
    }

    modifier prank(address executor) {
        if (executor.balance > 0) {
            vm.startPrank(executor);
        } else {
            vm.allowCheatcodes(executor);
            startHoax(executor);
        }
        _;
        vm.stopPrank();
    }
}
