// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../../../src/external/interfaces/weth/IWETH9.sol";
import "../../../src/strategies/GearboxV3AirdropStrategy.sol";
import "../../fixtures/TestFixture.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/Constants.sol";
import "../ForkTestFixture.sol";
import "../StrategyHarness.sol";

address constant REZ_TOKEN_ADDRESS = 0x3B50805453023a91a8bf641e279401a0b23FA6F9;

contract GearboxV3AirdropStrategyWethTest is TestFixture, ForkTestFixture {
    event AirdropTokenUpdated(address indexed token, bool isAirdropToken);

    address[] private assetGroup;
    uint256 private assetGroupId;
    uint256[] private assetGroupExchangeRates;

    GearboxV3AirdropStrategyHarness gearboxV3AirdropStrategy;

    // ******* Underlying specific constants **************
    IERC20Metadata tokenUnderlying = IERC20Metadata(WETH);
    IFarmingPool sdToken = IFarmingPool(SDWETH_TOKEN);
    uint256 underlyingPriceUSD = 2300000;
    // ****************************************************

    function setUpForkTestFixture() internal override {
        mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK_EXTENDED_4);
    }

    function setUp() public {
        setUpForkTestFixture();
        vm.selectFork(mainnetForkId);
        setUpBase();

        priceFeedManager.setExchangeRate(address(tokenUnderlying), USD_DECIMALS_MULTIPLIER * underlyingPriceUSD / 1000);

        assetGroup = Arrays.toArray(address(tokenUnderlying));
        assetGroupRegistry.allowTokenBatch(assetGroup);
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);
        assetGroupExchangeRates = SpoolUtils.getExchangeRates(assetGroup, priceFeedManager);

        gearboxV3AirdropStrategy = new GearboxV3AirdropStrategyHarness(
            assetGroupRegistry,
            accessControl,
            swapper
        );

        gearboxV3AirdropStrategy.initialize("GearboxV3AirdropStrategy", assetGroupId, sdToken);

        vm.prank(address(strategyRegistry));
        accessControl.grantRole(ROLE_STRATEGY, address(gearboxV3AirdropStrategy));
    }

    function test_setAirdropToken() public {
        // arrange
        address token = address(0x1);
        address alice = address(0xa);

        // act 1

        // - should revert when called by non-ROLE_SPOOL_ADMIN
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_SPOOL_ADMIN, alice));
        gearboxV3AirdropStrategy.setAirdropToken(token, true);
        vm.stopPrank();

        // - should set airdrop tokens
        vm.expectEmit(true, true, true, true);
        emit AirdropTokenUpdated(token, true);
        gearboxV3AirdropStrategy.setAirdropToken(token, true);

        // act 2
        vm.expectEmit(true, true, true, true);
        emit AirdropTokenUpdated(token, false);
        gearboxV3AirdropStrategy.setAirdropToken(token, false);
    }

    function test_extractAirdrop() public {
        // arrange
        IERC20 rez = IERC20(REZ_TOKEN_ADDRESS);

        address alice = address(0xa);
        address emergencyWithdrawer = address(0xe);
        accessControl.grantRole(ROLE_EMERGENCY_WITHDRAWAL_EXECUTOR, emergencyWithdrawer);

        // - airdrop some REZ tokens to the strategy
        deal(REZ_TOKEN_ADDRESS, address(gearboxV3AirdropStrategy), 100 * 1e18);

        // act

        // - should revert when called by non-ROLE_EMERGENCY_WITHDRAWAL_EXECUTOR
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(MissingRole.selector, ROLE_EMERGENCY_WITHDRAWAL_EXECUTOR, alice));
        gearboxV3AirdropStrategy.extractAirdrop(address(rez));
        vm.stopPrank();

        // - should revert when token is not an airdrop token
        vm.startPrank(emergencyWithdrawer);
        vm.expectRevert(abi.encodeWithSelector(NotAirdropToken.selector));
        gearboxV3AirdropStrategy.extractAirdrop(address(tokenUnderlying));
        vm.stopPrank();

        gearboxV3AirdropStrategy.setAirdropToken(REZ_TOKEN_ADDRESS, true);

        // - should extract airdrop
        vm.startPrank(emergencyWithdrawer);
        gearboxV3AirdropStrategy.extractAirdrop(address(rez));
        vm.stopPrank();

        // assert
        assertEq(rez.balanceOf(address(gearboxV3AirdropStrategy)), 0);
        assertEq(rez.balanceOf(EXTRACTION_ADDRESS), 100 * 1e18);
    }
}

// Exposes protocol-specific functions for unit-testing.
contract GearboxV3AirdropStrategyHarness is GearboxV3AirdropStrategy, StrategyHarness {
    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, ISwapper swapper_)
        GearboxV3AirdropStrategy(assetGroupRegistry_, accessControl_, swapper_)
    {}
}
