// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/managers/ActionManager.sol";
import "../src/managers/AssetGroupRegistry.sol";
import "../src/managers/GuardManager.sol";
import "../src/managers/RiskManager.sol";
import "../src/managers/SmartVaultManager.sol";
import "../src/managers/StrategyRegistry.sol";
import "../src/managers/UsdPriceFeedManager.sol";
import "../src/MasterWallet.sol";
import "../src/SmartVault.sol";
import "../src/Swapper.sol";
import "./libraries/Arrays.sol";
import "./mocks/MockStrategy.sol";
import "./mocks/MockToken.sol";
import "./mocks/MockPriceFeedManager.sol";

struct VaultManagerData {
    address smartVault;
    uint256 flushIndex;
    address[] strategies;
    uint256[] dhwIndexes;
    uint256[] vaultDeposits;
    uint256[][] flushedDeposits;
}

struct StrategyRegistryData {
    address strategy;
    uint256 dhwIndex;
    uint256 sharesMinted;
    uint256[] deposits;
    uint256[] slippages;
    uint256[] exchangeRates;
    address[] assetGroup;
}

contract MockSmartVaultManager is SmartVaultManager {
    using ArrayMapping for mapping(uint256 => uint256);

    constructor(
        ISpoolAccessControl accessControl_,
        IStrategyRegistry strategyRegistry_,
        IUsdPriceFeedManager priceFeedManager_,
        IAssetGroupRegistry assetGroupRegistry_,
        IMasterWallet masterWallet_,
        IActionManager actionManager_,
        IGuardManager guardManager_,
        ISwapper swapper_
    )
        SmartVaultManager(
            accessControl_,
            strategyRegistry_,
            priceFeedManager_,
            assetGroupRegistry_,
            masterWallet_,
            actionManager_,
            guardManager_,
            swapper_
        )
    {}

    function setData(VaultManagerData calldata data) external {
        _smartVaultStrategies[data.smartVault] = data.strategies;
        _vaultDeposits[data.smartVault][data.flushIndex].setValues(data.vaultDeposits);
        _dhwIndexes[data.smartVault][data.flushIndex].setValues(data.dhwIndexes);
        _flushIndexesToSync[data.smartVault] = data.flushIndex;
        _flushIndexes[data.smartVault] = data.flushIndex + 1;

        for (uint256 i = 0; i < data.strategies.length; i++) {
            _vaultFlushedDeposits[data.smartVault][data.flushIndex][data.strategies[i]].setValues(
                data.flushedDeposits[i]
            );
        }
    }
}

contract MockStrategyRegistry is StrategyRegistry {
    using ArrayMapping for mapping(uint256 => uint256);

    constructor(IMasterWallet masterWallet_, ISpoolAccessControl accessControl_, IUsdPriceFeedManager priceFeedManager_)
        StrategyRegistry(masterWallet_, accessControl_, priceFeedManager_)
    {}

    function setData(StrategyRegistryData calldata data) external {
        _sharesMinted[data.strategy][data.dhwIndex] = data.sharesMinted;
        _depositedAssets[data.strategy][data.dhwIndex].setValues(data.deposits);
        _depositSlippages[data.strategy][data.dhwIndex].setValues(data.slippages);
        _dhwExchangeRates[data.strategy][data.dhwIndex].setValues(data.exchangeRates);
        _strategies[data.strategy] = true;
        _currentIndexes[data.strategy] = data.dhwIndex + 1;

        uint256 totalUsdValue =
            _priceFeedManager.assetToUsdCustomPriceBulk(data.assetGroup, data.deposits, data.exchangeRates);
        MockStrategy(data.strategy).setTotalUsdValue(totalUsdValue);
    }
}

