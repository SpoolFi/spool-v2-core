// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/IUsdPriceFeedManager.sol";
import "../interfaces/ISmartVaultManager.sol";
import "../interfaces/IRiskManager.sol";
import "../interfaces/ISmartVault.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/IGuardManager.sol";
import "../interfaces/IAction.sol";
import "../interfaces/RequestType.sol";
import "../interfaces/IAssetGroupRegistry.sol";
import "../libraries/ArrayMapping.sol";
import "../libraries/SmartVaultDeposits.sol";
import "../interfaces/ISpoolAccessControl.sol";
import "../access/SpoolAccessControl.sol";
import "../interfaces/ISmartVaultManager.sol";

contract SmartVaultManager is ISmartVaultManager, SpoolAccessControllable {
    using SafeERC20 for IERC20;
    using ArrayMapping for mapping(uint256 => uint256);

    /* ========== STATE VARIABLES ========== */

    /**
     * @notice Contract executing token swaps for vault flush.
     */
    ISwapper internal immutable _swapper;

    // @notice Guard manager
    IGuardManager internal immutable _guardManager;

    // @notice Action manager
    IActionManager internal immutable _actionManager;

    /// @notice Strategy registry
    IStrategyRegistry private immutable _strategyRegistry;

    /// @notice Price Feed Manager
    IUsdPriceFeedManager private immutable _priceFeedManager;

    /// @notice Asset Group registry
    IAssetGroupRegistry private immutable _assetGroupRegistry;

    /// @notice Master wallet
    IMasterWallet private immutable _masterWallet;

    mapping(address => bool) internal _smartVaultRegistry;

    mapping(address => uint256) internal _smartVaultAssetGroups;

    /// @notice Smart Vault strategy registry
    mapping(address => address[]) internal _smartVaultStrategies;

    /// @notice Smart Vault risk provider registry
    mapping(address => address) internal _smartVaultRiskProviders;

    /// @notice Smart Vault strategy allocations
    mapping(address => mapping(uint256 => uint256)) internal _smartVaultAllocations;

    /// @notice Smart Vault tolerance registry
    mapping(address => int256) internal _riskTolerances;

    /// @notice Current flush index for given Smart Vault
    mapping(address => uint256) internal _flushIndexes;

    /// @notice First flush index that still needs to be synced for given Smart Vault.
    mapping(address => uint256) internal _flushIndexesToSync;

    /// @notice DHW indexes for given Smart Vault and flush index
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _dhwIndexes;

    /// @notice TODO smart vault => flush index => assets deposited
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _vaultDeposits;

    /// @notice TODO smart vault => flush index => strategy => assets deposited
    mapping(address => mapping(uint256 => mapping(address => mapping(uint256 => uint256)))) internal
        _vaultFlushedDeposits;

    /// @notice TODO smart vault => flush index => vault shares minted
    mapping(address => mapping(uint256 => uint256)) internal _mintedVaultShares;

    /// @notice TODO smart vault => flush index => vault shares withdrawn
    mapping(address => mapping(uint256 => uint256)) internal _withdrawnVaultShares;

    /// @notice TODO smart vault => flush index => strategy shares withdrawn
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _withdrawnStrategyShares;

    /// @notice TODO smart vault => flush index => assets withdrawn
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _withdrawnAssets;

    /// @notice TODO smart vault => flush index => exchange rates
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _flushExchangeRates;

    constructor(
        ISpoolAccessControl accessControl_,
        IStrategyRegistry strategyRegistry_,
        IUsdPriceFeedManager priceFeedManager_,
        IAssetGroupRegistry assetGroupRegistry_,
        IMasterWallet masterWallet_,
        IActionManager actionManager_,
        IGuardManager guardManager_,
        ISwapper swapper_
    ) SpoolAccessControllable(accessControl_) {
        _strategyRegistry = strategyRegistry_;
        _priceFeedManager = priceFeedManager_;
        _assetGroupRegistry = assetGroupRegistry_;
        _masterWallet = masterWallet_;
        _actionManager = actionManager_;
        _guardManager = guardManager_;
        _swapper = swapper_;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice TODO
     */
    function strategies(address smartVault) external view returns (address[] memory) {
        return _smartVaultStrategies[smartVault];
    }

    /**
     * @notice TODO
     */
    function allocations(address smartVault) external view returns (uint256[] memory) {
        return _smartVaultAllocations[smartVault].toArray(_smartVaultStrategies[smartVault].length);
    }

    /**
     * @notice TODO
     */
    function riskProvider(address smartVault) external view returns (address) {
        return _smartVaultRiskProviders[smartVault];
    }

    /**
     * @notice TODO
     */
    function riskTolerance(address smartVault) external view returns (int256) {
        return _riskTolerances[smartVault];
    }

    /**
     * @notice TODO
     */
    function assetGroupId(address smartVault) external view returns (uint256) {
        return _smartVaultAssetGroups[smartVault];
    }

    /**
     * @notice TODO
     */
    function getLatestFlushIndex(address smartVault) external view returns (uint256) {
        return _flushIndexes[smartVault];
    }

    /**
     * @notice Smart vault deposits for given flush index.
     */
    function smartVaultDeposits(address smartVault, uint256 flushIdx) external view returns (uint256[] memory) {
        uint256 assetGroupLength = _assetGroupRegistry.assetGroupLength(_smartVaultAssetGroups[smartVault]);
        return _vaultDeposits[smartVault][flushIdx].toArray(assetGroupLength);
    }

    /**
     * @notice DHW indexes that were active at given flush index
     */
    function dhwIndexes(address smartVault, uint256 flushIndex) external view returns (uint256[] memory) {
        uint256 strategyCount = _smartVaultStrategies[smartVault].length;
        return _dhwIndexes[smartVault][flushIndex].toArray(strategyCount);
    }

    /**
     * @notice Gets total value (in USD) of assets managed by the vault.
     */
    function getVaultTotalUsdValue(address smartVault) public view returns (uint256) {
        address[] memory strategyAddresses = _smartVaultStrategies[smartVault];

        uint256 totalUsdValue = 0;

        for (uint256 i = 0; i < strategyAddresses.length; i++) {
            IStrategy strategy = IStrategy(strategyAddresses[i]);
            totalUsdValue =
                totalUsdValue + strategy.totalUsdValue() * strategy.balanceOf(smartVault) / strategy.totalSupply();
        }

        return totalUsdValue;
    }

    /**
     * @notice Calculate current Smart Vault asset deposit ratio
     * @dev As described in /notes/multi-asset-vault-deposit-ratios.md
     */
    function getDepositRatio(address smartVault)
        external
        view
        onlyRegisteredSmartVault(smartVault)
        returns (uint256[] memory)
    {
        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);
        DepositRatioQueryBag memory bag = DepositRatioQueryBag(
            smartVault,
            tokens,
            strategies_,
            _smartVaultAllocations[smartVault].toArray(strategies_.length),
            SpoolUtils.getExchangeRates(tokens, _priceFeedManager),
            SpoolUtils.getStrategyRatios(strategies_),
            _priceFeedManager.usdDecimals(),
            address(_masterWallet),
            address(_swapper)
        );

        return SmartVaultDeposits.getDepositRatio(bag);
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /* ========== DEPOSIT/WITHDRAW ========== */

    /**
     * @dev Burns exactly shares from owner and sends assets of underlying tokens to receiver.
     * @param shares TODO
     * @param receiver TODO
     * @param owner TODO
     * - MUST emit the Withdraw event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
     *   redeem execution, and are accounted for during redeem.
     * - MUST revert if all of shares cannot be redeemed (due to withdrawal limit being reached, slippage, the owner
     *   not having enough shares, etc).
     *
     * NOTE: some implementations will require pre-requesting to the Vault before a withdrawal may be performed.
     * Those methods should be performed separately.
     */
    function redeem(address smartVault, uint256 shares, address receiver, address owner)
        external
        onlyRegisteredSmartVault(smartVault)
        returns (uint256)
    {
        return _redeemShares(smartVault, shares, receiver, owner);
    }

    /**
     * @notice Used to withdraw underlying asset.
     * @param shares TODO
     * @param receiver TODO
     * @param owner TODO
     * @return returnedAssets TODO
     */
    function redeemFast(
        address smartVault,
        uint256 shares,
        address receiver,
        uint256[][] calldata, /*slippages*/
        address owner
    ) external onlyRegisteredSmartVault(smartVault) returns (uint256[] memory) {
        revert("0");
    }

    /**
     * @notice TODO
     * @param smartVault TODO
     * @param depositor TODO
     * @param assets TODO
     * @param receiver TODO
     */
    function depositFor(address smartVault, uint256[] calldata assets, address receiver, address depositor)
        external
        onlyRegisteredSmartVault(smartVault)
        returns (uint256)
    {
        return _depositAssets(smartVault, depositor, receiver, assets);
    }

    /**
     * @notice TODO
     * TODO: pass slippages
     * @param smartVault TODO
     * @param assets TODO
     * @param receiver TODO
     * @param slippages TODO
     * @return receipt TODO
     */
    function depositFast(
        address smartVault,
        uint256[] calldata assets,
        address receiver,
        uint256[][] calldata slippages
    ) external onlyRegisteredSmartVault(smartVault) returns (uint256) {
        revert("0");
    }

    /**
     * @dev Mints shares Vault shares to receiver by depositing exactly amount of underlying tokens.
     * @param assets TODO
     *
     * - MUST emit the Deposit event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
     *   deposit execution, and are accounted for during deposit.
     * - MUST revert if all of assets cannot be deposited (due to deposit limit being reached, slippage, the user not
     *   approving enough underlying tokens to the Vault contract, etc).
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault’s underlying asset token.
     */
    function deposit(address smartVault, uint256[] calldata assets, address receiver)
        external
        onlyRegisteredSmartVault(smartVault)
        returns (uint256)
    {
        return _depositAssets(smartVault, msg.sender, receiver, assets);
    }

    function claimSmartVaultTokens(address smartVaultAddress, uint256 depositNftId)
        external
        onlyRegisteredSmartVault(smartVaultAddress)
        returns (uint256)
    {
        ISmartVault smartVault = ISmartVault(smartVaultAddress);
        smartVault.burnNFT(msg.sender, depositNftId, RequestType.Deposit);
        DepositMetadata memory data = smartVault.getDepositMetadata(depositNftId);

        if (data.flushIndex >= _flushIndexesToSync[smartVaultAddress]) {
            revert DepositNotSyncedYet();
        }

        uint256 depositedUsd;
        uint256 totalDepositedUsd;
        {
            address[] memory assets = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVaultAddress]);
            uint256[] memory totalDepositedAssets =
                _vaultDeposits[smartVaultAddress][data.flushIndex].toArray(data.assets.length);
            uint256[] memory exchangeRates =
                _flushExchangeRates[smartVaultAddress][data.flushIndex].toArray(data.assets.length);

            for (uint256 i = 0; i < data.assets.length; i++) {
                depositedUsd += _priceFeedManager.assetToUsdCustomPrice(assets[i], data.assets[i], exchangeRates[i]);
                totalDepositedUsd +=
                    _priceFeedManager.assetToUsdCustomPrice(assets[i], totalDepositedAssets[i], exchangeRates[i]);
            }
        }

        uint256 claimedVaultTokens =
            _mintedVaultShares[smartVaultAddress][data.flushIndex] * depositedUsd / totalDepositedUsd;
        // there will be some dust after all users claim SVTs
        smartVault.claimShares(msg.sender, claimedVaultTokens);

        return claimedVaultTokens;
    }

    function claimWithdrawal(address smartVaultAddress, uint256 withdrawalNftId, address receiver)
        external
        onlyRegisteredSmartVault(smartVaultAddress)
        returns (uint256[] memory, uint256)
    {
        ISmartVault smartVault = ISmartVault(smartVaultAddress);
        WithdrawalMetadata memory data = smartVault.getWithdrawalMetadata(withdrawalNftId);
        smartVault.burnNFT(msg.sender, withdrawalNftId, RequestType.Withdrawal);

        uint256 assetGroupID = _smartVaultAssetGroups[smartVaultAddress];
        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupID);
        uint256[] memory withdrawnAssets =
            _calculateWithdrawal(smartVaultAddress, withdrawalNftId, data, assetGroup.length);

        _runActions(
            smartVaultAddress, msg.sender, receiver, msg.sender, withdrawnAssets, assetGroup, RequestType.Withdrawal
        );

        for (uint256 i = 0; i < assetGroup.length; i++) {
            // TODO-Q: should this be done by an action, since there might be a swap?
            _masterWallet.transfer(IERC20(assetGroup[i]), receiver, withdrawnAssets[i]);
        }

        return (withdrawnAssets, assetGroupID);
    }

    /* ========== REGISTRY ========== */

    function registerSmartVault(address smartVault, SmartVaultRegistrationForm calldata registrationForm)
        external
        onlyUnregisteredSmartVault(smartVault)
        onlyRole(ROLE_RISK_PROVIDER, registrationForm.riskProvider)
    {
        // TODO: should check if same asset group on strategies and smart vault

        // set asset group
        _smartVaultAssetGroups[smartVault] = registrationForm.assetGroupId;

        // set strategies
        if (registrationForm.strategies.length == 0) {
            revert SmartVaultRegistrationNoStrategies();
        }

        for (uint256 i = 0; i < registrationForm.strategies.length; i++) {
            address strategy = registrationForm.strategies[i];
            if (!_strategyRegistry.isStrategy(strategy)) {
                revert InvalidStrategy(strategy);
            }
        }

        _smartVaultStrategies[smartVault] = registrationForm.strategies;

        // set strategy allocations
        // TODO: need to make sure all allocations add up to the ALLOC_PRECISION
        if (registrationForm.strategyAllocations.length != registrationForm.strategies.length) {
            revert SmartVaultRegistrationIncorrectAllocationLength();
        }

        for (uint256 i = 0; i < registrationForm.strategyAllocations.length; i++) {
            if (registrationForm.strategyAllocations[i] == 0) {
                revert SmartVaultRegistrationZeroAllocation();
            }
        }

        _smartVaultAllocations[smartVault].setValues(registrationForm.strategyAllocations);

        // set risk provider
        _smartVaultRiskProviders[smartVault] = registrationForm.riskProvider;

        // update registry
        _smartVaultRegistry[smartVault] = true;
    }

    /**
     * @notice TODO
     */
    function setRiskProvider(address smartVault, address riskProvider_)
        external
        onlyRole(ROLE_RISK_PROVIDER, riskProvider_)
    {
        _smartVaultRiskProviders[smartVault] = riskProvider_;
    }

    /* ========== BOOKKEEPING ========== */

    /**
     * @notice Transfer all pending deposits from the SmartVault to strategies
     * @dev Swap to match ratio and distribute across strategies
     *      as described in /notes/multi-asset-vault-deposit-ratios.md
     * @param smartVault Smart Vault address
     * @param swapInfo Swap info
     */
    function flushSmartVault(address smartVault, SwapInfo[] calldata swapInfo)
        external
        onlyRegisteredSmartVault(smartVault)
    {
        uint256 flushIdx = _flushIndexes[smartVault];
        uint256 withdrawals = _withdrawnVaultShares[smartVault][flushIdx];
        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        uint256[] memory flushDhwIndexes;

        if (_vaultDeposits[smartVault][flushIdx][0] > 0) {
            // handle deposits
            address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);

            DepositRatioQueryBag memory bag = DepositRatioQueryBag(
                smartVault,
                tokens,
                strategies_,
                _smartVaultAllocations[smartVault].toArray(strategies_.length),
                SpoolUtils.getExchangeRates(tokens, _priceFeedManager),
                SpoolUtils.getStrategyRatios(strategies_),
                _priceFeedManager.usdDecimals(),
                address(_masterWallet),
                address(_swapper)
            );

            _flushExchangeRates[smartVault][flushIdx].setValues(bag.exchangeRates);

            uint256[] memory deposits = _vaultDeposits[smartVault][flushIdx].toArray(tokens.length);
            uint256[][] memory distribution = SmartVaultDeposits.distributeVaultDeposits(bag, deposits, swapInfo);

            for (uint256 i = 0; i < strategies_.length; i++) {
                _vaultFlushedDeposits[smartVault][flushIdx][strategies_[i]].setValues(distribution[i]);
            }

            flushDhwIndexes = _strategyRegistry.addDeposits(bag.strategies, distribution);
        }

        if (withdrawals > 0) {
            // handle withdrawals
            uint256[] memory strategyWithdrawals = new uint256[](strategies_.length);

            for (uint256 i = 0; i < strategies_.length; i++) {
                uint256 strategyShares = IStrategy(strategies_[i]).balanceOf(smartVault);
                uint256 totalVaultShares = ISmartVault(smartVault).totalSupply();

                strategyWithdrawals[i] = strategyShares * withdrawals / totalVaultShares;
            }

            ISmartVault(smartVault).burn(smartVault, withdrawals);
            ISmartVault(smartVault).releaseStrategyShares(strategies_, strategyWithdrawals);

            flushDhwIndexes = _strategyRegistry.addWithdrawals(strategies_, strategyWithdrawals);

            _withdrawnStrategyShares[smartVault][flushIdx].setValues(strategyWithdrawals);
        }

        if (flushDhwIndexes.length == 0) revert NothingToFlush();

        _dhwIndexes[smartVault][flushIdx].setValues(flushDhwIndexes);
        _flushIndexes[smartVault] = flushIdx + 1;

        emit SmartVaultFlushed(smartVault, flushIdx);
    }

    function syncSmartVault(address smartVault) external {
        // TODO: sync yields
        // TODO: sync deposits

        address[] memory strategies = _smartVaultStrategies[smartVault];

        uint256 flushIndex = _flushIndexesToSync[smartVault];
        while (flushIndex < _flushIndexes[smartVault]) {
            // TODO: Check if all DHW indexes were processed for given flushIndex (here, not down the stack)

            uint256[] memory indexes = _dhwIndexes[smartVault][flushIndex].toArray(strategies.length);

            for (uint256 i = 0; i < strategies.length; i++) {
                uint256 dhwIndex = _dhwIndexes[smartVault][flushIndex][i];

                if (dhwIndex == _strategyRegistry.currentIndex(strategies[i])) {
                    revert DhwNotRunYetForIndex(strategies[i], dhwIndex);
                }
            }

            _syncWithdrawals(smartVault, flushIndex, strategies, indexes);
            _syncDeposits(smartVault, flushIndex, strategies, indexes);

            flushIndex++;
            _flushIndexesToSync[smartVault] = flushIndex;
        }
    }

    /**
     * @notice TODO
     */
    function reallocate() external {}

    /* ========== PRIVATE/INTERNAL FUNCTIONS ========== */

    function _depositAssets(address smartVault, address owner, address receiver, uint256[] memory assets)
        internal
        returns (uint256)
    {
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);
        _runGuards(smartVault, msg.sender, receiver, owner, assets, tokens, RequestType.Deposit);
        _runActions(smartVault, msg.sender, receiver, owner, assets, tokens, RequestType.Deposit);

        for (uint256 i = 0; i < assets.length; i++) {
            IERC20(tokens[i]).safeTransferFrom(owner, address(_masterWallet), assets[i]);
        }

        if (tokens.length != assets.length) revert InvalidAssetLengths();
        uint256 flushIdx = _flushIndexes[smartVault];

        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == 0) revert InvalidDepositAmount({smartVault: smartVault});
            _vaultDeposits[smartVault][flushIdx][i] += assets[i];
        }

        DepositMetadata memory metadata = DepositMetadata(assets, block.timestamp, flushIdx);
        return ISmartVault(smartVault).mintDepositNFT(receiver, metadata);
    }

    function _redeemShares(address smartVaultAddress, uint256 vaultShares, address receiver, address owner)
        internal
        returns (uint256)
    {
        ISmartVault smartVault = ISmartVault(smartVaultAddress);
        if (smartVault.balanceOf(owner) < vaultShares) {
            revert InsufficientBalance(smartVault.balanceOf(msg.sender), vaultShares);
        }

        // run guards
        uint256[] memory assets = new uint256[](1);
        assets[0] = vaultShares;
        address[] memory tokens = new address[](1);
        tokens[0] = smartVaultAddress;
        _runGuards(smartVaultAddress, msg.sender, receiver, owner, assets, tokens, RequestType.Withdrawal);

        // add withdrawal to be flushed
        uint256 flushIndex = _flushIndexes[smartVaultAddress];
        _withdrawnVaultShares[smartVaultAddress][flushIndex] += vaultShares;

        // transfer vault shares back to smart vault
        smartVault.transferFrom(owner, smartVaultAddress, vaultShares);
        return smartVault.mintWithdrawalNFT(receiver, WithdrawalMetadata(vaultShares, flushIndex));
    }

    function _calculateWithdrawal(
        address smartVault,
        uint256 withdrawalNftId,
        WithdrawalMetadata memory data,
        uint256 assetGroupLength
    ) internal view returns (uint256[] memory) {
        uint256[] memory withdrawnAssets = new uint256[](assetGroupLength);

        // loop over all assets
        for (uint256 i = 0; i < withdrawnAssets.length; i++) {
            withdrawnAssets[i] = _withdrawnAssets[smartVault][data.flushIndex][i] * data.vaultShares
                / _withdrawnVaultShares[smartVault][data.flushIndex];
        }

        return withdrawnAssets;
    }

    function _syncWithdrawals(
        address smartVault,
        uint256 flushIndex,
        address[] memory strategies,
        uint256[] memory dhwIndexes
    ) private {
        uint256 withdrawnShares = _withdrawnVaultShares[smartVault][flushIndex];

        if (withdrawnShares == 0) {
            return;
        }

        uint256[] memory withdrawnAssets_ = _strategyRegistry.claimWithdrawals(
            strategies, dhwIndexes, _withdrawnStrategyShares[smartVault][flushIndex].toArray(strategies.length)
        );

        _withdrawnAssets[smartVault][flushIndex].setValues(withdrawnAssets_);
    }

    function _syncDeposits(
        address smartVault,
        uint256 flushIndex,
        address[] memory strategies,
        uint256[] memory dhwIndexes
    ) private {
        if (_vaultDeposits[smartVault][flushIndex][0] == 0) {
            return;
        }

        uint256 vaultDepositUSDTotal = 0;
        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(_smartVaultAssetGroups[smartVault]);

        for (uint256 i = 0; i < strategies.length; i++) {
            StrategyAtIndex memory atDHW = _strategyRegistry.strategyAtIndex(strategies[i], dhwIndexes[i]);
            uint256[] memory vaultDeposits =
                _vaultFlushedDeposits[smartVault][flushIndex][strategies[i]].toArray(strategies.length);
            uint256 vaultDepositUSD =
                _priceFeedManager.assetToUsdCustomPriceBulk(assetGroup, vaultDeposits, atDHW.exchangeRates);
            uint256 slippageUSD =
                _priceFeedManager.assetToUsdCustomPriceBulk(assetGroup, atDHW.slippages, atDHW.exchangeRates);
            uint256 strategyDepositUSD =
                _priceFeedManager.assetToUsdCustomPriceBulk(assetGroup, atDHW.depositedAssets, atDHW.exchangeRates);

            uint256 vaultStrategyShares = atDHW.sharesMinted * vaultDepositUSD / strategyDepositUSD;

            vaultDepositUSDTotal += vaultDepositUSD - slippageUSD * vaultDepositUSD / strategyDepositUSD;
            IStrategy(strategies[i]).transferFrom(strategies[i], smartVault, vaultStrategyShares);
        }

        if (vaultDepositUSDTotal == 0) {
            return;
        }

        // TODO: What if total vault USD value is 0?
        uint256 toMint =
            vaultDepositUSDTotal * ISmartVault(smartVault).totalSupply() / getVaultTotalUsdValue(smartVault);

        // First cycle, after initial deposits
        if (toMint == 0) {
            toMint = 1000 ether;
        }

        ISmartVault(smartVault).mint(smartVault, toMint);
        _mintedVaultShares[smartVault][flushIndex] = toMint;
    }

    function _runGuards(
        address smartVault,
        address executor,
        address receiver,
        address owner,
        uint256[] memory assets,
        address[] memory assetGroup,
        RequestType requestType
    ) internal view {
        RequestContext memory context = RequestContext(receiver, executor, owner, requestType, assets, assetGroup);
        _guardManager.runGuards(smartVault, context);
    }

    function _runActions(
        address smartVault,
        address executor,
        address recipient,
        address owner,
        uint256[] memory assets,
        address[] memory assetGroup,
        RequestType requestType
    ) internal {
        ActionContext memory context = ActionContext(recipient, executor, owner, requestType, assetGroup, assets);
        _actionManager.runActions(smartVault, context);
    }

    function _onlyUnregisteredSmartVault(address smartVault) internal view {
        _checkRole(ROLE_SMART_VAULT, smartVault);
        if (_smartVaultRegistry[smartVault]) {
            revert SmartVaultAlreadyRegistered();
        }
    }

    function _onlyRegisteredSmartVault(address smartVault) internal view {
        _checkRole(ROLE_SMART_VAULT, smartVault);
        if (!_smartVaultRegistry[smartVault]) {
            revert SmartVaultNotRegisteredYet();
        }
    }

    /* ========== MODIFIERS ========== */

    modifier onlyUnregisteredSmartVault(address smartVault) {
        _onlyUnregisteredSmartVault(smartVault);
        _;
    }

    modifier onlyRegisteredSmartVault(address smartVault) {
        _onlyRegisteredSmartVault(smartVault);
        _;
    }
}
