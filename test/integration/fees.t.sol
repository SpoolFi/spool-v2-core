// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

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

contract SmartVaultFeesTest is TestFixture {
    address private alice;
    address private bob;
    address private charlie;
    address private vaultOwner;

    MockStrategy2 private strategyA;

    address[] private strategiesA;

    ISmartVault private smartVaultA;

    uint256 private assetGroupId;
    address[] private assetGroup;

    uint256 private ecosystemFeePct = 0;
    uint256 private treasuryFeePct = 0;
    uint16 private managementFeePct = 2_00;
    uint16 private depositFeePct = 5_00;
    uint16 private performanceFeePct = 10_00;

    function setUp() public {
        setUpBase();

        alice = address(0xa);
        bob = address(0xb);
        charlie = address(0xc);
        vaultOwner = address(0xf);

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

            strategiesA = Arrays.toArray(address(strategyA));
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
                managementFeePct: managementFeePct,
                depositFeePct: depositFeePct,
                performanceFeePct: performanceFeePct,
                allowRedeemFor: false
            });
            vm.prank(vaultOwner);
            smartVaultA = smartVaultFactory.deploySmartVault(specification);
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

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftAlice), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }
    }

    function _getUserValue(address user, ISmartVault smartVault) private view returns (uint256) {
        uint256 totalShares = smartVault.totalSupply();
        uint256 userShares = smartVault.balanceOf(user);
        address strategy = smartVaultManager.strategies(address(smartVault))[0];
        MockProtocol2 protocol = MockStrategy2(strategy).protocol();
        uint256 totalUnderlying = token.balanceOf(address(protocol));

        return totalUnderlying * userShares / totalShares;
    }

    function test_initialState() public {
        // check initial state
        {
            // - assets were routed to strategy
            assertEq(token.balanceOf(address(strategyA.protocol())), 100 ether);
            assertEq(token.balanceOf(address(masterWallet)), 0 ether);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 100_000000000000000000000);
            // - strategy tokens were distributed
            assertEq(strategyA.balanceOf(address(smartVaultA)), 100_000000000000000000000);
            // - smart vault tokens were minted
            assertEq(smartVaultA.totalSupply(), 100_000000000000000000000);
            // - smart vault tokens were distributed and deposit fee taken
            assertEq(smartVaultA.balanceOf(alice), 95_000000000000000000000);
            assertEq(smartVaultA.balanceOf(vaultOwner), 5_000000000000000000000);
        }
    }

    function test_depositFees_shouldCollect() public {
        // check fees
        {
            // Alice deposited 100 eth
            // - 5 eth or 5% should go as deposit fee
            // - 95 eth or 95% should go to Alice
            assertEq(_getUserValue(alice, smartVaultA), 95 ether);
            assertEq(_getUserValue(vaultOwner, smartVaultA), 5 ether);
        }
    }

    function test_depositFees_multipleDepositsAndWithdrawals() public {
        // do deposits and withdrawals
        {
            vm.startPrank(alice);
            // Alice deposits 100 eth to smart vault A
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
            // Alice withdraws half her eth from smart vault A
            uint256 withdrawalNftAlice = smartVaultManager.redeem(
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
            vm.startPrank(bob);
            // Bob also deposits 100 eth to smart vault A
            token.approve(address(smartVaultManager), 100 ether);
            uint256 depositNftBob = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(100 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftAlice), Arrays.toArray(NFT_MINTED_SHARES)
            );
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftAlice), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftBob), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state and fees
        {
            // Alice deposited 100 eth and withdrew 47.5 eth
            // Bob deposited 100 eth
            assertEq(token.balanceOf(alice), 847.5 ether);
            assertEq(token.balanceOf(bob), 900 ether);
            // 5% of deposits should be taken as fees
            // - 5 eth from Alice
            // - 5 eth from Bob
            assertEq(_getUserValue(alice, smartVaultA), 142.5 ether);
            assertEq(_getUserValue(bob, smartVaultA), 95 ether);
            assertEq(_getUserValue(vaultOwner, smartVaultA), 15 ether);
        }
    }

    function test_depositFees_redeemFast1() public {
        // add 1 eth deposit by Bob
        {
            vm.startPrank(bob);
            token.approve(address(smartVaultManager), 1 ether);
            uint256 depositNftBob = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftBob), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // - assets were routed to strategy
            assertEq(token.balanceOf(address(strategyA.protocol())), 101 ether);
            assertEq(token.balanceOf(address(masterWallet)), 0 ether);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 101_000000000000000000000);
            // - strategy tokens were distributed
            assertEq(strategyA.balanceOf(address(smartVaultA)), 101_000000000000000000000);
            // - smart vault tokens were minted
            assertEq(smartVaultA.totalSupply(), 101_000000000000000000000);
            // - smart vault tokens were distributed and deposit fee taken
            assertEq(smartVaultA.balanceOf(alice), 95_000000000000000000000);
            assertEq(smartVaultA.balanceOf(bob), 950000000000000000000);
            assertEq(smartVaultA.balanceOf(vaultOwner), 5_050000000000000000000);
        }

        // Bob deposits again and Alice redeems fast after flush
        {
            vm.startPrank(bob);
            token.approve(address(smartVaultManager), 100 ether);
            uint256 depositNftBob = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(100 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // redeem fast
            vm.startPrank(alice);
            uint256[][] memory withdrawSlippages = new uint256[][](1);
            withdrawSlippages[0] = new uint256[](0);
            uint256[2][] memory exchangeRateSlippages = new uint256[2][](1);
            exchangeRateSlippages[0][0] = priceFeedManager.exchangeRates(address(token));
            exchangeRateSlippages[0][1] = priceFeedManager.exchangeRates(address(token));
            smartVaultManager.redeemFast(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: smartVaultA.balanceOf(alice),
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                withdrawSlippages,
                exchangeRateSlippages
            );
            vm.stopPrank();

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftBob), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state and fees
        {
            // Alice withdrew all her shares
            // - 95 eth
            // Bob deposited 100 eth
            // - 5 for fees
            // - 95 for Bob
            assertEq(token.balanceOf(alice), 995 ether, "token balance Alice");
            assertEq(token.balanceOf(address(strategyA.protocol())), 95.95 ether + 10.05 ether, "token balance vault A");
            assertEq(_getUserValue(alice, smartVaultA), 0 ether, "vault value Alice");
            assertEq(_getUserValue(bob, smartVaultA), 95.95 ether, "vault value Bob");
            assertEq(_getUserValue(vaultOwner, smartVaultA), 10.05 ether, "vault value vault owner");
        }
    }

    function test_depositFees_redeemFast2() public {
        // add 1 eth deposit by Bob
        {
            vm.startPrank(bob);
            token.approve(address(smartVaultManager), 1 ether);
            uint256 depositNftBob = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftBob), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // - assets were routed to strategy
            assertEq(token.balanceOf(address(strategyA.protocol())), 101 ether);
            assertEq(token.balanceOf(address(masterWallet)), 0 ether);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 101_000000000000000000000);
            // - strategy tokens were distributed
            assertEq(strategyA.balanceOf(address(smartVaultA)), 101_000000000000000000000);
            // - smart vault tokens were minted
            assertEq(smartVaultA.totalSupply(), 101_000000000000000000000);
            // - smart vault tokens were distributed and deposit fee taken
            assertEq(smartVaultA.balanceOf(alice), 95_000000000000000000000);
            assertEq(smartVaultA.balanceOf(bob), 950000000000000000000);
            assertEq(smartVaultA.balanceOf(vaultOwner), 5_050000000000000000000);
        }

        // Bob deposits again and Alice redeems fast after flush
        {
            vm.startPrank(bob);
            token.approve(address(smartVaultManager), 100 ether);
            uint256 depositNftBob = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(100 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // redeem fast and sync
            vm.startPrank(alice);
            uint256[][] memory withdrawSlippages = new uint256[][](1);
            withdrawSlippages[0] = new uint256[](0);
            uint256[2][] memory exchangeRateSlippages = new uint256[2][](1);
            exchangeRateSlippages[0][0] = priceFeedManager.exchangeRates(address(token));
            exchangeRateSlippages[0][1] = priceFeedManager.exchangeRates(address(token));
            smartVaultManager.redeemFast(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: smartVaultA.balanceOf(alice),
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                withdrawSlippages,
                exchangeRateSlippages
            );
            vm.stopPrank();

            // claim
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftBob), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state and fees
        {
            // Alice withdrew all her shares
            // - 95 eth
            // Bob deposited 100 eth
            // - 5 for fees
            // - 95 for Bob
            assertEq(token.balanceOf(alice), 995 ether, "token balance Alice");
            assertEq(token.balanceOf(address(strategyA.protocol())), 95.95 ether + 10.05 ether, "token balance vault A");
            assertEq(_getUserValue(alice, smartVaultA), 0 ether, "vault value Alice");
            assertEq(_getUserValue(bob, smartVaultA), 95.95 ether, "vault value Bob");
            assertEq(_getUserValue(vaultOwner, smartVaultA), 10.05 ether, "vault value vault owner");
        }
    }

    function test_performanceFees_shouldCollect() public {
        // generate yield
        {
            vm.startPrank(charlie);
            // generate 20% yield
            uint256 yield = token.balanceOf(address(strategyA.protocol())) * 20 / 100;
            token.approve(address(strategyA.protocol()), yield);
            strategyA.protocol().donate(yield);

            // must make a small deposit so that vault can be flushed
            token.approve(address(smartVaultManager), 1);
            smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1),
                    receiver: charlie,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);
        }

        // check fees
        {
            // there was 20 eth yield generated
            // - 2 eth or 10% should go as performance fee
            // - 18 eth is divided among shares
            //   - 17.1 eth for Alice
            //   - 0.9 eth for vault owner
            assertEq(_getUserValue(alice, smartVaultA), 95 ether + 17.1 ether);
            assertEq(_getUserValue(vaultOwner, smartVaultA), 5 ether + 2 ether + 0.9 ether);
        }
    }

    function test_performanceFees_multipleDhws() public {
        // do 3 yield cycles
        for (uint256 i; i < 3; ++i) {
            vm.startPrank(charlie);
            // generate 20% yield
            uint256 yield = token.balanceOf(address(strategyA.protocol())) * 20 / 100;
            token.approve(address(strategyA.protocol()), yield);
            strategyA.protocol().donate(yield);
            vm.stopPrank();

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();
        }

        // collect yield
        {
            // must make a small deposit so that vault can be flushed
            vm.startPrank(charlie);
            token.approve(address(smartVaultManager), 1);
            smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1),
                    receiver: charlie,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);
        }

        // check state
        {
            // there were 3 cycles of 20% yield
            // - total yield: 72.8% (= 1.2**3 - 1)
            // Alice had 95 eth
            // - generated 69.16 eth yield
            //   - 6.916 eth (= 10%) for fees
            //   - 62.244 eth (= 90%) for Alice
            // vault owner had 5 eth
            // - generated 3.64 eth yield
            assertEq(_getUserValue(alice, smartVaultA), 95 ether + 62.244 ether);
            assertEq(_getUserValue(vaultOwner, smartVaultA), 5 ether + 6.916 ether + 3.64 ether);
        }
    }

    function test_performanceFees_multipleDhwCycles() public {
        // do 2 rounds of 2 yield cycles and collect yield between rounds
        for (uint256 i; i < 2; ++i) {
            for (uint256 j; j < 2; ++j) {
                vm.startPrank(charlie);
                // generate 20% yield
                uint256 yield = token.balanceOf(address(strategyA.protocol())) * 20 / 100;
                token.approve(address(strategyA.protocol()), yield);
                strategyA.protocol().donate(yield);
                vm.stopPrank();

                // dhw
                vm.startPrank(doHardWorker);
                strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
                vm.stopPrank();
            }

            // collect yield
            {
                // must make a small deposit so that vault can be flushed
                vm.startPrank(charlie);
                token.approve(address(smartVaultManager), 1);
                smartVaultManager.deposit(
                    DepositBag({
                        smartVault: address(smartVaultA),
                        assets: Arrays.toArray(1),
                        receiver: charlie,
                        referral: address(0),
                        doFlush: false
                    })
                );
                vm.stopPrank();

                // flush
                smartVaultManager.flushSmartVault(address(smartVaultA));

                // dhw
                vm.startPrank(doHardWorker);
                strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
                vm.stopPrank();

                // sync
                smartVaultManager.syncSmartVault(address(smartVaultA), true);
            }
        }

        // check state
        {
            // there were 2 rounds of 2 yield cycles
            // - each yield was 20%
            // - total yield per cycle: 44% (= 1.2**2 - 1)
            // first round
            // - Alice had 95 eth
            //   - generated 41.8 eth yield
            //     - 4.18 eth (= 10%) for fees
            //     - 37.62 eth (= 90%) for Alice
            // - vault owner had 5 eth
            //   - generated 2.2 eth yield
            // second round
            // - Alice had 132.62 eth (= 95 + 37.62)
            //   - generated 58.3528 eth yield
            //     - 5.83528 eth (= 10%) for fees
            //     - 52.51752 eth (= 90%) for Alice
            // - vault owner had 11.38 eth (= 5 + 4.18 + 2.2)
            //   - generated 5.0072 eth yield
            assertApproxEqRel(_getUserValue(alice, smartVaultA), 132.62 ether + 52.51752 ether, 1e7); // eq to 1 part per 1e11
            assertApproxEqRel(_getUserValue(vaultOwner, smartVaultA), 11.38 ether + 5.83528 ether + 5.0072 ether, 1e7); // eq to 1 part per 1e11
        }
    }

    function test_performanceFees_deposit() public {
        // generate yield and deposit
        {
            vm.startPrank(charlie);
            // generate 20% yield
            uint256 yield = token.balanceOf(address(strategyA.protocol())) * 20 / 100;
            token.approve(address(strategyA.protocol()), yield);
            strategyA.protocol().donate(yield);
            vm.stopPrank();

            vm.startPrank(alice);
            // Alice deposits 100 eth to smart vault A
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

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftAlice), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state and fees
        {
            // there was 20% yield
            // - Alice had 95 eth that generated 19 eth yield
            //   - 1.9 eth (= 10%) for fees
            //   - 17.1 eth (= 90%) for Alice
            // - vault owner had 5 eth that generated 1 eth yield
            // Alice deposited 100 eth
            // - 5 eth (= 5%) for fees
            // - 95 eth (= 95%) for Alice
            assertApproxEqAbs(_getUserValue(alice, smartVaultA), 95 ether + 17.1 ether + 95 ether, 10);
            assertApproxEqAbs(_getUserValue(vaultOwner, smartVaultA), 5 ether + 1.9 ether + 1 ether + 5 ether, 10);
        }
    }

    function test_performanceFees_withdrawal1() public {
        // generate yield and withdraw
        {
            vm.startPrank(charlie);
            // generate 20% yield
            uint256 yield = token.balanceOf(address(strategyA.protocol())) * 20 / 100;
            token.approve(address(strategyA.protocol()), yield);
            strategyA.protocol().donate(yield);
            vm.stopPrank();

            vm.startPrank(alice);
            // Alice withdraws half her eth from smart vault A
            uint256 withdrawalNftAlice = smartVaultManager.redeem(
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

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftAlice), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
        }

        // check state and fees -- no fees on withdrawn amount
        {
            // there was 20% yield
            // - Alice had 95 eth that generated 19 eth yield
            //   - half of yield is withdrawn and no fees get charged
            //     - 9.5 eth for Alice
            //   - half of yield remains and fees get charged
            //     - 0.95 eth (= 10%) for fees
            //     - 8.55 eth (= 90%) for Alice
            // - vault owner had 5 eth that generated 1 eth yield
            // Alice withdrew half her shares
            // - 57 eth (= 95/2 + 9.5) withdrawn
            // - 56.05 eth (= 95/2 + 8.55) left
            // vault owner has 6.95 ether (= 5 + 0.95 + 1)
            assertEq(token.balanceOf(alice), 957 ether, "token balance Alice");
            assertEq(token.balanceOf(address(strategyA.protocol())), 56.05 ether + 6.95 ether, "token balance vault A");
            assertEq(_getUserValue(alice, smartVaultA), 56.05 ether, "vault value Alice");
            assertApproxEqAbs(_getUserValue(vaultOwner, smartVaultA), 6.95 ether, 10, "vault value vault owner");
        }
    }

    function test_performanceFees_withdrawal2() public {
        // add a 1 eth deposit by Bob
        {
            vm.startPrank(bob);
            token.approve(address(smartVaultManager), 1 ether);
            uint256 depositNftBob = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftBob), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // - assets were routed to strategy
            assertEq(token.balanceOf(address(strategyA.protocol())), 101 ether);
            assertEq(token.balanceOf(address(masterWallet)), 0 ether);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 101_000000000000000000000);
            // - strategy tokens were distributed
            assertEq(strategyA.balanceOf(address(smartVaultA)), 101_000000000000000000000);
            // - smart vault tokens were minted
            assertEq(smartVaultA.totalSupply(), 101_000000000000000000000);
            // - smart vault tokens were distributed and deposit fee taken
            assertEq(smartVaultA.balanceOf(alice), 95_000000000000000000000);
            assertEq(smartVaultA.balanceOf(bob), 950000000000000000000);
            assertEq(smartVaultA.balanceOf(vaultOwner), 5_050000000000000000000);
        }

        // generate yield and withdraw
        {
            vm.startPrank(charlie);
            // generate 20% yield
            uint256 yield = token.balanceOf(address(strategyA.protocol())) * 20 / 100;
            token.approve(address(strategyA.protocol()), yield);
            strategyA.protocol().donate(yield);

            vm.stopPrank();

            vm.startPrank(alice);
            // Alice withdraws all her eth from smart vault A
            uint256 withdrawalNftAlice = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: smartVaultA.balanceOf(alice),
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftAlice), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
        }

        // check state and fees -- no fees on withdrawn amount
        {
            // there was 20% yield
            // - Alice had 95 eth that generated 19 eth yield
            //   - all of yield is withdrawn and no fees get charged
            //     - 19 eth for Alice
            // - Bob had 0.95 eth that generated 0.19 eth yield
            //   - 0.019 eth (= 10%) for fees
            //   - 0.171 eth (= 90%) for Bob
            // - vault owner had 5.05 eth that generated 1.01 eth yield
            // Alice withdrew all her shares
            // - 114 eth (= 95 + 19)
            // Bob has 1.121 eth
            // vault owner has 6.079 eth (= 5.05 + 0.019 + 1.01)
            assertEq(token.balanceOf(alice), 1014 ether, "token balance Alice");
            assertEq(token.balanceOf(address(strategyA.protocol())), 1.121 ether + 6.079 ether, "token balance vault A");
            assertEq(_getUserValue(alice, smartVaultA), 0 ether, "vault value Alice");
            assertEq(_getUserValue(bob, smartVaultA), 1.121 ether, "vault value Bob");
            assertApproxEqAbs(_getUserValue(vaultOwner, smartVaultA), 6.079 ether, 10, "vault value vault owner");
        }
    }

    function test_performanceFees_redeemFast1() public {
        // add 1 eth deposit by Bob
        {
            vm.startPrank(bob);
            token.approve(address(smartVaultManager), 1 ether);
            uint256 depositNftBob = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftBob), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // - assets were routed to strategy
            assertEq(token.balanceOf(address(strategyA.protocol())), 101 ether);
            assertEq(token.balanceOf(address(masterWallet)), 0 ether);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 101_000000000000000000000);
            // - strategy tokens were distributed
            assertEq(strategyA.balanceOf(address(smartVaultA)), 101_000000000000000000000);
            // - smart vault tokens were minted
            assertEq(smartVaultA.totalSupply(), 101_000000000000000000000);
            // - smart vault tokens were distributed and deposit fee taken
            assertEq(smartVaultA.balanceOf(alice), 95_000000000000000000000);
            assertEq(smartVaultA.balanceOf(bob), 950000000000000000000);
            assertEq(smartVaultA.balanceOf(vaultOwner), 5_050000000000000000000);
        }

        // generate yield and redeem fast
        {
            vm.startPrank(charlie);
            // generate 20% yield -- must be compouned to realize
            uint256 yield = token.balanceOf(address(strategyA.protocol())) * 20 / 100;
            token.approve(address(strategyA.protocol()), yield);
            strategyA.protocol().reward(yield, address(strategyA));

            // must make a small deposit so that vault can be flushed
            token.approve(address(smartVaultManager), 1);
            smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1),
                    receiver: charlie,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // redeem fast
            vm.startPrank(alice);
            uint256[][] memory withdrawSlippages = new uint256[][](1);
            withdrawSlippages[0] = new uint256[](0);
            uint256[2][] memory exchangeRateSlippages = new uint256[2][](1);
            exchangeRateSlippages[0][0] = priceFeedManager.exchangeRates(address(token));
            exchangeRateSlippages[0][1] = priceFeedManager.exchangeRates(address(token));
            smartVaultManager.redeemFast(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: smartVaultA.balanceOf(alice),
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                withdrawSlippages,
                exchangeRateSlippages
            );
            vm.stopPrank();

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);
        }

        // check state and fees -- no fees on redeem fast amount
        {
            // there was 20% yield on compound
            // - vault had 101 eth that generated 20.2 eth yield
            //   - 0 eth for Alice, since she withdrew before DHW
            //   - 2.02 eth (= 10%) for fees
            //   - 18.18 eth (= 90%) for users
            //     - 2.8785 eth (= 18.18 * 0.95 / 6) for Bob
            //     - 15.3015 eth (= 18.18 * 5.05 / 6) for vault owner
            // Alice withdrew all her shares
            // - 95 eth
            // Bob has 3.8285 eth (= 0.95 + 2.8785)
            // vault owner has 22.3715 eth (= 5.05 + 15.3015 + 2.02)
            assertEq(token.balanceOf(alice), 995 ether, "token balance Alice");
            assertEq(
                token.balanceOf(address(strategyA.protocol())),
                3.8285 ether + 22.3715 ether + 1,
                "token balance vault A"
            );
            assertEq(_getUserValue(alice, smartVaultA), 0 ether, "vault value Alice");
            assertApproxEqAbs(_getUserValue(bob, smartVaultA), 3.8285 ether, 1e5, "vault value Bob");
            assertApproxEqAbs(_getUserValue(vaultOwner, smartVaultA), 22.3715 ether, 1e5, "vault value vault owner");
        }
    }

    function test_performanceFees_redeemFast2() public {
        // add a 1 eth deposit by Bob
        {
            vm.startPrank(bob);
            token.approve(address(smartVaultManager), 1 ether);
            uint256 depositNftBob = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftBob), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // - assets were routed to strategy
            assertEq(token.balanceOf(address(strategyA.protocol())), 101 ether);
            assertEq(token.balanceOf(address(masterWallet)), 0 ether);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 101_000000000000000000000);
            // - strategy tokens were distributed
            assertEq(strategyA.balanceOf(address(smartVaultA)), 101_000000000000000000000);
            // - smart vault tokens were minted
            assertEq(smartVaultA.totalSupply(), 101_000000000000000000000);
            // - smart vault tokens were distributed and deposit fee taken
            assertEq(smartVaultA.balanceOf(alice), 95_000000000000000000000);
            assertEq(smartVaultA.balanceOf(bob), 950000000000000000000);
            assertEq(smartVaultA.balanceOf(vaultOwner), 5_050000000000000000000);
        }

        // generate yield and redeem fast
        {
            vm.startPrank(charlie);
            // generate 20% yield -- must be compounded to realize
            uint256 yield = token.balanceOf(address(strategyA.protocol())) * 20 / 100;
            token.approve(address(strategyA.protocol()), yield);
            strategyA.protocol().reward(yield, address(strategyA));

            // must make a small deposit so that vault can be flushed
            token.approve(address(smartVaultManager), 1);
            smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1),
                    receiver: charlie,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            console.log("");
            console.log("token protocol", token.balanceOf(address(strategyA.protocol())));
            console.log("strategy supply", strategyA.totalSupply());
            console.log("strategy vault", strategyA.balanceOf(address(smartVaultA)));
            console.log("vault value alice", _getUserValue(alice, smartVaultA));
            console.log("vault value bob", _getUserValue(bob, smartVaultA));
            console.log("vault value vault owner", _getUserValue(vaultOwner, smartVaultA));
            console.log("");

            // redeem fast -- also syncs
            vm.startPrank(alice);
            uint256[][] memory withdrawSlippages = new uint256[][](1);
            withdrawSlippages[0] = new uint256[](0);
            uint256[2][] memory exchangeRateSlippages = new uint256[2][](1);
            exchangeRateSlippages[0][0] = priceFeedManager.exchangeRates(address(token));
            exchangeRateSlippages[0][1] = priceFeedManager.exchangeRates(address(token));
            smartVaultManager.redeemFast(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: smartVaultA.balanceOf(alice),
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                withdrawSlippages,
                exchangeRateSlippages
            );
            vm.stopPrank();
        }

        // check state and fees -- no fees on redeem fast amount
        {
            // there was 20% yield on compound
            // - vault had 101 eth that generated 20.2 eth yield
            //   - 19 eth for Alice
            //     - 1.9 eth (= 10%) for fees
            //     - 17.1 eth (= 90%) for Alice
            //   - 0.19 eth for Bob
            //     - 0.019 eth (= 10%) for fees
            //     - 0.171 eth (= 90%) for Bob
            //   - 1.01 eth for vault owner
            // Alice withdraws all her shares and her yield 112.1 eth (= 95 + 17.1)
            // Bob has 1.121 eth (= 0.95 + 0.171)
            // vault owner has 7.979 eth (= 5.05 + 1.9 + 1.01 + 0.019)
            assertApproxEqAbs(token.balanceOf(alice), 1012.1 ether, 10, "token balance Alice");
            assertApproxEqAbs(
                token.balanceOf(address(strategyA.protocol())), 1.121 ether + 7.979 ether, 10, "token balance vault A"
            );
            assertEq(_getUserValue(alice, smartVaultA), 0 ether, "vault value Alice");
            assertEq(_getUserValue(bob, smartVaultA), 1.121 ether, "vault value Bob");
            assertApproxEqAbs(_getUserValue(vaultOwner, smartVaultA), 7.979 ether, 10, "vault value vault owner");
        }
    }

    function test_managementFees_shouldCollect() public {
        // skip time to get management fees
        {
            skip(SECONDS_IN_YEAR);

            // must make a small deposit so that vault can be flushed
            vm.startPrank(charlie);
            token.approve(address(smartVaultManager), 1);
            smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1),
                    receiver: charlie,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);
        }

        // check state and fees
        {
            // 2% management fees should be collected
            // - Alice held 95 ether -> 1.9 ether should be taken as fees
            assertEq(_getUserValue(alice, smartVaultA), 95 ether - 1.9 ether);
            assertEq(_getUserValue(vaultOwner, smartVaultA), 5 ether + 1.9 ether);
        }
    }

    function test_managementFees_multipleCollections() public {
        uint256 cyclesLeft = 356;
        uint256 secondsLeft = SECONDS_IN_YEAR;
        // skip time to get management fees
        while (cyclesLeft > 0) {
            uint256 toSkip = secondsLeft / cyclesLeft;
            --cyclesLeft;
            secondsLeft -= toSkip;
            skip(toSkip);

            // must make a small deposit so that vault can be flushed
            vm.startPrank(charlie);
            token.approve(address(smartVaultManager), 1);
            smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1),
                    receiver: charlie,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);
        }

        // check fees
        {
            // 2% management fees should be collected
            // - Alice held 95 ether -> 1.9 ether should be taken as fees
            // assertEq(_getUserValue(alice, smartVaultA), 95 ether - 1.9 ether);
            // assertEq(_getUserValue(vaultOwner, smartVaultA), 5 ether + 1.9 ether);
            assertApproxEqRel(95 ether - _getUserValue(alice, smartVaultA), 1.9 ether, 1e16);
            assertApproxEqRel(_getUserValue(vaultOwner, smartVaultA) - 5 ether, 1.9 ether, 1e16);
        }
    }

    function test_managementFees_deposit() public {
        // skip time to get management fees and deposit
        {
            skip(SECONDS_IN_YEAR);

            vm.startPrank(alice);
            // Alice deposits 100 eth to smart vault A
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

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftAlice), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state and fees
        {
            // 2% management fees should be collected
            // - Alice held 95 ether -> 1.9 ether should be taken as fees
            // Alice deposited 100 eth
            // - 5 eth (= 5%) for fees
            // - 95 eth (= 95%) for Alice
            assertApproxEqAbs(
                _getUserValue(alice, smartVaultA), 95 ether - 1.9 ether + 95 ether, 10, "vault value Alice"
            );
            assertApproxEqAbs(
                _getUserValue(vaultOwner, smartVaultA), 5 ether + 1.9 ether + 5 ether, 10, "vault value vault owner"
            );
        }
    }

    function test_managementFees_withdrawal() public {
        // add a 1 eth deposit by Bob
        {
            vm.startPrank(bob);
            token.approve(address(smartVaultManager), 1 ether);
            uint256 depositNftBob = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftBob), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // - assets were routed to strategy
            assertEq(token.balanceOf(address(strategyA.protocol())), 101 ether);
            assertEq(token.balanceOf(address(masterWallet)), 0 ether);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 101_000000000000000000000);
            // - strategy tokens were distributed
            assertEq(strategyA.balanceOf(address(smartVaultA)), 101_000000000000000000000);
            // - smart vault tokens were minted
            assertEq(smartVaultA.totalSupply(), 101_000000000000000000000);
            // - smart vault tokens were distributed and deposit fee taken
            assertEq(smartVaultA.balanceOf(alice), 95_000000000000000000000);
            assertEq(smartVaultA.balanceOf(bob), 950000000000000000000);
            assertEq(smartVaultA.balanceOf(vaultOwner), 5_050000000000000000000);
        }

        // skip time to get management fees and withdraw
        {
            skip(SECONDS_IN_YEAR);

            vm.startPrank(alice);
            // Alice withdraws all her eth from smart vault A
            uint256 withdrawalNftAlice = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: smartVaultA.balanceOf(alice),
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftAlice), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
        }

        // check state and fees -- no fees on withdrawn amount
        {
            // 2% management fees should be collected
            // - Alice withdrew everything -> nothing to collect
            // - Bob held 0.95 eth -> 0.019 eth should be taken as fees
            // Alice withdrew all her shares
            // - 95 eth
            assertEq(token.balanceOf(alice), 995 ether, "token balance Alice");
            assertEq(token.balanceOf(address(strategyA.protocol())), 1 ether + 5 ether, "token balance vault A");
            assertEq(_getUserValue(alice, smartVaultA), 0 ether, "vault value Alice");
            assertEq(_getUserValue(bob, smartVaultA), 0.931 ether, "vault value Bob");
            assertApproxEqAbs(
                _getUserValue(vaultOwner, smartVaultA), 5.05 ether + 0.019 ether, 10, "vault value vault owner"
            );
        }
    }

    function test_managementFees_redeemFast1() public {
        // add 1 eth deposit by Bob
        {
            vm.startPrank(bob);
            token.approve(address(smartVaultManager), 1 ether);
            uint256 depositNftBob = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftBob), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // - assets were routed to strategy
            assertEq(token.balanceOf(address(strategyA.protocol())), 101 ether);
            assertEq(token.balanceOf(address(masterWallet)), 0 ether);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 101_000000000000000000000);
            // - strategy tokens were distributed
            assertEq(strategyA.balanceOf(address(smartVaultA)), 101_000000000000000000000);
            // - smart vault tokens were minted
            assertEq(smartVaultA.totalSupply(), 101_000000000000000000000);
            // - smart vault tokens were distributed and deposit fee taken
            assertEq(smartVaultA.balanceOf(alice), 95_000000000000000000000);
            assertEq(smartVaultA.balanceOf(bob), 950000000000000000000);
            assertEq(smartVaultA.balanceOf(vaultOwner), 5_050000000000000000000);
        }

        // skip time to get management fees
        {
            skip(SECONDS_IN_YEAR);

            // must make a small deposit so that vault can be flushed
            vm.startPrank(charlie);
            token.approve(address(smartVaultManager), 1);
            smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1),
                    receiver: charlie,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // redeem fast
            vm.startPrank(alice);
            uint256[][] memory withdrawSlippages = new uint256[][](1);
            withdrawSlippages[0] = new uint256[](0);
            uint256[2][] memory exchangeRateSlippages = new uint256[2][](1);
            exchangeRateSlippages[0][0] = priceFeedManager.exchangeRates(address(token));
            exchangeRateSlippages[0][1] = priceFeedManager.exchangeRates(address(token));
            smartVaultManager.redeemFast(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: smartVaultA.balanceOf(alice),
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                withdrawSlippages,
                exchangeRateSlippages
            );
            vm.stopPrank();

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);
        }

        // check state and fees
        {
            // 2% management fees should be collected
            // - Alice fast redeemed before sync -> no fees collected
            // - Bob had 0.95 eth -> should collect 0.019 eth fees
            assertEq(token.balanceOf(alice), 995 ether, "token balance Alice");
            assertEq(token.balanceOf(address(strategyA.protocol())), 6 ether + 1, "token balance vault A");
            assertEq(_getUserValue(alice, smartVaultA), 0 ether, "vault value Alice");
            assertEq(_getUserValue(bob, smartVaultA), 0.931 ether, "vault value Bob");
            assertEq(_getUserValue(vaultOwner, smartVaultA), 5.069 ether, "vault value vault owner");
        }
    }

    function test_managementFees_redeemFast2() public {
        // add 1 eth deposit by Bob
        {
            vm.startPrank(bob);
            token.approve(address(smartVaultManager), 1 ether);
            uint256 depositNftBob = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftBob), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // - assets were routed to strategy
            assertEq(token.balanceOf(address(strategyA.protocol())), 101 ether);
            assertEq(token.balanceOf(address(masterWallet)), 0 ether);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 101_000000000000000000000);
            // - strategy tokens were distributed
            assertEq(strategyA.balanceOf(address(smartVaultA)), 101_000000000000000000000);
            // - smart vault tokens were minted
            assertEq(smartVaultA.totalSupply(), 101_000000000000000000000);
            // - smart vault tokens were distributed and deposit fee taken
            assertEq(smartVaultA.balanceOf(alice), 95_000000000000000000000);
            assertEq(smartVaultA.balanceOf(bob), 950000000000000000000);
            assertEq(smartVaultA.balanceOf(vaultOwner), 5_050000000000000000000);
        }

        // skip time to get management fees
        {
            skip(SECONDS_IN_YEAR);

            // must make a small deposit so that vault can be flushed
            vm.startPrank(charlie);
            token.approve(address(smartVaultManager), 1);
            smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1),
                    receiver: charlie,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // redeem fast -- also syncs
            vm.startPrank(alice);
            uint256[][] memory withdrawSlippages = new uint256[][](1);
            withdrawSlippages[0] = new uint256[](0);
            uint256[2][] memory exchangeRateSlippages = new uint256[2][](1);
            exchangeRateSlippages[0][0] = priceFeedManager.exchangeRates(address(token));
            exchangeRateSlippages[0][1] = priceFeedManager.exchangeRates(address(token));
            smartVaultManager.redeemFast(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: smartVaultA.balanceOf(alice),
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                withdrawSlippages,
                exchangeRateSlippages
            );
            vm.stopPrank();
        }

        // check state and fees
        {
            // 2% management fees should be collected
            // - Alice had 95 eth -> should collect 1.9 eth fees
            // - Bob had 0.95 eth -> should collect 0.019 eth fees
            assertEq(token.balanceOf(alice), 993.1 ether, "token balance Alice");
            assertEq(token.balanceOf(address(strategyA.protocol())), 6 ether + 1.9 ether + 1, "token balance vault A");
            assertEq(_getUserValue(alice, smartVaultA), 0 ether, "vault value Alice");
            assertEq(_getUserValue(bob, smartVaultA), 0.931 ether, "vault value Bob");
            assertEq(_getUserValue(vaultOwner, smartVaultA), 6.969 ether, "vault value vault owner");
        }
    }

    function test_smartVaultFees_managementAndPerformance() public {
        // vault owner withdraws her shares
        {
            vm.startPrank(vaultOwner);
            uint256 withdrawalNftVaultOwner = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: smartVaultA.balanceOf(vaultOwner),
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                vaultOwner,
                false
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(vaultOwner);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA),
                Arrays.toArray(withdrawalNftVaultOwner),
                Arrays.toArray(NFT_MINTED_SHARES),
                vaultOwner
            );
            vm.stopPrank();
        }

        // check state
        {
            // - assets were removed from the strategy
            assertEq(token.balanceOf(address(strategyA.protocol())), 95 ether);
            assertEq(token.balanceOf(vaultOwner), 5 ether);
            // - strategy tokens were burned
            assertEq(strategyA.totalSupply(), 95_000000000000000000000);
            assertEq(strategyA.balanceOf(address(smartVaultA)), 95_000000000000000000000);
            // - smart vault tokens were burned
            assertEq(smartVaultA.totalSupply(), 95_000000000000000000000);
            assertEq(smartVaultA.balanceOf(alice), 95_000000000000000000000);
        }

        // do things
        // - yield is generated
        // - time goes by
        {
            // skip time to get management fees
            skip(SECONDS_IN_YEAR);

            // generate yield
            vm.startPrank(charlie);
            uint256 yield = token.balanceOf(address(strategyA.protocol())) * 20 / 100;
            token.approve(address(strategyA.protocol()), yield);
            strategyA.protocol().donate(yield);

            // must make a small deposit so that vault can be flushed
            token.approve(address(smartVaultManager), 1);
            smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1),
                    receiver: charlie,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);
        }

        // check state and fees
        {
            // vault had 95 eth deposited and got 19 eth yield
            // - management fees are 2%
            //   - should take 2.28 eth (= (95 + 19) * 2%)
            // - performance fees are 10%
            //   - should take 1.9 eth (= 19 * 10%)
            // - users should get remaining assets
            //   - 109.82 eth
            assertEq(token.balanceOf(address(strategyA.protocol())), 114 ether + 1, "token balance strategy A");
            assertEq(_getUserValue(alice, smartVaultA), 109.82 ether, "vault value Alice");
            assertEq(_getUserValue(vaultOwner, smartVaultA), 2.28 ether + 1.9 ether, "vault value vault owner");
        }
    }

    function test_smartVaultFees_allTogether() public {
        // add 1 eth deposit by Bob
        {
            vm.startPrank(bob);
            token.approve(address(smartVaultManager), 1 ether);
            uint256 depositNftBob = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftBob), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // - assets were routed to strategy
            assertEq(token.balanceOf(address(strategyA.protocol())), 101 ether);
            assertEq(token.balanceOf(address(masterWallet)), 0 ether);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 101_000000000000000000000);
            // - strategy tokens were distributed
            assertEq(strategyA.balanceOf(address(smartVaultA)), 101_000000000000000000000);
            // - smart vault tokens were minted
            assertEq(smartVaultA.totalSupply(), 101_000000000000000000000);
            // - smart vault tokens were distributed and deposit fee taken
            assertEq(smartVaultA.balanceOf(alice), 95_000000000000000000000);
            assertEq(smartVaultA.balanceOf(bob), 950000000000000000000);
            assertEq(smartVaultA.balanceOf(vaultOwner), 5_050000000000000000000);
        }

        // do things
        // - Alice withdraws
        // - Bob deposits
        // - yield is generated
        // - time goes by
        {
            // skip time to get management fees
            skip(SECONDS_IN_YEAR);

            // Alice withdraws half her shares
            vm.startPrank(alice);
            uint256 withdrawalNftAlice = smartVaultManager.redeem(
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

            // Bob deposits
            vm.startPrank(bob);
            token.approve(address(smartVaultManager), 10 ether);
            uint256 depositNftBob = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(10 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // generate yield
            vm.startPrank(charlie);
            uint256 yield = token.balanceOf(address(strategyA.protocol())) * 20 / 100;
            token.approve(address(strategyA.protocol()), yield);
            strategyA.protocol().donate(yield);
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftAlice), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftBob), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state and fees
        {
            // vault had 101 eth deposited
            // - there was 20% yield worth 20.2 eth
            // - Alice withdrew half her shares
            //   - 47.5 eth of base
            //   - 9.5 eth of yield
            // vault has 53.5 eth of base, 10.7 eth of yield and 53_5 shares
            // - management fees are 2%
            //   - 1.284 eth (= (53.5 + 10.7) * 0.02)
            // - performance fees are 10%
            //   - 1.07 eth (= 10.7 * 10%)
            // - users should get remaining assets
            //   - 61.846 eth (= 53.5 + 10.7 - 1.284 - 1.07)
            //     - 54.91 eth (= 61.846 * 47.5 / 53.5) for Alice
            //     - 1.0982 eth (= 61.846 * 0.95 / 53.5) for Bob
            //     - 5.8378 eth (= 61.846 * 5.05 / 53.5) for vault owner
            // Bob deposits 10 eth
            // - 0.5 eth (= 5%) for fees
            // - 9.5 eth (= 95%) for Bob
            assertEq(token.balanceOf(alice), 957 ether, "token balance Alice");
            assertEq(
                token.balanceOf(address(strategyA.protocol())),
                53.5 ether + 10.7 ether + 10 ether,
                "token balance vault A"
            );
            assertEq(_getUserValue(alice, smartVaultA), 54.91 ether, "vault value Alice");
            assertApproxEqAbs(_getUserValue(bob, smartVaultA), 1.0982 ether + 9.5 ether, 10, "vault value Bob");
            assertEq(
                _getUserValue(vaultOwner, smartVaultA),
                5.8378 ether + 1.284 ether + 1.07 ether + 0.5 ether,
                "vault value vault owner"
            );
        }
    }

    function test_smartVaultFees_emptyStrategy() public {
        // do things
        // - Alice withdraws
        // - vault owner withdraws
        // - yield is generated
        // - time goes by
        {
            // skip time to get management fees
            skip(SECONDS_IN_YEAR);

            // Alice withdraws all her shares
            vm.startPrank(alice);
            uint256 withdrawalNftAlice = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: smartVaultA.balanceOf(alice),
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                alice,
                false
            );
            vm.stopPrank();

            // vault owner withdraws all her shares
            vm.startPrank(vaultOwner);
            uint256 withdrawalNftVaultOwner = smartVaultManager.redeem(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: smartVaultA.balanceOf(vaultOwner),
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                vaultOwner,
                false
            );
            vm.stopPrank();

            // generate yield
            vm.startPrank(charlie);
            uint256 yield = token.balanceOf(address(strategyA.protocol())) * 10 / 100;
            token.approve(address(strategyA.protocol()), yield);
            strategyA.protocol().donate(yield);
            token.approve(address(strategyA.protocol()), yield);
            strategyA.protocol().reward(yield, address(strategyA));
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA), Arrays.toArray(withdrawalNftAlice), Arrays.toArray(NFT_MINTED_SHARES), alice
            );
            vm.stopPrank();
            vm.startPrank(vaultOwner);
            smartVaultManager.claimWithdrawal(
                address(smartVaultA),
                Arrays.toArray(withdrawalNftVaultOwner),
                Arrays.toArray(NFT_MINTED_SHARES),
                vaultOwner
            );
            vm.stopPrank();
        }

        // check state and fees
        {
            // vault had 100 eth deposited
            // - there was 20% yield worth 20 eth
            // - Alice withdrew all her shares
            //   - 95 eth of base
            //   - 19 eth of yield
            // - vault owner withdrew all her shares
            //   - 5 eth of base
            //   - 1 eth of yield
            assertEq(token.balanceOf(address(strategyA.protocol())), 0, "token balance strategy A protocol");
            assertEq(strategyA.totalSupply(), 0, "strategy A supply");
            assertEq(smartVaultA.totalSupply(), 0, "smart vault A supply");
            assertEq(token.balanceOf(alice), 900 ether + 95 ether + 19 ether, "token balance Alice");
            assertEq(token.balanceOf(vaultOwner), 5 ether + 1 ether);
        }
    }
}

