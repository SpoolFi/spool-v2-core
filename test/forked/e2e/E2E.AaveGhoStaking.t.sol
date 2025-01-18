// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../../mocks/MockAggregatorV3.sol";
import "../../mocks/MockExchange.sol";
import {MockStrategyNonAtomic} from "../../mocks/MockStrategyNonAtomic.sol";
import "../ForkTestFixtureDeployment.sol";

contract E2E_AaveGhoStaking is ForkTestFixtureDeployment {
    IERC20Metadata gho;
    IERC20Metadata aave;
    IStakedGho stakedGho;

    uint256 usdcMultiplier;
    uint256 ghoMultiplier;
    uint256 aaveMultiplier;

    MockExchange usdcGhoExchange;
    MockExchange usdcAaveExchange;

    address alice;

    function setUpForkTestFixture() internal override {
        mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK_EXTENDED_6);
    }

    function setUp() public {
        _deploy(Extended.AAVE_GHO_STAKING_ROUND_0);

        gho = IERC20Metadata(GHO);
        aave = IERC20Metadata(AAVE);
        stakedGho = IStakedGho(STAKED_GHO);

        usdcMultiplier = 10 ** IERC20Metadata(address(usdc)).decimals();
        ghoMultiplier = 10 ** gho.decimals();
        aaveMultiplier = 10 ** aave.decimals();

        alice = address(0xa);

        AggregatorV3Interface aaveAggregator = new SimpleMockAggregatorV3(
            8, "AAVE / USD", 1, 280_00000000
        );
        AggregatorV3Interface ghoAggregator = new SimpleMockAggregatorV3(
            8, "GHO / USD", 1, 1_00000000
        );
        AggregatorV3Interface usdcAggregator = new SimpleMockAggregatorV3(
            8, "USDC / USD", 1, 1_00000000
        );

        vm.startPrank(_spoolAdmin);
        _deploySpool.usdPriceFeedManager().setAsset(address(aave), aaveAggregator, true, 3780);
        _deploySpool.usdPriceFeedManager().setAsset(address(gho), ghoAggregator, true, 3780);
        _deploySpool.usdPriceFeedManager().setAsset(address(usdc), usdcAggregator, true, 3780);
        vm.stopPrank();

        usdcGhoExchange = new MockExchange(usdc, gho, _deploySpool.usdPriceFeedManager());
        usdcAaveExchange = new MockExchange(usdc, aave, _deploySpool.usdPriceFeedManager());

        _dealUsdc(address(usdcGhoExchange), 1_000_000 * usdcMultiplier);
        deal(address(gho), address(usdcGhoExchange), 1_000_000 * ghoMultiplier);
        _dealUsdc(address(usdcAaveExchange), 1_000_000 * usdcMultiplier);
        _dealAave(address(usdcAaveExchange), 1_000_000 * aaveMultiplier);

        vm.startPrank(_spoolAdmin);
        _deploySpool.swapper().updateExchangeAllowlist(Arrays.toArray(address(usdcGhoExchange)), Arrays.toArray(true));
        _deploySpool.swapper().updateExchangeAllowlist(Arrays.toArray(address(usdcAaveExchange)), Arrays.toArray(true));
        vm.stopPrank();

        vm.startPrank(_spoolAdmin);
        _deploySpool.spoolAccessControl().grantRole(ROLE_EMERGENCY_WITHDRAWAL_EXECUTOR, _emergencyWallet);
        vm.stopPrank();
    }

    function _encodeSwapToSlippages(
        MockExchange exchange,
        address tokenIn,
        uint256 toSwap,
        uint256[] memory otherSlippages
    ) internal view returns (uint256[] memory slippages) {
        bytes memory swapCallData = abi.encodeCall(exchange.swap, (tokenIn, toSwap, address(_deploySpool.swapper())));
        uint256[] memory encodedSwapCallData = BytesUint256Lib.encode(swapCallData);

        uint256 otherSlippagesLength = otherSlippages.length;

        slippages = new uint256[](otherSlippagesLength + 2 + encodedSwapCallData.length);
        for (uint256 i; i < otherSlippagesLength; ++i) {
            slippages[i] = otherSlippages[i];
        }
        slippages[otherSlippagesLength] = uint256(uint160(address(exchange)));
        slippages[otherSlippagesLength + 1] = swapCallData.length;
        for (uint256 i; i < encodedSwapCallData.length; ++i) {
            slippages[otherSlippagesLength + 2 + i] = encodedSwapCallData[i];
        }
    }

    function _encodeSwapToBytes(MockExchange exchange, address tokenIn, uint256 toSwap)
        internal
        view
        returns (bytes memory data)
    {
        bytes memory swapCallData = abi.encodeCall(exchange.swap, (tokenIn, toSwap, address(_deploySpool.swapper())));

        data = abi.encode(address(exchange), swapCallData);
    }

    function _dealUsdc(address to, uint256 amount) internal {
        vm.startPrank(USDC_WHALE);
        usdc.transfer(to, amount);
        vm.stopPrank();
    }

    function _dealAave(address to, uint256 amount) internal {
        vm.startPrank(address(0x4da27a545c0c5B758a6BA100e3a049001de870f5));
        IERC20(AAVE).transfer(to, amount);
        vm.stopPrank();
    }

    function test_deploySpool() public {
        uint256 assetGroupIdUsdc = _getAssetGroupId(USDC_KEY);

        address strategyAddress = _getStrategyAddress(AAVE_GHO_STAKING_KEY, assetGroupIdUsdc);
        AaveGhoStakingStrategy strategy = AaveGhoStakingStrategy(strategyAddress);

        assertEq(strategy.strategyName(), "aave-gho-staking-usdc");
        assertEq(strategy.assetGroupId(), assetGroupIdUsdc);
    }

    function test_basicFlow_usdc() public {
        uint256 assetGroupIdUsdc = _getAssetGroupId(USDC_KEY);

        address strategyAddress = _getStrategyAddress(AAVE_GHO_STAKING_KEY, assetGroupIdUsdc);
        AaveGhoStakingStrategy strategy = AaveGhoStakingStrategy(strategyAddress);

        address[] memory strategies = Arrays.toArray(strategyAddress);

        _dealUsdc(alice, 10_000 * usdcMultiplier);

        ISmartVault smartVault = _createVault(0, 0, assetGroupIdUsdc, strategies, uint16a16.wrap(100_00), address(0));

        // initial deposit
        {
            uint256 depositNftId = _deposit(smartVault, alice, 1_000 * usdcMultiplier);
            _flushVaults(smartVault);

            // - DHW
            DoHardWorkParameterBag memory dhwParamBag = _generateDefaultDhwParameterBag(strategies);

            uint256[] memory slippages = new uint256[](3);
            slippages[0] = 0; // dhw with deposit selector
            slippages[1] = Arrays.toPackedRange(999 * usdcMultiplier, 1001 * usdcMultiplier); // before deposit check
            slippages[2] = Arrays.toPackedRange(0, 0); // before redeemal check
            slippages = _encodeSwapToSlippages(usdcGhoExchange, address(usdc), 1_000 * usdcMultiplier, slippages);
            dhwParamBag.strategySlippages[0][0] = slippages;

            vm.startPrank(_doHardWorker);
            _strategyRegistry.doHardWork(dhwParamBag);
            vm.stopPrank();

            // - claim
            _smartVaultManager.syncSmartVault(address(smartVault), true);

            vm.startPrank(alice);
            _smartVaultManager.claimSmartVaultTokens(
                address(smartVault), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );

            assertEq(usdc.balanceOf(alice), 9_000 * usdcMultiplier, "usdc -> alice");
            assertEq(stakedGho.balanceOf(strategyAddress), 1000_000000000000000000, "stakedGho -> strategy");
            assertEq(strategy.totalSupply(), 1000000000000000000000000, "strategy -> total supply");
            assertEq(strategy.balanceOf(address(smartVault)), 999999999999000000000000, "strategy -> smartVault");
            assertEq(smartVault.totalSupply(), 999999999999000000000000, "smartVault -> total supply");
            assertEq(smartVault.balanceOf(alice), 999999999998000000000000, "smartVault -> alice");
        }

        // deposit without compound
        {
            uint256 depositNftId = _deposit(smartVault, alice, 2_000 * usdcMultiplier);
            _flushVaults(smartVault);

            // - DHW
            DoHardWorkParameterBag memory dhwParamBag = _generateDefaultDhwParameterBag(strategies);

            uint256[] memory slippages = new uint256[](3);
            slippages[0] = 0; // dhw with deposit selector
            slippages[1] = Arrays.toPackedRange(1999 * usdcMultiplier, 2001 * usdcMultiplier); // before deposit check
            slippages[2] = Arrays.toPackedRange(0, 0); // before redeemal check
            slippages = _encodeSwapToSlippages(usdcGhoExchange, address(usdc), 2_000 * usdcMultiplier, slippages);
            dhwParamBag.strategySlippages[0][0] = slippages;

            vm.startPrank(_doHardWorker);
            _strategyRegistry.doHardWork(dhwParamBag);
            vm.stopPrank();

            // - claim
            _smartVaultManager.syncSmartVault(address(smartVault), true);

            vm.startPrank(alice);
            _smartVaultManager.claimSmartVaultTokens(
                address(smartVault), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );

            assertEq(usdc.balanceOf(alice), 7_000 * usdcMultiplier, "usdc -> alice");
            assertEq(stakedGho.balanceOf(strategyAddress), 3000_000000000000000000, "stakedGho -> strategy");
            assertEq(strategy.totalSupply(), 3000000000000000000000000, "strategy -> total supply");
            assertEq(strategy.balanceOf(address(smartVault)), 2999999999999000000000000, "strategy -> smartVault");
            assertEq(smartVault.totalSupply(), 2999999999999000000000000, "smartVault -> total supply");
            assertEq(smartVault.balanceOf(alice), 2999999999998000000000000, "smartVault -> alice");
        }

        // withdraw - async
        {
            vm.startPrank(alice);
            uint256 withdrawalNftId = _smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVault),
                    shares: 1000000000000000000000000,
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );
            vm.stopPrank();
            _flushVaults(smartVault);

            // - DHW
            DoHardWorkParameterBag memory dhwParamBag = _generateDefaultDhwParameterBag(strategies);

            uint256[] memory slippages = new uint256[](3);
            slippages[0] = 1; // dhw with withdrawal selector
            slippages[1] = Arrays.toPackedRange(0, 0); // before deposit check
            slippages[2] = Arrays.toPackedRange(999000000000000000000000, 1000100000000000000000000); // before redeemal check
            dhwParamBag.strategySlippages[0][0] = slippages;

            vm.startPrank(_doHardWorker);
            _strategyRegistry.doHardWork(dhwParamBag);
            vm.stopPrank();

            assertEq(usdc.balanceOf(alice), 7_000 * usdcMultiplier, "usdc -> alice");
            assertEq(stakedGho.balanceOf(strategyAddress), 3000_000000000000000000, "stakedGho -> strategy");
            assertEq(strategy.totalSupply(), 3000000000000000000000000, "strategy -> total supply");
            assertEq(strategy.balanceOf(address(smartVault)), 1999999999999000000000000, "strategy -> smartVault");
            assertEq(smartVault.totalSupply(), 1999999999999000000000000, "smartVault -> total supply");
            assertEq(smartVault.balanceOf(alice), 1999999999998000000000000, "smartVault -> alice");

            // - wait 20 days
            vm.roll(block.number + 100);
            skip(20 * 24 * 60 * 60);

            // - DHW continue
            DoHardWorkContinuationParameterBag memory dhwContinueParamBag =
                _generateDefaultDhwContinuationParameterBag(strategies);

            bytes memory continuationData = _encodeSwapToBytes(usdcGhoExchange, address(gho), 1000 * ghoMultiplier);
            dhwContinueParamBag.continuationData[0][0] = continuationData;

            vm.startPrank(_doHardWorker);
            _strategyRegistry.doHardWorkContinue(dhwContinueParamBag);
            vm.stopPrank();

            // - claim
            _smartVaultManager.syncSmartVault(address(smartVault), true);

            vm.startPrank(alice);
            _smartVaultManager.claimWithdrawal(
                address(smartVault), Arrays.toArray(withdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();

            assertEq(usdc.balanceOf(alice), 8_000 * usdcMultiplier, "usdc -> alice");
            assertEq(stakedGho.balanceOf(strategyAddress), 2000_000000000000000000, "stakedGho -> strategy");
            assertEq(strategy.totalSupply(), 2000000000000000000000000, "strategy -> total supply");
            assertEq(strategy.balanceOf(address(smartVault)), 1999999999999000000000000, "strategy -> smartVault");
            assertEq(smartVault.totalSupply(), 1999999999999000000000000, "smartVault -> total supply");
            assertEq(smartVault.balanceOf(alice), 1999999999998000000000000, "smartVault -> alice");
        }

        // withdraw - sync
        {
            vm.startPrank(alice);
            uint256 withdrawalNftId = _smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVault),
                    shares: 500000000000000000000000,
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );
            vm.stopPrank();
            _flushVaults(smartVault);

            // - DHW
            DoHardWorkParameterBag memory dhwParamBag = _generateDefaultDhwParameterBag(strategies);

            uint256[] memory slippages = new uint256[](3);
            slippages[0] = 1; // dhw with withdrawal selector
            slippages[1] = Arrays.toPackedRange(0, 0); // before deposit check
            slippages[2] = Arrays.toPackedRange(499000000000000000000000, 501000000000000000000000); // before redeemal check
            slippages = _encodeSwapToSlippages(usdcGhoExchange, address(gho), 500 * ghoMultiplier, slippages);
            dhwParamBag.strategySlippages[0][0] = slippages;

            vm.startPrank(_doHardWorker);
            _strategyRegistry.doHardWork(dhwParamBag);
            vm.stopPrank();

            // - claim
            _smartVaultManager.syncSmartVault(address(smartVault), true);

            vm.startPrank(alice);
            _smartVaultManager.claimWithdrawal(
                address(smartVault), Arrays.toArray(withdrawalNftId), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();

            assertEq(usdc.balanceOf(alice), 8_500 * usdcMultiplier, "usdc -> alice");
            assertEq(stakedGho.balanceOf(strategyAddress), 1500_000000000000000000, "stakedGho -> strategy");
            assertEq(strategy.totalSupply(), 1500000000000000000000000, "strategy -> total supply");
            assertEq(strategy.balanceOf(address(smartVault)), 1499999999999000000000000, "strategy -> smartVault");
            assertEq(smartVault.totalSupply(), 1499999999999000000000000, "smartVault -> total supply");
            assertEq(smartVault.balanceOf(alice), 1499999999998000000000000, "smartVault -> alice");
        }

        // redeem fast
        {
            uint256[][] memory slippages = new uint256[][](1);
            slippages[0] = new uint256[](1);
            slippages[0][0] = 3; // redeem fast selector
            slippages[0] = _encodeSwapToSlippages(usdcGhoExchange, address(gho), 500 * ghoMultiplier, slippages[0]);

            vm.startPrank(alice);
            _smartVaultManager.redeemFast(
                RedeemBag({
                    smartVault: address(smartVault),
                    shares: 500000000000000000000000,
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                slippages
            );
            vm.stopPrank();

            assertEq(usdc.balanceOf(alice), 9_000 * usdcMultiplier, "usdc -> alice");
            assertEq(stakedGho.balanceOf(strategyAddress), 1000_000000000000000000, "stakedGho -> strategy");
            assertEq(strategy.totalSupply(), 1000000000000000000000000, "strategy -> total supply");
            assertEq(strategy.balanceOf(address(smartVault)), 999999999999000000000000, "strategy -> smartVault");
            assertEq(smartVault.totalSupply(), 999999999999000000000000, "smartVault -> total supply");
            assertEq(smartVault.balanceOf(alice), 999999999998000000000000, "smartVault -> alice");
        }

        // deposit only compound
        {
            _prankOrigin(address(0), address(0));
            (address[] memory tokens, uint256[] memory amounts) = strategy.getProtocolRewards();
            vm.stopPrank();

            assertEq(tokens.length, 1, "tokens length");
            assertEq(tokens[0], address(aave), "tokens[0]");
            assertEq(amounts[0], 49993426897104000, "amounts[0]");

            // - DHW
            DoHardWorkParameterBag memory dhwParamBag = _generateDefaultDhwParameterBag(strategies);

            SwapInfo[] memory swapInfo = new SwapInfo[](1);
            swapInfo[0] = SwapInfo({
                swapTarget: address(usdcAaveExchange),
                token: address(aave),
                swapCallData: abi.encodeCall(
                    usdcAaveExchange.swap, (address(aave), 49993426897104000, address(_deploySpool.swapper()))
                    )
            });
            dhwParamBag.compoundSwapInfo[0][0] = swapInfo;

            uint256[] memory slippages = new uint256[](3);
            slippages[0] = 0; // dhw with deposit selector
            slippages[1] = Arrays.toPackedRange(0, 0); // before deposit check
            slippages[2] = Arrays.toPackedRange(0, 0); // before redeemal check
            slippages = _encodeSwapToSlippages(usdcGhoExchange, address(usdc), 13_998159, slippages);
            dhwParamBag.strategySlippages[0][0] = slippages;

            vm.startPrank(_doHardWorker);
            _strategyRegistry.doHardWork(dhwParamBag);
            vm.stopPrank();

            assertEq(usdc.balanceOf(alice), 9_000 * usdcMultiplier, "usdc -> alice");
            assertEq(stakedGho.balanceOf(strategyAddress), 1013_998159000000000000, "stakedGho -> strategy");
            assertEq(strategy.totalSupply(), 1001382399951114437094124, "strategy -> total supply");
            assertEq(strategy.balanceOf(address(smartVault)), 999999999999000000000000, "strategy -> smartVault");
            assertEq(strategy.balanceOf(_feeRecipient), 1382399951114437094124, "strategy -> feeRecipient");
            assertEq(smartVault.totalSupply(), 999999999999000000000000, "smartVault -> total supply");
            assertEq(smartVault.balanceOf(alice), 999999999998000000000000, "smartVault -> alice");
        }

        // redeem shares - sync
        {
            uint256[][] memory slippages = new uint256[][](1);
            slippages[0] = new uint256[](1);
            slippages[0][0] = 3; // redeem fast selector
            slippages[0] = _encodeSwapToSlippages(usdcGhoExchange, address(gho), 1_399815899999999999, slippages[0]);

            vm.startPrank(_feeRecipient);
            _strategyRegistry.redeemStrategyShares(strategies, Arrays.toArray(1382399951114437094124), slippages);
            vm.stopPrank();

            assertEq(usdc.balanceOf(alice), 9_000 * usdcMultiplier, "usdc -> alice");
            assertEq(usdc.balanceOf(_feeRecipient), 1_399815, "usdc -> feeRecipient");
            assertEq(stakedGho.balanceOf(strategyAddress), 1012_598343100000000001, "stakedGho -> strategy");
            assertEq(strategy.totalSupply(), 1000000000000000000000000, "strategy -> total supply");
            assertEq(strategy.balanceOf(address(smartVault)), 999999999999000000000000, "strategy -> smartVault");
            assertEq(strategy.balanceOf(_feeRecipient), 0, "strategy -> feeRecipient");
            assertEq(smartVault.totalSupply(), 999999999999000000000000, "smartVault -> total supply");
            assertEq(smartVault.balanceOf(alice), 999999999998000000000000, "smartVault -> alice");
        }

        // emergency withdrawal
        {
            // - wait 10 days
            vm.roll(block.number + 100);
            skip(10 * 24 * 60 * 60);

            // - emergency withdraw - trigger cooldown
            uint256[][] memory slippages = new uint256[][](1);
            slippages[0] = new uint256[](0);

            vm.startPrank(_emergencyWallet);
            _strategyRegistry.emergencyWithdraw(strategies, slippages, false);
            vm.stopPrank();

            assertEq(usdc.balanceOf(alice), 9_000 * usdcMultiplier, "usdc -> alice");
            assertEq(usdc.balanceOf(_feeRecipient), 1_399815, "usdc -> feeRecipient");
            assertEq(stakedGho.balanceOf(strategyAddress), 1012_598343100000000001, "stakedGho -> strategy");
            assertEq(strategy.totalSupply(), 1000000000000000000000000, "strategy -> total supply");
            assertEq(strategy.balanceOf(address(smartVault)), 999999999999000000000000, "strategy -> smartVault");
            assertEq(strategy.balanceOf(_feeRecipient), 0, "strategy -> feeRecipient");
            assertEq(smartVault.totalSupply(), 999999999999000000000000, "smartVault -> total supply");
            assertEq(smartVault.balanceOf(alice), 999999999998000000000000, "smartVault -> alice");

            // - wait 20 days
            vm.roll(block.number + 100);
            skip(20 * 24 * 60 * 60);

            // - emergency withdraw - unstake
            vm.startPrank(_emergencyWallet);
            _strategyRegistry.emergencyWithdraw(strategies, slippages, true);
            vm.stopPrank();

            assertEq(usdc.balanceOf(alice), 9_000 * usdcMultiplier, "usdc -> alice");
            assertEq(usdc.balanceOf(_feeRecipient), 1_399815, "usdc -> feeRecipient");
            assertEq(gho.balanceOf(_emergencyWallet), 1012_598343100000000001, "gho -> emergencyWallet");
            assertEq(stakedGho.balanceOf(strategyAddress), 0, "stakedGho -> strategy");
            assertEq(strategy.totalSupply(), 1000000000000000000000000, "strategy -> total supply");
            assertEq(strategy.balanceOf(address(smartVault)), 999999999999000000000000, "strategy -> smartVault");
            assertEq(strategy.balanceOf(_feeRecipient), 0, "strategy -> feeRecipient");
            assertEq(smartVault.totalSupply(), 999999999999000000000000, "smartVault -> total supply");
            assertEq(smartVault.balanceOf(alice), 999999999998000000000000, "smartVault -> alice");
        }
    }

    function test_reallocationFlow_deposit_usdc() public {
        uint256 assetGroupIdUsdc = _getAssetGroupId(USDC_KEY);

        address strategyAddress = _getStrategyAddress(AAVE_GHO_STAKING_KEY, assetGroupIdUsdc);
        AaveGhoStakingStrategy strategy = AaveGhoStakingStrategy(strategyAddress);

        MockStrategyNonAtomic anotherStrategy = new MockStrategyNonAtomic(
            _deploySpool.assetGroupRegistry(),
            _deploySpool.spoolAccessControl(),
            assetGroupIdUsdc,
            ATOMIC_STRATEGY,
            0,
            true
        );
        anotherStrategy.initialize("another-strategy");
        address anotherStrategyAddress = address(anotherStrategy);
        vm.startPrank(_spoolAdmin);
        _strategyRegistry.registerStrategy(anotherStrategyAddress, 0, ATOMIC_STRATEGY);
        vm.stopPrank();

        address[] memory strategies = Arrays.toArray(strategyAddress, anotherStrategyAddress);

        _dealUsdc(alice, 10_000 * usdcMultiplier);

        vm.mockCall(
            address(_deploySpool.riskManager()),
            abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
            abi.encode(Arrays.toUint16a16(50_00, 50_00))
        );

        // smart vault A is needed to make first deposit into the strategies
        // when initial shares are locked
        // this makes smart vault B to take full shares for its deposit
        // making reallocation calculations easier to calculate by hand
        ISmartVault smartVaultA = _createVault(
            0, 0, assetGroupIdUsdc, strategies, uint16a16.wrap(0), address(_deploySpool.linearAllocationProvider())
        );
        ISmartVault smartVaultB = _createVault(
            0, 0, assetGroupIdUsdc, strategies, uint16a16.wrap(0), address(_deploySpool.linearAllocationProvider())
        );

        // initial deposit into vault A
        {
            uint256 depositNftId = _deposit(smartVaultA, alice, 2_000 * usdcMultiplier);
            _flushVaults(smartVaultA);

            // - DHW
            DoHardWorkParameterBag memory dhwParamBag = _generateDefaultDhwParameterBag(strategies);

            uint256[] memory slippages = new uint256[](3);
            slippages[0] = 0; // dhw with deposit selector
            slippages[1] = Arrays.toPackedRange(1_000 * usdcMultiplier, 1_000 * usdcMultiplier); // before deposit check
            slippages[2] = Arrays.toPackedRange(0, 0); // before redeemal check
            slippages = _encodeSwapToSlippages(usdcGhoExchange, address(usdc), 1_000 * usdcMultiplier, slippages);
            dhwParamBag.strategySlippages[0][0] = slippages;

            vm.startPrank(_doHardWorker);
            _strategyRegistry.doHardWork(dhwParamBag);
            vm.stopPrank();

            // - claim
            _smartVaultManager.syncSmartVault(address(smartVaultA), true);

            vm.startPrank(alice);
            _smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();

            assertEq(usdc.balanceOf(alice), 8_000 * usdcMultiplier, "usdc -> alice");
            assertEq(strategy.totalSupply(), 1000000000000000000000000, "strategy -> total supply");
            assertEq(anotherStrategy.totalSupply(), 1000000000000000000000000, "another strategy -> total supply");
        }

        // initial deposit into vault B
        {
            uint256 depositNftId = _deposit(smartVaultB, alice, 2_000 * usdcMultiplier);
            _flushVaults(smartVaultB);

            // - DHW
            DoHardWorkParameterBag memory dhwParamBag = _generateDefaultDhwParameterBag(strategies);

            uint256[] memory slippages = new uint256[](3);
            slippages[0] = 0; // dhw with deposit selector
            slippages[1] = Arrays.toPackedRange(1_000 * usdcMultiplier, 1_000 * usdcMultiplier); // before deposit check
            slippages[2] = Arrays.toPackedRange(0, 0); // before redeemal check
            slippages = _encodeSwapToSlippages(usdcGhoExchange, address(usdc), 1_000 * usdcMultiplier, slippages);
            dhwParamBag.strategySlippages[0][0] = slippages;

            vm.startPrank(_doHardWorker);
            _strategyRegistry.doHardWork(dhwParamBag);
            vm.stopPrank();

            // - claim
            _smartVaultManager.syncSmartVault(address(smartVaultB), true);

            vm.startPrank(alice);
            _smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftId), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();

            assertEq(usdc.balanceOf(alice), 6_000 * usdcMultiplier, "usdc -> alice");
            assertEq(stakedGho.balanceOf(strategyAddress), 2000_000000000000000000, "stakedGho -> strategy");
            assertEq(strategy.totalSupply(), 2000000000000000000000000, "strategy -> total supply");
            assertEq(strategy.balanceOf(address(smartVaultB)), 1000000000000000000000000, "strategy -> smartVaultB");
            assertEq(anotherStrategy.totalSupply(), 2000000000000000000000000, "another strategy -> total supply");
            assertEq(
                anotherStrategy.balanceOf(address(smartVaultB)),
                1000000000000000000000000,
                "another strategy -> smartVaultB"
            );
            assertEq(smartVaultB.totalSupply(), 2000000000000000000000000, "smartVaultB -> total supply");
            assertEq(smartVaultB.balanceOf(alice), 1999999999999000000000000, "smartVaultB -> alice");
        }

        // reallocation with deposit - smart vault B
        {
            vm.mockCall(
                address(_deploySpool.riskManager()),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toUint16a16(75_00, 25_00))
            );

            ReallocateParamBag memory reallocateParamBag = _generateDefaultReallocateParamBag(smartVaultB);

            uint256[] memory depositSlippages = new uint256[](2);
            depositSlippages[0] = 2; // reallocation selector
            depositSlippages[1] = Arrays.toPackedRange(500 * usdcMultiplier, 500 * usdcMultiplier); // before deposit check
            depositSlippages =
                _encodeSwapToSlippages(usdcGhoExchange, address(usdc), 500 * usdcMultiplier, depositSlippages);
            reallocateParamBag.depositSlippages[0] = depositSlippages;

            uint256[] memory withdrawalSlippages = new uint256[](2);
            withdrawalSlippages[0] = 2; // reallocation selector
            withdrawalSlippages[1] = Arrays.toPackedRange(0, 0); // before redeemal check
            reallocateParamBag.withdrawalSlippages[0] = withdrawalSlippages;

            vm.startPrank(_reallocator);
            _smartVaultManager.reallocate(reallocateParamBag);
            vm.stopPrank();

            assertEq(usdc.balanceOf(alice), 6_000 * usdcMultiplier, "usdc -> alice");
            assertEq(stakedGho.balanceOf(strategyAddress), 2500_000000000000000000, "stakedGho -> strategy");
            assertEq(strategy.totalSupply(), 2500000000000000000000000, "strategy -> total supply");
            assertEq(strategy.balanceOf(address(smartVaultB)), 1500000000000000000000000, "strategy -> smartVaultB");
            assertEq(anotherStrategy.totalSupply(), 1500000000000000000000000, "another strategy -> total supply");
            assertEq(
                anotherStrategy.balanceOf(address(smartVaultB)),
                500000000000000000000000,
                "another strategy -> smartVaultB"
            );
            assertEq(smartVaultB.totalSupply(), 2000000000000000000000000, "smartVaultB -> total supply");
            assertEq(smartVaultB.balanceOf(alice), 1999999999999000000000000, "smartVaultB -> alice");
        }

        // reallocation with withdrawal - smart vault B
        {
            // - emergency withdraw - to trigger cooldown
            uint256[][] memory slippages = new uint256[][](1);
            slippages[0] = new uint256[](0);

            vm.startPrank(_emergencyWallet);
            _strategyRegistry.emergencyWithdraw(Arrays.toArray(strategyAddress), slippages, false);
            vm.stopPrank();

            // - wait 20 days
            vm.roll(block.number + 100);
            skip(20 * 24 * 60 * 60);

            // - reallocate with withdrawal

            vm.mockCall(
                address(_deploySpool.riskManager()),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toUint16a16(25_00, 75_00))
            );

            ReallocateParamBag memory reallocateParamBag = _generateDefaultReallocateParamBag(smartVaultB);

            uint256[] memory depositSlippages = new uint256[](2);
            depositSlippages[0] = 2; // reallocation selector
            depositSlippages[1] = Arrays.toPackedRange(0, 0); // before deposit check
            reallocateParamBag.depositSlippages[0] = depositSlippages;

            uint256[] memory withdrawalSlippages = new uint256[](2);
            withdrawalSlippages[0] = 2; // reallocation selector
            withdrawalSlippages[1] = Arrays.toPackedRange(100000000000000000000000, 10000000000000000000000000); // before redeemal check
            withdrawalSlippages =
                _encodeSwapToSlippages(usdcGhoExchange, address(gho), 1000 * ghoMultiplier, withdrawalSlippages);
            reallocateParamBag.withdrawalSlippages[0] = withdrawalSlippages;

            vm.startPrank(_reallocator);
            _smartVaultManager.reallocate(reallocateParamBag);
            vm.stopPrank();

            assertEq(usdc.balanceOf(alice), 6_000 * usdcMultiplier, "usdc -> alice");
            assertEq(stakedGho.balanceOf(strategyAddress), 1500_000000000000000000, "stakedGho -> strategy");
            assertEq(strategy.totalSupply(), 1500000000000000000000000, "strategy -> total supply");
            assertEq(strategy.balanceOf(address(smartVaultB)), 500000000000000000000000, "strategy -> smartVaultB");
            assertEq(anotherStrategy.totalSupply(), 2500000000000000000000000, "another strategy -> total supply");
            assertEq(
                anotherStrategy.balanceOf(address(smartVaultB)),
                1500000000000000000000000,
                "another strategy -> smartVaultB"
            );
            assertEq(smartVaultB.totalSupply(), 2000000000000000000000000, "smartVaultB -> total supply");
            assertEq(smartVaultB.balanceOf(alice), 1999999999999000000000000, "smartVaultB -> alice");
        }
    }
}
