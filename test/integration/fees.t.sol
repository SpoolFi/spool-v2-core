// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../libraries/Arrays.sol";
import "../libraries/Constants.sol";
import "../fixtures/TestFixture.sol";
import "../mocks/MockStrategy2.sol";

contract PlatformFeesTest is TestFixture {
    address private alice;
    address private bob;
    address private charlie;

    MockStrategy2 private strategyA;
    MockStrategy2 private strategyB;

    address[] private strategiesA;
    address[] private strategiesB;
    address[] private strategies;

    ISmartVault private smartVaultA;
    ISmartVault private smartVaultB;

    uint256 private assetGroupId;
    address[] private assetGroup;

    uint256 private ecosystemFeePct = 6_00;
    uint256 private treasuryFeePct = 4_00;

    function setUp() public {
        setUpBase();

        alice = address(0xa);
        bob = address(0xb);
        charlie = address(0xc);

        strategyRegistry.setEcosystemFee(uint96(ecosystemFeePct));
        strategyRegistry.setTreasuryFee(uint96(treasuryFeePct));

        priceFeedManager.setExchangeRate(address(token), 1 * USD_DECIMALS_MULTIPLIER);
        assetGroup = Arrays.toArray(address(token));
        assetGroupId = assetGroupRegistry.registerAssetGroup(assetGroup);

        // strategies
        {
            strategyA = new MockStrategy2(assetGroupRegistry, accessControl, assetGroupId);
            strategyA.initialize("StratA");
            strategyRegistry.registerStrategy(address(strategyA));

            strategyB = new MockStrategy2(assetGroupRegistry, accessControl, assetGroupId);
            strategyB.initialize("StratB");
            strategyRegistry.registerStrategy(address(strategyB));

            strategiesA = Arrays.toArray(address(strategyA));
            strategiesB = Arrays.toArray(address(strategyB));
            strategies = Arrays.toArray(address(strategyA), address(strategyB));
        }

        // smart vaults
        {
            SmartVaultSpecification memory specification = SmartVaultSpecification({
                smartVaultName: "SmartVaultA",
                assetGroupId: assetGroupId,
                actions: new IAction[](0),
                actionRequestTypes: new RequestType[](0),
                guards: new GuardDefinition[][](0),
                guardRequestTypes: new RequestType[](0),
                strategies: strategiesA,
                strategyAllocation: Arrays.toUint16a16(100_00),
                riskTolerance: 4,
                riskProvider: riskProvider,
                allocationProvider: address(0xabc),
                managementFeePct: 0,
                depositFeePct: 0,
                performanceFeePct: 0,
                allowRedeemFor: false
            });
            smartVaultA = smartVaultFactory.deploySmartVault(specification);

            specification.smartVaultName = "SmartVaultB";
            specification.strategies = strategiesB;
            smartVaultB = smartVaultFactory.deploySmartVault(specification);
        }

        // initial state
        {
            deal(address(token), alice, 1000 ether, true);
            deal(address(token), bob, 1000 ether, true);
            deal(address(token), charlie, 1000 ether, true);

            // deposit
            vm.startPrank(alice);
            token.approve(address(smartVaultManager), 100 ether);
            uint256 depositNftAlice = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(100 ether),
                    receiver: alice,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();
            vm.startPrank(bob);
            token.approve(address(smartVaultManager), 100 ether);
            uint256 depositNftBob = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultB),
                    assets: Arrays.toArray(100 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));
            smartVaultManager.flushSmartVault(address(smartVaultB));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);
            smartVaultManager.syncSmartVault(address(smartVaultB), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftAlice), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultB), Arrays.toArray(depositNftBob), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }
    }

    function test_initialState() public {
        // check initial state
        {
            // - assets were routed to strategy
            assertEq(token.balanceOf(address(strategyA.protocol())), 100 ether);
            assertEq(token.balanceOf(address(strategyB.protocol())), 100 ether);
            assertEq(token.balanceOf(address(masterWallet)), 0 ether);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 100_000000000000000000000);
            assertEq(strategyB.totalSupply(), 100_000000000000000000000);
            // - strategy tokens were distributed
            assertEq(strategyA.balanceOf(address(smartVaultA)), 100_000000000000000000000);
            assertEq(strategyB.balanceOf(address(smartVaultB)), 100_000000000000000000000);
            // - smart vault tokens were minted
            assertEq(smartVaultA.totalSupply(), 100_000000000000000000000);
            assertEq(smartVaultB.totalSupply(), 100_000000000000000000000);
            // - smart vault tokens were distributed
            assertEq(smartVaultA.balanceOf(alice), 100_000000000000000000000);
            assertEq(smartVaultB.balanceOf(bob), 100_000000000000000000000);
        }
    }

    function test_dhw_shouldCorrectlyCalculateBaseYield() public {
        // generate yield
        {
            // donate to protocol to get base yield
            vm.startPrank(charlie);
            token.approve(address(strategyA.protocol()), 60 ether);
            strategyA.protocol().donate(60 ether);
            vm.stopPrank();

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(Arrays.toArray(address(strategyA)), assetGroup));
            vm.stopPrank();
        }

        // check calculated yield
        {
            uint256 lastDhwIndex = strategyRegistry.currentIndex(strategiesA)[0] - 1;
            int256 dhwYield = strategyRegistry.getDhwYield(strategiesA, Arrays.toUint16a16(lastDhwIndex))[0];

            assertEq(dhwYield, YIELD_FULL_PERCENT_INT * 60 / 100, "yield");
        }

        // check collected platform fees
        {
            uint256[] memory shares = new uint256[](1);
            uint256[][] memory withdrawalSlippages = new uint256[][](1);
            withdrawalSlippages[0] = new uint256[](0);
            // collect ecosystem fees
            shares[0] = strategyA.balanceOf(ecosystemFeeRecipient);
            vm.startPrank(ecosystemFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategiesA, shares, withdrawalSlippages);
            vm.stopPrank();
            // collect treasury fees
            shares[0] = strategyA.balanceOf(treasuryFeeRecipient);
            vm.startPrank(treasuryFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategiesA, shares, withdrawalSlippages);
            vm.stopPrank();

            assertApproxEqAbs(
                token.balanceOf(ecosystemFeeRecipient), 60 ether * ecosystemFeePct / FULL_PERCENT, 10, "ecosystem fees"
            );
            assertApproxEqAbs(
                token.balanceOf(treasuryFeeRecipient), 60 ether * treasuryFeePct / FULL_PERCENT, 10, "treasury fees"
            );
        }
    }

    function test_dhw_shouldCorrectlyCalculateCompoundYield() public {
        // generate yield
        {
            // add rewards for strategy to get compound yield
            vm.startPrank(charlie);
            token.approve(address(strategyA.protocol()), 40 ether);
            strategyA.protocol().reward(40 ether, address(strategyA));
            vm.stopPrank();

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(Arrays.toArray(address(strategyA)), assetGroup));
            vm.stopPrank();
        }

        // check calculated yield
        {
            uint256 lastDhwIndex = strategyRegistry.currentIndex(strategiesA)[0] - 1;
            int256 dhwYield = strategyRegistry.getDhwYield(strategiesA, Arrays.toUint16a16(lastDhwIndex))[0];

            assertEq(dhwYield, YIELD_FULL_PERCENT_INT * 40 / 100, "yield");
        }

        // check collected platform fees
        {
            uint256[] memory shares = new uint256[](1);
            uint256[][] memory withdrawalSlippages = new uint256[][](1);
            withdrawalSlippages[0] = new uint256[](0);
            // collect ecosystem fees
            shares[0] = strategyA.balanceOf(ecosystemFeeRecipient);
            vm.startPrank(ecosystemFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategiesA, shares, withdrawalSlippages);
            vm.stopPrank();
            // collect treasury fees
            shares[0] = strategyA.balanceOf(treasuryFeeRecipient);
            vm.startPrank(treasuryFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategiesA, shares, withdrawalSlippages);
            vm.stopPrank();

            assertApproxEqAbs(
                token.balanceOf(ecosystemFeeRecipient), 40 ether * ecosystemFeePct / FULL_PERCENT, 10, "ecosystem fees"
            );
            assertApproxEqAbs(
                token.balanceOf(treasuryFeeRecipient), 40 ether * treasuryFeePct / FULL_PERCENT, 10, "treasury fees"
            );
        }
    }

    function test_dhw_shouldCorrectlyCalculateFullYield() public {
        // generate yield
        {
            vm.startPrank(charlie);
            token.approve(address(strategyA.protocol()), 100 ether);
            // donate to protocol to get base yield
            strategyA.protocol().donate(60 ether);
            // add rewards for strategy to get compound yield
            strategyA.protocol().reward(40 ether, address(strategyA));
            vm.stopPrank();

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(Arrays.toArray(address(strategyA)), assetGroup));
            vm.stopPrank();
        }

        // check calculated yield
        {
            uint256 lastDhwIndex = strategyRegistry.currentIndex(strategiesA)[0] - 1;
            int256 dhwYield = strategyRegistry.getDhwYield(strategiesA, Arrays.toUint16a16(lastDhwIndex))[0];

            assertEq(dhwYield, YIELD_FULL_PERCENT_INT * 100 / 100, "yield");
        }

        // check collected platform fees
        {
            uint256[] memory shares = new uint256[](1);
            uint256[][] memory withdrawalSlippages = new uint256[][](1);
            withdrawalSlippages[0] = new uint256[](0);
            // collect ecosystem fees
            shares[0] = strategyA.balanceOf(ecosystemFeeRecipient);
            vm.startPrank(ecosystemFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategiesA, shares, withdrawalSlippages);
            vm.stopPrank();
            // collect treasury fees
            shares[0] = strategyA.balanceOf(treasuryFeeRecipient);
            vm.startPrank(treasuryFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategiesA, shares, withdrawalSlippages);
            vm.stopPrank();

            assertApproxEqAbs(
                token.balanceOf(ecosystemFeeRecipient), 100 ether * ecosystemFeePct / FULL_PERCENT, 10, "ecosystem fees"
            );
            assertApproxEqAbs(
                token.balanceOf(treasuryFeeRecipient), 100 ether * treasuryFeePct / FULL_PERCENT, 10, "treasury fees"
            );
        }
    }

    function test_dhw_feeCollectionOverMultipleDhws() public {
        // do 10 yield cycles
        for (uint256 i; i < 10; ++i) {
            uint256 yield;

            vm.startPrank(charlie);
            // generate 10% yield
            // strategy A
            yield = token.balanceOf(address(strategyA.protocol())) * 10 / 100;
            token.approve(address(strategyA.protocol()), yield);
            strategyA.protocol().donate(yield);
            // strategy B
            yield = token.balanceOf(address(strategyB.protocol())) * 10 / 100;
            token.approve(address(strategyB.protocol()), yield);
            strategyB.protocol().donate(yield);
            vm.stopPrank();

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategies, assetGroup));
            vm.stopPrank();

            // collect fees for strategy B, but not for strategy A
            uint256[] memory shares = new uint256[](1);
            uint256[][] memory withdrawalSlippages = new uint256[][](1);
            withdrawalSlippages[0] = new uint256[](0);
            // collect ecosystem fees
            shares[0] = strategyB.balanceOf(ecosystemFeeRecipient);
            vm.startPrank(ecosystemFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategiesB, shares, withdrawalSlippages);
            vm.stopPrank();
            // collect treasury fees
            shares[0] = strategyB.balanceOf(treasuryFeeRecipient);
            vm.startPrank(treasuryFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategiesB, shares, withdrawalSlippages);
            vm.stopPrank();
        }

        // collect fees for strategy A
        {
            uint256[] memory shares = new uint256[](1);
            uint256[][] memory withdrawalSlippages = new uint256[][](1);
            withdrawalSlippages[0] = new uint256[](0);
            // collect ecosystem fees
            shares[0] = strategyA.balanceOf(ecosystemFeeRecipient);
            vm.startPrank(ecosystemFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategiesA, shares, withdrawalSlippages);
            vm.stopPrank();
            // collect treasury fees
            shares[0] = strategyA.balanceOf(treasuryFeeRecipient);
            vm.startPrank(treasuryFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategiesA, shares, withdrawalSlippages);
            vm.stopPrank();
        }

        // check that users of both strategies got same amount of tokens
        assertEq(strategyA.totalSupply(), strategyB.totalSupply());
        assertApproxEqAbs(
            token.balanceOf(address(strategyA.protocol())), token.balanceOf(address(strategyB.protocol())), 10
        );
    }

    function test_dhw_shouldCorrectlyCalculateYieldOverMultipleDhws() public {
        // do 3 yield cycles
        for (uint256 i; i < 3; ++i) {
            uint256 yield;

            vm.startPrank(charlie);
            // generate 20% yield
            yield = token.balanceOf(address(strategyA.protocol())) * 20 / 100;
            token.approve(address(strategyA.protocol()), yield);
            strategyA.protocol().donate(yield);
            vm.stopPrank();

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();
        }

        // check calculated yield
        {
            uint256 lastDhwIndex = strategyRegistry.currentIndex(strategiesA)[0] - 1;
            int256 dhwYield = strategyRegistry.getDhwYield(strategiesA, Arrays.toUint16a16(lastDhwIndex))[0];

            // expected yield is 72.8% (= 1.2**3 - 1)
            assertApproxEqAbs(dhwYield, YIELD_FULL_PERCENT_INT * 728 / 1000, 10, "yield");
        }

        // check valut generated value
        {
            uint256[] memory shares = new uint256[](1);
            uint256[][] memory withdrawalSlippages = new uint256[][](1);
            withdrawalSlippages[0] = new uint256[](0);
            // collect ecosystem fees
            shares[0] = strategyA.balanceOf(ecosystemFeeRecipient);
            vm.startPrank(ecosystemFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategiesA, shares, withdrawalSlippages);
            vm.stopPrank();
            // collect treasury fees
            shares[0] = strategyA.balanceOf(treasuryFeeRecipient);
            vm.startPrank(treasuryFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategiesA, shares, withdrawalSlippages);
            vm.stopPrank();

            // what is left are vaults's funds
            // expected yield for valut is 64.3032% (= (1 + (0.2*0.9)**3) - 1)
            assertApproxEqAbs(token.balanceOf(address(strategyA.protocol())), 164.3032 ether, 10);
        }
    }

    function test_dhw_shouldTakeCorrectAmountOfFeesWhenAlsoDepositIsHappening() public {
        // do another deposit
        {
            vm.startPrank(alice);
            token.approve(address(smartVaultManager), 100 ether);
            smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(100 ether),
                    receiver: alice,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            smartVaultManager.flushSmartVault(address(smartVaultA));
        }

        // generate yield
        {
            // add rewards for strategy to get compound yield
            vm.startPrank(charlie);
            token.approve(address(strategyA.protocol()), 20 ether);
            strategyA.protocol().reward(20 ether, address(strategyA));
            vm.stopPrank();

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(Arrays.toArray(address(strategyA)), assetGroup));
            vm.stopPrank();
        }

        // check calculated yield
        {
            uint256 lastDhwIndex = strategyRegistry.currentIndex(strategiesA)[0] - 1;
            int256 dhwYield = strategyRegistry.getDhwYield(strategiesA, Arrays.toUint16a16(lastDhwIndex))[0];

            assertEq(dhwYield, YIELD_FULL_PERCENT_INT * 20 / 100, "yield");
        }

        // check collected platform fees
        {
            uint256[] memory shares = new uint256[](1);
            uint256[][] memory withdrawalSlippages = new uint256[][](1);
            withdrawalSlippages[0] = new uint256[](0);
            // collect ecosystem fees
            shares[0] = strategyA.balanceOf(ecosystemFeeRecipient);
            vm.startPrank(ecosystemFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategiesA, shares, withdrawalSlippages);
            vm.stopPrank();
            // collect treasury fees
            shares[0] = strategyA.balanceOf(treasuryFeeRecipient);
            vm.startPrank(treasuryFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategiesA, shares, withdrawalSlippages);
            vm.stopPrank();

            assertApproxEqAbs(token.balanceOf(ecosystemFeeRecipient), 20 ether * ecosystemFeePct / FULL_PERCENT, 10);
            assertApproxEqAbs(token.balanceOf(treasuryFeeRecipient), 20 ether * treasuryFeePct / FULL_PERCENT, 10);
        }

        // check protocol funds
        {
            // assets were really deposited during DHW
            assertApproxEqAbs(token.balanceOf(address(strategyA.protocol())), 218 ether, 10);
        }
    }

    function test_dhw_shouldTakeCorrectAmountOfFeesWhenAlsoWithdrawingIsHappening() public {
        // do withdrawal
        {
            vm.startPrank(alice);
            smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: smartVaultA.balanceOf(alice) / 2,
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );
            vm.stopPrank();

            smartVaultManager.flushSmartVault(address(smartVaultA));
        }

        // generate yield
        {
            // add rewards for strategy to get compound yield
            vm.startPrank(charlie);
            token.approve(address(strategyA.protocol()), 20 ether);
            strategyA.protocol().reward(20 ether, address(strategyA));
            vm.stopPrank();

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(Arrays.toArray(address(strategyA)), assetGroup));
            vm.stopPrank();
        }

        // check calculated yield
        {
            uint256 lastDhwIndex = strategyRegistry.currentIndex(strategiesA)[0] - 1;
            int256 dhwYield = strategyRegistry.getDhwYield(strategiesA, Arrays.toUint16a16(lastDhwIndex))[0];

            assertEq(dhwYield, YIELD_FULL_PERCENT_INT * 20 / 100, "yield");
        }

        // check collected platform fees
        {
            uint256[] memory shares = new uint256[](1);
            uint256[][] memory withdrawalSlippages = new uint256[][](1);
            withdrawalSlippages[0] = new uint256[](0);
            // collect ecosystem fees
            shares[0] = strategyA.balanceOf(ecosystemFeeRecipient);
            vm.startPrank(ecosystemFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategiesA, shares, withdrawalSlippages);
            vm.stopPrank();
            // collect treasury fees
            shares[0] = strategyA.balanceOf(treasuryFeeRecipient);
            vm.startPrank(treasuryFeeRecipient);
            strategyRegistry.redeemStrategyShares(strategiesA, shares, withdrawalSlippages);
            vm.stopPrank();

            assertApproxEqAbs(token.balanceOf(ecosystemFeeRecipient), 20 ether * ecosystemFeePct / FULL_PERCENT, 10);
            assertApproxEqAbs(token.balanceOf(treasuryFeeRecipient), 20 ether * treasuryFeePct / FULL_PERCENT, 10);
        }

        // check protocol funds
        {
            // assets were really withdrawn during DHW
            assertApproxEqAbs(token.balanceOf(address(strategyA.protocol())), 59 ether, 10);
        }
    }
}