contract DepositIntegrationTest is Test, SpoolAccessRoles {
    address private alice = address(0xa);
    address private bob = address(0xb);
    address private riskProvider = address(0x1);
    address[] private strategies;

    MockToken private tokenA = new MockToken("Token A", "TA");
    MockToken private tokenB = new MockToken("Token B", "TB");

    MockStrategy private strategyA;
    MockStrategy private strategyB;

    AssetGroupRegistry private assetGroupRegistry = new AssetGroupRegistry();
    ISpoolAccessControl accessControl = new SpoolAccessControl();
    SmartVault private vault;
    MockSmartVaultManager private smartVaultManager;
    MockStrategyRegistry private strategyRegistry;
    MasterWallet private masterWallet;

    function setUp() public {
        masterWallet = new MasterWallet(accessControl);
        strategyA = new MockStrategy("StratA", strategyRegistry, assetGroupRegistry);
        strategyB = new MockStrategy("StratB", strategyRegistry, assetGroupRegistry);
        vault = new SmartVault("MySmartVault", accessControl);
        IUsdPriceFeedManager priceFeedManager = new MockPriceFeedManager();
        strategyRegistry = new MockStrategyRegistry(masterWallet, accessControl, priceFeedManager);
        smartVaultManager = new MockSmartVaultManager(
            accessControl,
            strategyRegistry,
            priceFeedManager,
            assetGroupRegistry,
            masterWallet,
            new ActionManager(),
            new GuardManager(),
            new Swapper()
        );

        strategies = Arrays.toArray(address(strategyA), address(strategyB));
        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(tokenA), address(tokenB)));

        // Ratios arbitrary -> vault sync normalizes to $ based on stored exchange rates
        strategyA.initialize(assetGroupId, Arrays.toArray(999, 999));
        strategyB.initialize(assetGroupId, Arrays.toArray(999, 999));
        vault.initialize();

        accessControl.grantRole(ROLE_SMART_VAULT, address(vault));
        accessControl.grantRole(ROLE_RISK_PROVIDER, riskProvider);
        accessControl.grantRole(ROLE_SMART_VAULT_MANAGER, address(smartVaultManager));

        strategyRegistry.registerStrategy(strategies[0]);
        strategyRegistry.registerStrategy(strategies[1]);
        smartVaultManager.registerSmartVault(
            address(vault),
            SmartVaultRegistrationForm({
                assetGroupId: assetGroupId,
                strategies: strategies,
                strategyAllocations: Arrays.toArray(400, 600),
                riskProvider: riskProvider
            })
        );
    }

    function test_vaultSync_deposit() public {
        uint256[] memory exchangeRates = Arrays.toArray(10 ** 26, 10 ** 26);
        uint256[][] memory flushedDeposits = new uint256[][](2);
        flushedDeposits[0] = Arrays.toArray(40 ether, 120 ether);
        flushedDeposits[1] = Arrays.toArray(60 ether, 180 ether);

        deal(address(strategyA), address(strategyA), 1000 ether, true);
        deal(address(strategyB), address(strategyB), 1000 ether, true);

        vm.prank(address(strategyA));
        strategyA.approve(address(smartVaultManager), 1000 ether);
        vm.prank(address(strategyB));
        strategyB.approve(address(smartVaultManager), 1000 ether);

        smartVaultManager.setData(
            VaultManagerData({
                smartVault: address(vault),
                flushIndex: 0,
                strategies: strategies,
                dhwIndexes: Arrays.toArray(0, 0),
                vaultDeposits: Arrays.toArray(100 ether, 300 ether),
                flushedDeposits: flushedDeposits
            })
        );

        strategyRegistry.setData(
            StrategyRegistryData({
                strategy: strategies[0],
                dhwIndex: 0,
                sharesMinted: 1000 ether,
                deposits: Arrays.toArray(80 ether, 240 ether),
                slippages: Arrays.toArray(0, 0),
                exchangeRates: exchangeRates,
                assetGroup: Arrays.toArray(address(tokenA), address(tokenB))
            })
        );

        strategyRegistry.setData(
            StrategyRegistryData({
                strategy: strategies[1],
                dhwIndex: 0,
                sharesMinted: 1000 ether,
                deposits: Arrays.toArray(60 ether, 180 ether),
                slippages: Arrays.toArray(0, 0),
                exchangeRates: exchangeRates,
                assetGroup: Arrays.toArray(address(tokenA), address(tokenB))
            })
        );

        assertEq(vault.totalSupply(), 0);
        assertEq(strategyA.balanceOf(address(vault)), 0);
        assertEq(strategyB.balanceOf(address(vault)), 0);

        smartVaultManager.syncSmartVault(address(vault));

        assertEq(strategyA.balanceOf(address(vault)), 500 ether);
        assertEq(strategyB.balanceOf(address(vault)), 1000 ether);
        assertEq(strategyA.totalSupply(), 1000 ether);
        assertEq(strategyB.totalSupply(), 1000 ether);
        assertEq(vault.totalSupply(), 1000 ether);
    }
}
