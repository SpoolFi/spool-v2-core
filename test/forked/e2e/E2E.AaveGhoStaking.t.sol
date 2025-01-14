// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../../mocks/MockExchange.sol";
import "../ForkTestFixtureDeployment.sol";

contract E2E_AaveGhoStaking is ForkTestFixtureDeployment {
    function setUpForkTestFixture() internal override {
        mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK_EXTENDED_6);
    }

    function setUp() public {
        _deploy(Extended.AAVE_GHO_STAKING_ROUND_0);
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

    function _dealUsdc(address to, uint256 amount) internal {
        vm.startPrank(USDC_WHALE);
        usdc.transfer(to, amount);
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

        IERC20Metadata gho = strategy.gho();
        IStakedGho stakedGho = strategy.stakedGho();
        uint256 usdcMultiplier = 10 ** IERC20Metadata(address(usdc)).decimals();
        uint256 ghoMultiplier = 10 ** gho.decimals();

        MockExchange usdcGhoExchange = new MockExchange(usdc, gho, _deploySpool.usdPriceFeedManager());
        _dealUsdc(address(usdcGhoExchange), 1_000_000 * usdcMultiplier);
        deal(address(gho), address(usdcGhoExchange), 1_000_000 * ghoMultiplier);
        vm.startPrank(_spoolAdmin);
        _deploySpool.swapper().updateExchangeAllowlist(Arrays.toArray(address(usdcGhoExchange)), Arrays.toArray(true));
        vm.stopPrank();

        address alice = address(0xa);
        _dealUsdc(alice, 10_000 * usdcMultiplier);

        ISmartVault smartVault =
            _createVault(0, 0, assetGroupIdUsdc, Arrays.toArray(strategyAddress), uint16a16.wrap(100_00), address(0));

        // initial deposit
        {
            uint256 depositNftId = _deposit(smartVault, alice, 1_000 * usdcMultiplier);
            _flushVaults(smartVault);

            // - DHW
            DoHardWorkParameterBag memory dhwParamBag = _generateDefaultDhwParameterBag(Arrays.toArray(strategyAddress));

            uint256[] memory slippages = new uint256[](3);
            slippages[0] = 0; // dhw with deposit selector
            slippages[1] = Arrays.toPackedRange(999 * usdcMultiplier, 1001 * usdcMultiplier); // before deposit check
            slippages[2] = Arrays.toPackedRange(0, 0); // before withdrawal check
            slippages = _encodeSwapToSlippages( // swap data USDC -> GHO
            usdcGhoExchange, address(usdc), 1_000 * usdcMultiplier, slippages);
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

            assertEq(stakedGho.balanceOf(address(strategy)), 1009793843083534134956, "stakedGho -> strategy");
            assertEq(strategy.totalSupply(), 1009739283922192331606000, "strategy -> total supply");
            assertEq(strategy.balanceOf(address(smartVault)), 1009739283921192331606000, "strategy -> smartVault");
            assertEq(smartVault.totalSupply(), 1009739283921192331606000, "smartVault -> total supply");
            assertEq(smartVault.balanceOf(alice), 1009739283920192331606000, "alice -> smartVault");
        }
    }
}
