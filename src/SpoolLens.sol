// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./interfaces/ISpoolLens.sol";
import "./interfaces/IAssetGroupRegistry.sol";
import "./interfaces/IDepositManager.sol";
import "./interfaces/IMasterWallet.sol";
import "./interfaces/IRiskManager.sol";
import "./interfaces/ISmartVaultManager.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IStrategyRegistry.sol";
import "./interfaces/IUsdPriceFeedManager.sol";
import "./interfaces/IWithdrawalManager.sol";
import "./interfaces/CommonErrors.sol";
import "./interfaces/Constants.sol";
import "./interfaces/IAllocationProvider.sol";
import "./access/SpoolAccessControllable.sol";

/// @notice Used when strategies length is 0 or more than the cap.
error BadStrategieslength(uint256 length);

contract SpoolLens is ISpoolLens, SpoolAccessControllable {
    /// @notice Spool access control manager.
    ISpoolAccessControl public immutable accessControl;

    /// @notice Smart vault deposit manager
    IDepositManager public immutable depositManager;

    /// @notice Smart vault withdrawal manager
    IWithdrawalManager public immutable withdrawalManager;

    /// @notice Strategy registry
    IStrategyRegistry public immutable strategyRegistry;

    /// @notice Asset Group registry
    IAssetGroupRegistry public immutable assetGroupRegistry;

    /// @notice Risk manager
    IRiskManager public immutable riskManager;

    /// @notice Master wallet
    IMasterWallet public immutable masterWallet;

    /// @notice Price feed manager
    IUsdPriceFeedManager public immutable priceFeedManager;

    /// @notice Smart vault manager
    ISmartVaultManager public immutable smartVaultManager;

    address public immutable ghostStrategy;

    /* ========== VIEW FUNCTIONS ========== */

    constructor(
        ISpoolAccessControl accessControl_,
        IAssetGroupRegistry assetGroupRegistry_,
        IRiskManager riskManager_,
        IDepositManager depositManager_,
        IWithdrawalManager withdrawalManager_,
        IStrategyRegistry strategyRegistry_,
        IMasterWallet masterWallet_,
        IUsdPriceFeedManager priceFeedManager_,
        ISmartVaultManager smartVaultManager_,
        address ghostStrategy_
    ) SpoolAccessControllable(accessControl_) {
        if (address(assetGroupRegistry_) == address(0)) revert ConfigurationAddressZero();
        if (address(riskManager_) == address(0)) revert ConfigurationAddressZero();
        if (address(depositManager_) == address(0)) revert ConfigurationAddressZero();
        if (address(withdrawalManager_) == address(0)) revert ConfigurationAddressZero();
        if (address(strategyRegistry_) == address(0)) revert ConfigurationAddressZero();
        if (address(masterWallet_) == address(0)) revert ConfigurationAddressZero();
        if (address(priceFeedManager_) == address(0)) revert ConfigurationAddressZero();
        if (address(smartVaultManager_) == address(0)) revert ConfigurationAddressZero();

        accessControl = accessControl_;
        assetGroupRegistry = assetGroupRegistry_;
        riskManager = riskManager_;
        depositManager = depositManager_;
        withdrawalManager = withdrawalManager_;
        strategyRegistry = strategyRegistry_;
        masterWallet = masterWallet_;
        priceFeedManager = priceFeedManager_;
        smartVaultManager = smartVaultManager_;
        ghostStrategy = ghostStrategy_;
    }

    /**
     * @notice Retrieves a Smart Vault Token Balance for user. Including the predicted balance from all current D-NFTs
     * currently in holding.
     */
    function getUserSVTBalance(address smartVault, address user, uint256[] calldata nftIds)
        external
        view
        returns (uint256)
    {
        return _getUserSVTBalance(smartVault, user, nftIds);
    }

    /**
     * @notice Retrieves user balances of smart vault tokens for each NFT.
     * @param smartVault Smart vault.
     * @param user User to check.
     * @param nftIds user's NFTs (only D-NFTs, system will ignore W-NFTs)
     * @return nftSvts SVT balance of each user D-NFT for smart vault.
     */
    function getUserSVTsfromNFTs(address smartVault, address user, uint256[] calldata nftIds)
        external
        view
        returns (uint256[] memory nftSvts)
    {
        nftSvts = new uint256[](nftIds.length);
        for (uint256 i; i < nftSvts.length; ++i) {
            uint256[] memory nftId = new uint256[](1);
            nftId[0] = nftIds[i];
            nftSvts[i] = smartVaultManager.simulateSyncWithBurn(smartVault, user, nftId);
        }
    }

    /**
     * @notice Retrieves total supply of SVTs.
     * Includes deposits that were processed by DHW, but still need SVTs to be minted.
     * @param smartVault Smart Vault address.
     * @return totalSupply Simulated total supply.
     */
    function getSVTTotalSupply(address smartVault) external view returns (uint256) {
        (uint256 currentSupply, uint256 mintedSVTs, uint256 fees,) = smartVaultManager.simulateSync(smartVault);
        return currentSupply + mintedSVTs + fees;
    }

    /**
     * @notice Calculate strategy allocations for a Smart Vault
     * @param strategies Array of strategies to calculate allocations for
     * @param riskProvider Address of the risk provider
     * @param allocationProvider Address of the allocation provider
     * @return allocations Array of allocations for each strategy
     */
    function getSmartVaultAllocations(address[] calldata strategies, address riskProvider, address allocationProvider)
        external
        view
        returns (uint256[][] memory allocations)
    {
        _checkRole(ROLE_ALLOCATION_PROVIDER, allocationProvider);
        _checkRole(ROLE_RISK_PROVIDER, riskProvider);

        if (strategies.length == 0 || strategies.length > STRATEGY_COUNT_CAP) {
            revert BadStrategieslength(strategies.length);
        }

        uint256 assetGroupId = IStrategy(strategies[0]).assetGroupId();
        for (uint256 i; i < strategies.length; ++i) {
            _checkRole(ROLE_STRATEGY, strategies[i]);

            if (assetGroupId != IStrategy(strategies[i]).assetGroupId()) {
                revert NotSameAssetGroup();
            }
        }

        allocations = new uint256[][](21);

        int256[] memory apyList = strategyRegistry.strategyAPYs(strategies);
        uint8[] memory riskScores = riskManager.getRiskScores(riskProvider, strategies);

        unchecked {
            for (uint8 i; i < allocations.length; ++i) {
                int8 riskTolerance = int8(i) - 10;
                allocations[i] = IAllocationProvider(allocationProvider).calculateAllocation(
                    AllocationCalculationInput({
                        strategies: strategies,
                        apys: apyList,
                        riskScores: riskScores,
                        riskTolerance: riskTolerance
                    })
                );
            }
        }
    }

    /**
     * @notice Returns smart vault balances in the underlying assets.
     * @dev Should be just used as a view to show balances.
     * @param smartVault Smart vault.
     * @param doFlush Flush vault before calculation.
     * @return balances Array of balances for each asset.
     */
    function getSmartVaultAssetBalances(address smartVault, bool doFlush)
        external
        returns (uint256[] memory balances)
    {
        smartVaultManager.syncSmartVault(smartVault, false);

        if (doFlush) {
            smartVaultManager.flushSmartVault(smartVault);
        }

        uint256 assetsLength = assetGroupRegistry.assetGroupLength(smartVaultManager.assetGroupId(smartVault));
        balances = new uint256[](assetsLength);

        address[] memory smartVaultStrategies = smartVaultManager.strategies(smartVault);

        for (uint256 i; i < smartVaultStrategies.length; ++i) {
            if (ghostStrategy == smartVaultStrategies[i]) {
                continue;
            }

            IStrategy strategy = IStrategy(smartVaultStrategies[i]);

            uint256 strategySupply = strategy.totalSupply();
            if (strategySupply == 0) {
                continue;
            }

            uint256 smartVaultBalance = strategy.balanceOf(smartVault);
            uint256[] memory amounts = strategy.getUnderlyingAssetAmounts();

            for (uint256 j; j < balances.length; ++j) {
                balances[j] += (amounts[j] * smartVaultBalance) / strategySupply;
            }
        }
    }

    /**
     * @notice Returns user balances for each strategy across smart vaults
     * @dev Should just used as a view to show balances.
     * @param user User.
     * @param smartVaults smartVaults that user has deposits in
     * @param doFlush should smart vault be flushed. same size as smartVaults
     * @param nftIds NFTs in smart vault. same size as smartVaults
     * @return balances Array of balances for each asset, for each strategy, for each smart vault. same size as smartVaults
     */
    function getUserStrategyValues(
        address user,
        address[] calldata smartVaults,
        uint256[][] calldata nftIds,
        bool[] calldata doFlush
    ) external returns (uint256[][][] memory balances) {
        balances = new uint256[][][](smartVaults.length);
        for (uint256 i = 0; i < smartVaults.length; ++i) {
            address smartVault = smartVaults[i];

            smartVaultManager.syncSmartVault(smartVault, false);

            if (doFlush[i]) {
                smartVaultManager.flushSmartVault(smartVault);
            }

            uint256 vaultSharesUser = _getUserSVTBalance(smartVault, user, nftIds[i]);

            uint256 vaultSharesTotal = ISmartVault(smartVault).totalSupply();

            balances[i] = _getUserStrategyValuesByVault(smartVault, vaultSharesUser, vaultSharesTotal);
        }
    }

    /**
     * @notice Returns user balances for each strategy in a smart vault
     * @param smartVault SmartVault.
     * @param vaultSharesUser User's shares in the smart vault.
     * @param vaultSharesTotal Total shares in the smart vault.
     * @return balances Array of balances for each asset. same size as vault strategies
     */
    function _getUserStrategyValuesByVault(address smartVault, uint256 vaultSharesUser, uint256 vaultSharesTotal)
        private
        view
        returns (uint256[][] memory balances)
    {
        address[] memory strategies = smartVaultManager.strategies(smartVault);
        balances = new uint256[][](strategies.length);
        for (uint256 i; i < strategies.length; ++i) {
            IStrategy strategy = IStrategy(strategies[i]);

            uint256 strategySharesTotal = strategy.totalSupply();

            uint256 strategySharesVault = strategy.balanceOf(smartVault);

            uint256[] memory amounts = strategy.getUnderlyingAssetAmounts();

            balances[i] = new uint256[](amounts.length);
            for (uint256 j; j < amounts.length; ++j) {
                uint256 amountStrategy = amounts[j];

                uint256 amountVault = (strategySharesVault * amountStrategy) / strategySharesTotal;

                uint256 amountUser = (vaultSharesUser * amountVault) / vaultSharesTotal;

                balances[i][j] = amountUser;
            }
        }
    }

    /**
     * @notice Retrieves a Smart Vault Token Balance for user. Including the predicted balance from all current D-NFTs
     * currently in holding.
     */
    function _getUserSVTBalance(address smartVault, address user, uint256[] calldata nftIds)
        private
        view
        returns (uint256 currentBalance)
    {
        currentBalance = ISmartVault(smartVault).balanceOf(user);

        if (accessControl.smartVaultOwner(smartVault) == user) {
            (,, uint256 fees,) = smartVaultManager.simulateSync(smartVault);
            currentBalance += fees;
        }

        if (nftIds.length > 0) {
            currentBalance += smartVaultManager.simulateSyncWithBurn(smartVault, user, nftIds);
        }
    }
}