contract AllFeesTest is TestFixture {
    address private alice;
    address private bob;
    address private charlie;
    address private vaultOwner;

    MockStrategy2 private strategyA;
    MockStrategy2 private strategyB;

    address[] private strategiesA;

    ISmartVault private smartVaultA;

    uint256 private assetGroupId;
    address[] private assetGroup;

    uint256 private ecosystemFeePct = 6_00;
    uint256 private treasuryFeePct = 4_00;
    uint16 private managementFeePct = 2_00;
    uint16 private depositFeePct = 5_00;
    uint16 private performanceFeePct = 10_00;

    function setUp() public {
        setUpBase();

        alice = address(0xa);
        bob = address(0xb);
        charlie = address(0xc);
        vaultOwner = address(0xf);

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

            strategiesA = Arrays.toArray(address(strategyA), address(strategyB));
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
                strategyAllocation: Arrays.toUint16a16(50_00, 50_00),
                riskTolerance: 4,
                riskProvider: riskProvider,
                allocationProvider: address(0xabc),
                managementFeePct: managementFeePct,
                depositFeePct: depositFeePct,
                performanceFeePct: performanceFeePct,
                allowRedeemFor: false
            });
            vm.prank(vaultOwner);
            smartVaultA = smartVaultFactory.deploySmartVault(specification);
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

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(alice);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftAlice), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }
    }

    function _getUserVaultValue(address user, ISmartVault smartVault) private view returns (uint256) {
        uint256 totalVaultShares = smartVault.totalSupply();
        uint256 userVaultShares = smartVault.balanceOf(user);
        address[] memory strategies = smartVaultManager.strategies(address(smartVault));

        uint256 userUnderlying;
        for (uint256 i; i < strategies.length; ++i) {
            MockStrategy2 strategy = MockStrategy2(strategies[i]);

            uint256 totalStrategyShares = strategy.totalSupply();
            uint256 vaultStrategyShares = strategy.balanceOf(address(smartVault));

            MockProtocol2 protocol = MockStrategy2(strategies[i]).protocol();
            uint256 totalUnderlying = token.balanceOf(address(protocol));

            userUnderlying +=
                totalUnderlying * vaultStrategyShares * userVaultShares / totalStrategyShares / totalVaultShares;
        }

        return userUnderlying;
    }

    function _getUserStrategyValue(address user, address[] memory strategies) private view returns (uint256) {
        uint256 userUnderlying;
        for (uint256 i; i < strategies.length; ++i) {
            MockStrategy2 strategy = MockStrategy2(strategies[i]);

            uint256 totalShares = strategy.totalSupply();
            uint256 userShares = strategy.balanceOf(user);

            MockProtocol2 protocol = strategy.protocol();
            uint256 totalUnderlying = token.balanceOf(address(protocol));

            userUnderlying += totalUnderlying * userShares / totalShares;
        }

        return userUnderlying;
    }

    function test_initialState() public {
        // check initial state
        {
            // - assets were routed to strategy
            assertEq(token.balanceOf(address(strategyA.protocol())), 50 ether);
            assertEq(token.balanceOf(address(strategyB.protocol())), 50 ether);
            assertEq(token.balanceOf(address(masterWallet)), 0 ether);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 50_000000000000000000000);
            assertEq(strategyB.totalSupply(), 50_000000000000000000000);
            // - strategy tokens were distributed
            assertEq(strategyA.balanceOf(address(smartVaultA)), 50_000000000000000000000);
            assertEq(strategyB.balanceOf(address(smartVaultA)), 50_000000000000000000000);
            // - smart vault tokens were minted
            assertEq(smartVaultA.totalSupply(), 100_000000000000000000000);
            // - smart vault tokens were distributed and deposit fee taken
            assertEq(smartVaultA.balanceOf(alice), 95_000000000000000000000);
            assertEq(smartVaultA.balanceOf(vaultOwner), 5_000000000000000000000);
        }
    }

    function test_yieldFees() public {
        // generate yield
        {
            vm.startPrank(charlie);
            // generate 20% yield
            // - strategy A
            uint256 yield = token.balanceOf(address(strategyA.protocol())) * 20 / 100;
            token.approve(address(strategyA.protocol()), yield);
            strategyA.protocol().donate(yield);
            // - strategy B
            yield = token.balanceOf(address(strategyB.protocol())) * 20 / 100;
            token.approve(address(strategyB.protocol()), yield);
            strategyB.protocol().donate(yield);

            // must make a small deposit so that vault can be flushed
            token.approve(address(smartVaultManager), 2);
            smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(2),
                    receiver: charlie,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);
        }

        // check state and fees
        {
            // there was 20 eth yield generated
            // - 1.2 eth (= 6%) for ecosystem fees (strat)
            // - 0.8 eth (= 4%) for treasury fees (strat)
            // - 2 eth (= 10%) for performance fees (vault)
            // - 16 eth (= 80%) for users
            //   - 15.2 eth (= 16 * 95 / 100) for Alice
            //   - 0.8 eth (= 16 * 5 / 100) for vault owner
            assertEq(token.balanceOf(address(strategyA.protocol())), 60 ether + 1);
            assertEq(token.balanceOf(address(strategyB.protocol())), 60 ether + 1);
            assertApproxEqAbs(_getUserStrategyValue(ecosystemFeeRecipient, strategiesA), 1.2 ether, 10);
            assertApproxEqAbs(_getUserStrategyValue(treasuryFeeRecipient, strategiesA), 0.8 ether, 10);
            assertEq(_getUserStrategyValue(address(smartVaultA), strategiesA), 100 ether + 18 ether);
            assertEq(_getUserVaultValue(alice, smartVaultA), 95 ether + 15.2 ether);
            assertApproxEqAbs(_getUserVaultValue(vaultOwner, smartVaultA), 5 ether + 0.8 ether + 2 ether, 10);
        }
    }

    function test_yieldAndRedeemFastDuringDhws() public {
        // add 1 eth deposit by Bob
        {
            vm.startPrank(bob);
            token.approve(address(smartVaultManager), 1 ether);
            uint256 depositNftBob = smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(1 ether),
                    receiver: bob,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(strategiesA, assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);

            // claim
            vm.startPrank(bob);
            smartVaultManager.claimSmartVaultTokens(
                address(smartVaultA), Arrays.toArray(depositNftBob), Arrays.toArray(NFT_MINTED_SHARES)
            );
            vm.stopPrank();
        }

        // check state
        {
            // - assets were routed to strategy
            assertEq(token.balanceOf(address(strategyA.protocol())), 50.5 ether);
            assertEq(token.balanceOf(address(strategyB.protocol())), 50.5 ether);
            assertEq(token.balanceOf(address(masterWallet)), 0 ether);
            // - strategy tokens were minted
            assertEq(strategyA.totalSupply(), 50_500000000000000000000);
            assertEq(strategyB.totalSupply(), 50_500000000000000000000);
            // - strategy tokens were distributed
            assertEq(strategyA.balanceOf(address(smartVaultA)), 50_500000000000000000000);
            assertEq(strategyB.balanceOf(address(smartVaultA)), 50_500000000000000000000);
            // - smart vault tokens were minted
            assertEq(smartVaultA.totalSupply(), 101_000000000000000000000);
            // - smart vault tokens were distributed and deposit fee taken
            assertEq(smartVaultA.balanceOf(alice), 95_000000000000000000000);
            assertEq(smartVaultA.balanceOf(bob), 950000000000000000000);
            assertEq(smartVaultA.balanceOf(vaultOwner), 5_050000000000000000000);
        }

        // generate yield and redeem fast
        {
            vm.startPrank(charlie);
            // - strategy A -- must be compouned to realize
            uint256 yield = token.balanceOf(address(strategyA.protocol())) * 20 / 100;
            token.approve(address(strategyA.protocol()), yield);
            strategyA.protocol().reward(yield, address(strategyA));
            // - strategy B -- must be compouned to realize
            yield = token.balanceOf(address(strategyB.protocol())) * 20 / 100;
            token.approve(address(strategyB.protocol()), yield);
            strategyB.protocol().reward(yield, address(strategyB));

            // must make a small deposit so that vault can be flushed
            token.approve(address(smartVaultManager), 2);
            smartVaultManager.deposit(
                DepositBag({
                    smartVault: address(smartVaultA),
                    assets: Arrays.toArray(2),
                    receiver: charlie,
                    referral: address(0),
                    doFlush: false
                })
            );
            vm.stopPrank();

            // flush
            smartVaultManager.flushSmartVault(address(smartVaultA));

            // dhw - strategy A
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(Arrays.toArray(address(strategyA)), assetGroup));
            vm.stopPrank();

            // redeem fast
            vm.startPrank(alice);
            uint256[][] memory withdrawSlippages = new uint256[][](2);
            withdrawSlippages[0] = new uint256[](0);
            withdrawSlippages[1] = new uint256[](0);
            uint256[2][] memory exchangeRateSlippages = new uint256[2][](1);
            exchangeRateSlippages[0][0] = priceFeedManager.exchangeRates(address(token));
            exchangeRateSlippages[0][1] = priceFeedManager.exchangeRates(address(token));
            smartVaultManager.redeemFast(
                RedeemBag({
                    smartVault: address(smartVaultA),
                    shares: smartVaultA.balanceOf(alice),
                    nftIds: new uint256[](0),
                    nftAmounts: new uint256[](0)
                }),
                withdrawSlippages,
                exchangeRateSlippages
            );
            vm.stopPrank();

            // dhw - strategy A
            vm.startPrank(doHardWorker);
            strategyRegistry.doHardWork(generateDhwParameterBag(Arrays.toArray(address(strategyB)), assetGroup));
            vm.stopPrank();

            // sync
            smartVaultManager.syncSmartVault(address(smartVaultA), true);
        }

        // check state and fees
        {
            // strategy A DHW
            // - there was 10.1 eth yield on compound -> 20% yield
            //   - 0.606 eth (= 6%) for ecosystem fees (strat)
            //   - 0.404 eth (= 4%) for treasury fees (strat)
            //   - 9.09 eth (= 90%) for smart vault
            // Alice redeems fast
            // - takes 56.05 eth (= (50.5 + 9.09) * 95 / 101) from strategy A
            //   - remains 3.54 eth for smart vault
            // - takes 47.5 eth (= 50.5 * 95 / 101) from strategy B
            //   - remains 3 for smart vault
            // strategy B DHW
            // - there was 3 eth left (= 50.5 - 47.5)
            // - there was 10.1 eth yield on compound -> 336.666666667% yield
            //   - 0.606 eth (= 6%) for ecosystem fees (strat)
            //   - 0.404 eth (= 4%) for treasury fees (strat)
            //   - 9.09 eth (= 90%) for smart vault
            // sync
            // - strategy A
            //   - 3 eth deposited
            //   - 0.54 eth yield remaining -> original yield 0.6 eth
            //     - 0.06 eth (= 0.6 * 10%) for performance fees
            //     - 0.48 eth (= 0.54 - 0.06) for users
            //       - 0.076 eth (= 0.48 * 0.95 / 6) for Bob
            //       - 0.404 eth (= 0.48 * 5.05 / 6) for vault owner
            // - strategy B
            //   - 3 eth deposited
            //   - 9.09 eth yield remaining -> original yield 10.1 eth
            //     - 1.01 eth (= 10.1 * 10%) for performance fees (vault)
            //     - 8.08 eth (= 9.09 - 1.01) for users
            //       - 1.279333333333333333 eth (= 8.08 * 0.95 / 6) for Bob
            //       - 6.800666666666666666 eth (= 1.01 * 5.05 / 6) for vault owner
            assertEq(token.balanceOf(address(strategyA.protocol())), 4.55 ether + 1);
            assertEq(token.balanceOf(address(strategyB.protocol())), 13.1 ether + 1);
            assertEq(token.balanceOf(alice), 900 ether + 56.05 ether + 47.5 ether);
            assertApproxEqAbs(_getUserStrategyValue(ecosystemFeeRecipient, strategiesA), 1.212 ether, 1e5);
            assertApproxEqAbs(_getUserStrategyValue(treasuryFeeRecipient, strategiesA), 0.808 ether, 1e5);
            assertApproxEqAbs(
                _getUserStrategyValue(address(smartVaultA), strategiesA),
                3.54 ether + 3 ether + 1.01 ether + 8.08 ether,
                1e5
            );
            assertEq(_getUserVaultValue(alice, smartVaultA), 0);
            assertApproxEqAbs(
                _getUserVaultValue(bob, smartVaultA), 0.95 ether + 0.076 ether + 1.279333333333333333 ether, 1e5
            );
            assertApproxEqAbs(
                _getUserVaultValue(vaultOwner, smartVaultA),
                5.05 ether + (0.06 ether + 0.404 ether) + (1.01 ether + 6.800666666666666666 ether),
                1e5
            );
        }
    }
}
