// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../../src/interfaces/RequestType.sol";
import "../../src/guards/UnlockGuard.sol";
import "../../src/managers/AssetGroupRegistry.sol";
import "../../src/managers/RiskManager.sol";
import "../../src/managers/SmartVaultManager.sol";
import "../../src/managers/StrategyRegistry.sol";
import "../../src/managers/UsdPriceFeedManager.sol";
import "../../src/SmartVault.sol";
import "../../src/SmartVaultFactory.sol";
import "../../src/Swapper.sol";
import "../mocks/MockStrategy.sol";
import "../libraries/Arrays.sol";
import "../fixtures/TestFixture.sol";

contract UnlockGuardIntegrationTest is TestFixture {
    address private alice;
    address private bob;
    address private charlie;
    address private dave;
    address private eve;

    UnlockGuard private unlockGuard;
    MockStrategy strategy;

    function setUp() public {
        setUpBase();

        alice = address(0xa);
        bob = address(0xb);
        charlie = address(0xc);
        dave = address(0xd);
        eve = address(0xe);

        uint256 assetGroupId = assetGroupRegistry.registerAssetGroup(Arrays.toArray(address(token)));

        (GuardDefinition[][] memory guards, RequestType[] memory guardRequestTypes) = setUpUnlockGuard();

        strategy = new MockStrategy(assetGroupRegistry, accessControl, swapper, assetGroupId);
        {
            uint256[] memory strategyRatios = new uint256[](1);
            strategyRatios[0] = 1_000;
            strategy.initialize("Strategy", strategyRatios);
            strategyRegistry.registerStrategy(address(strategy), 0);
        }

        {
            vm.mockCall(
                address(riskManager),
                abi.encodeWithSelector(IRiskManager.calculateAllocation.selector),
                abi.encode(Arrays.toUint16a16(1_000))
            );

            smartVault = smartVaultFactory.deploySmartVault(
                SmartVaultSpecification({
                    smartVaultName: "SmartVault",
                    svtSymbol: "SV",
                    baseURI: "https://token-cdn-domain/",
                    assetGroupId: assetGroupId,
                    actions: new IAction[](0),
                    actionRequestTypes: new RequestType[](0),
                    guards: guards,
                    guardRequestTypes: guardRequestTypes,
                    strategies: Arrays.toArray(address(strategy)),
                    strategyAllocation: Arrays.toUint16a16(FULL_PERCENT),
                    riskTolerance: 0,
                    riskProvider: address(0),
                    allocationProvider: address(0),
                    managementFeePct: 0,
                    depositFeePct: 0,
                    allowRedeemFor: false,
                    performanceFeePct: 0
                })
            );
        }

        setUpUnlock();
    }

    function setUpUnlockGuard() private returns (GuardDefinition[][] memory, RequestType[] memory) {
        unlockGuard = new UnlockGuard(accessControl);

        // Setup smart vault with one guard:
        // - check whether the person burning the deposit NFT has passed the unlock
        // The guard is implemented using the `checkUnlock` function of the
        // UnlockGuard contract.
        GuardDefinition[][] memory guards = new GuardDefinition[][](1);
        guards[0] = new GuardDefinition[](1);

        // guard call receives three parameters:
        // - address of the smart vault
        // - ID of unlock to use for the smart vault
        // - address to check against the unlock
        GuardParamType[] memory guardParamTypes = new GuardParamType[](2);

        guardParamTypes[0] = GuardParamType.VaultAddress; // address of the smart vault
        guardParamTypes[1] = GuardParamType.Assets; // ID of the unlock, set as method param value below

        // define the guards
        guards[0][0] = GuardDefinition({ // guard checking the executor
            contractAddress: address(unlockGuard),
            methodSignature: "checkUnlock(address)",
            operator: "",
            expectedValue: 0,
            methodParamTypes: guardParamTypes,
            methodParamValues: new bytes[](0)
        });

        RequestType[] memory requestTypes = new RequestType[](1);
        requestTypes[0] = RequestType.BurnNFT;

        return (guards, requestTypes);
    }

    function setUpUnlock() private {
        // allow Alice to update unlocks for the smart vault
        accessControl.grantSmartVaultRole(address(smartVault), ROLE_SMART_VAULT_ADMIN, alice);

        vm.prank(alice);
        unlockGuard.updateUnlock(address(smartVault), 30 days);
    }

    function test_depositWithUnlock() public {
        token.mint(charlie, 2 ether);
        token.mint(eve, 1 ether);
        token.mint(bob, 1 ether);

        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1 ether;

        uint256[][] memory nftIds = new uint256[][](3);

        vm.startPrank(charlie);
        token.approve(address(smartVaultManager), 2 ether);
        nftIds[0] = new uint256[](1);
        nftIds[0][0] =
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, charlie, address(0), false));
        vm.stopPrank();
        vm.warp(block.timestamp + 4 days);

        vm.startPrank(eve);
        token.approve(address(smartVaultManager), 1 ether);
        nftIds[1] = new uint256[](1);
        nftIds[1][0] =
            smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, eve, address(0), false));
        vm.stopPrank();
        vm.warp(block.timestamp + 4 days);

        vm.startPrank(bob);
        token.approve(address(smartVaultManager), 1 ether);
        nftIds[2] = new uint256[](1);
        nftIds[2][0] = smartVaultManager.deposit(DepositBag(address(smartVault), depositAmounts, bob, address(0), true));
        vm.stopPrank();
        vm.warp(block.timestamp + 5 days);

        // execute dhw for the strategy
        DoHardWorkParameterBag memory bag =
            generateDhwParameterBag(Arrays.toArray(address(strategy)), Arrays.toArray(address(token)));
        accessControl.grantRole(ROLE_DO_HARD_WORKER, alice);
        vm.prank(alice);
        strategyRegistry.doHardWork(bag);
        smartVaultManager.syncSmartVault(address(smartVault), false);

        uint256[] memory nftAmounts = Arrays.toArray(NFT_MINTED_SHARES);

        // claim as Charlie, should fail
        vm.prank(charlie);
        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 0));
        smartVaultManager.claimSmartVaultTokens(address(smartVault), nftIds[0], nftAmounts);

        // claim as Eve, should fail
        vm.prank(eve);
        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 0));
        smartVaultManager.claimSmartVaultTokens(address(smartVault), nftIds[1], nftAmounts);

        // claim as Bob, should fail
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(GuardFailed.selector, 0));
        smartVaultManager.claimSmartVaultTokens(address(smartVault), nftIds[2], nftAmounts);

        vm.warp(block.timestamp + 22 days);

        // at this point everyone should be able to burn.
        vm.prank(charlie);
        smartVaultManager.claimSmartVaultTokens(address(smartVault), nftIds[0], nftAmounts);

        vm.prank(eve);
        smartVaultManager.claimSmartVaultTokens(address(smartVault), nftIds[1], nftAmounts);

        vm.prank(bob);
        smartVaultManager.claimSmartVaultTokens(address(smartVault), nftIds[2], nftAmounts);
    }
}
