// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

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

contract SmartVaultRegistry is ISmartVaultRegistry {
    /// @notice Smart vault address registry
    mapping(address => bool) internal _smartVaults;

    /**
     * @notice Checks whether an address is a registered Smart Vault
     */
    function isSmartVault(address address_) external view returns (bool) {
        return _smartVaults[address_];
    }

    /**
     * @notice Add a Smart Vault to the registry
     */
    function registerSmartVault(address smartVault) external {
        if (_smartVaults[smartVault]) revert SmartVaultAlreadyRegistered({address_: smartVault});
        _smartVaults[smartVault] = true;
    }

    /**
     * @notice Remove a Smart Vault
     */
    function removeSmartVault(address smartVault) external validSmartVault(smartVault) {
        _smartVaults[smartVault] = false;
    }

    /* ========== MODIFIERS ========== */

    modifier validSmartVault(address address_) {
        if (!_smartVaults[address_]) revert InvalidSmartVault({address_: address_});
        _;
    }
}

contract SmartVaultDeposits is ISmartVaultDeposits {
    /// @notice Deposit ratio precision
    uint256 constant RATIO_PRECISION = 10 ** 22;

    /// @notice Vault-strategy allocation precision
    uint256 constant ALLOC_PRECISION = 1000;

    /// @notice Difference between desired and actual amounts in WEI after swapping
    uint256 constant SWAP_TOLERANCE = 500;

    /// @notice Address that holds funds before they're processed by DHW or claimed by user.
    IMasterWallet private immutable _masterWallet;

    constructor(IMasterWallet masterWallet_) {
        _masterWallet = masterWallet_;
    }

    /**
     * @notice Calculate current Smart Vault asset deposit ratio
     * @dev As described in /notes/multi-asset-vault-deposit-ratios.md
     */
    function getDepositRatio(DepositRatioQueryBag memory bag) external pure returns (uint256[] memory) {
        uint256[] memory outRatios = new uint256[](bag.tokens.length);

        if (bag.tokens.length == 1) {
            outRatios[0] = 1;
            return outRatios;
        }

        uint256[][] memory ratios = _getDepositRatios(bag);
        for (uint256 i = 0; i < bag.strategies.length; i++) {
            for (uint256 j = 0; j < bag.tokens.length; j++) {
                outRatios[j] += ratios[i][j];
            }
        }

        for (uint256 j = bag.tokens.length; j > 0; j--) {
            outRatios[j - 1] = outRatios[j - 1] * RATIO_PRECISION / outRatios[0];
        }

        return outRatios;
    }

    /**
     * @notice Calculate Smart Vault deposit distributions for underlying strategies based on their
     * internal ratio.
     * @param bag Deposit specific parameters
     * @param swapInfo Information needed to perform asset swaps
     * @return Token deposit amounts per strategy
     */
    function distributeVaultDeposits(
        DepositRatioQueryBag memory bag,
        uint256[] memory depositsIn,
        SwapInfo[] calldata swapInfo
    ) external returns (uint256[][] memory) {
        if (bag.tokens.length != depositsIn.length) revert InvalidAssetLengths();

        uint256[] memory decimals = new uint256[](bag.tokens.length);
        uint256[][] memory depositRatios;
        uint256 depositUSD = 0;

        depositRatios = _getDepositRatios(bag);

        for (uint256 j = 0; j < bag.tokens.length; j++) {
            decimals[j] = ERC20(bag.tokens[j]).decimals();
            depositUSD += bag.exchangeRates[j] * depositsIn[j] / 10 ** decimals[j];
        }

        DepositBag memory depositBag = DepositBag(
            bag.tokens,
            bag.strategies,
            depositsIn,
            decimals,
            bag.exchangeRates,
            depositRatios,
            depositUSD,
            bag.usdDecimals
        );

        depositBag.depositsIn = _swapToRatio(depositBag, swapInfo);
        return _distributeAcrossStrategies(depositBag);
    }

    /**
     * @notice Swap to match required ratio
     * TODO: take slippage into consideration
     * TODO: check if "swap" feature is exploitable
     */
    function _swapToRatio(DepositBag memory bag, SwapInfo[] memory swapInfo) internal returns (uint256[] memory) {
        uint256[] memory oldBalances = _getBalances(bag.tokens);
        for (uint256 i; i < swapInfo.length; i++) {
            _swap(swapInfo[i]);
        }
        uint256[] memory newBalances = _getBalances(bag.tokens);
        uint256[] memory depositsOut = new uint256[](bag.tokens.length);

        for (uint256 i = 0; i < bag.tokens.length; i++) {
            uint256 ratio = 0;

            for (uint256 j = 0; j < bag.depositRatios.length; j++) {
                ratio += bag.depositRatios[j][i];
            }

            // Add/Subtract swapped amounts
            if (newBalances[i] >= oldBalances[i]) {
                depositsOut[i] = bag.depositsIn[i] + (newBalances[i] - oldBalances[i]);
            } else {
                depositsOut[i] = bag.depositsIn[i] - (oldBalances[i] - newBalances[i]);
            }

            // Desired token deposit amount
            uint256 desired = ratio * bag.depositUSD * 10 ** bag.decimals[i] / 10 ** bag.usdDecimals / RATIO_PRECISION;

            // Check discrepancies
            bool isOk = desired == depositsOut[i]
                || desired > depositsOut[i] && (desired - depositsOut[i]) < SWAP_TOLERANCE
                || desired < depositsOut[i] && (depositsOut[i] - desired) < SWAP_TOLERANCE;

            if (!isOk) {
                revert IncorrectDepositRatio();
            }
        }

        return depositsOut;
    }

    function _distributeAcrossStrategies(DepositBag memory bag) internal pure returns (uint256[][] memory) {
        uint256[] memory depositAccum = new uint256[](bag.tokens.length);
        uint256[][] memory strategyDeposits = new uint256[][](bag.strategies.length);
        uint256 usdPrecision = 10 ** bag.usdDecimals;

        for (uint256 i = 0; i < bag.strategies.length; i++) {
            strategyDeposits[i] = new uint256[](bag.tokens.length);

            for (uint256 j = 0; j < bag.tokens.length; j++) {
                uint256 tokenPrecision = 10 ** bag.decimals[j];
                strategyDeposits[i][j] =
                    bag.depositUSD * bag.depositRatios[i][j] * tokenPrecision / RATIO_PRECISION / usdPrecision;
                depositAccum[j] += strategyDeposits[i][j];

                // Dust
                if (i == bag.strategies.length - 1) {
                    strategyDeposits[i][j] += bag.depositsIn[j] - depositAccum[j];
                }
            }
        }

        return strategyDeposits;
    }

    function _getDepositRatios(DepositRatioQueryBag memory bag) internal pure returns (uint256[][] memory) {
        uint256[][] memory outRatios = new uint256[][](bag.strategies.length);
        if (bag.strategies.length != bag.allocations.length) revert InvalidArrayLength();

        uint256 usdPrecision = 10 ** bag.usdDecimals;

        for (uint256 i = 0; i < bag.strategies.length; i++) {
            outRatios[i] = new uint256[](bag.tokens.length);
            uint256 ratioNorm = 0;

            for (uint256 j = 0; j < bag.tokens.length; j++) {
                ratioNorm += bag.exchangeRates[j] * bag.strategyRatios[i][j];
            }

            for (uint256 j = 0; j < bag.tokens.length; j++) {
                outRatios[i][j] += bag.allocations[i] * bag.strategyRatios[i][j] * usdPrecision * RATIO_PRECISION
                    / ratioNorm / ALLOC_PRECISION;
            }
        }

        return outRatios;
    }

    function _getBalances(address[] memory tokens) private view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = ERC20(tokens[i]).balanceOf(address(_masterWallet));
        }

        return balances;
    }

    function _swap(SwapInfo memory _swapInfo) private {
        _masterWallet.approve(IERC20(_swapInfo.token), _swapInfo.swapTarget, _swapInfo.amountIn);
        (bool success, bytes memory data) = _swapInfo.swapTarget.call(_swapInfo.swapCallData);
        if (!success) revert(_getRevertMsg(data));

        _masterWallet.resetApprove(IERC20(_swapInfo.token), _swapInfo.swapTarget);
    }

    /**
     * @dev Gets revert message when a low-level call reverts, so that it can
     * be bubbled-up to caller.
     * @param _returnData Data returned from reverted low-level call.
     * @return Revert message.
     */
    function _getRevertMsg(bytes memory _returnData) private pure returns (string memory) {
        // if the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) {
            return "CompositeOrder::getRevertMsg: Transaction reverted silently.";
        }

        assembly {
            // slice the sig hash
            _returnData := add(_returnData, 0x04)
        }

        return abi.decode(_returnData, (string)); // all that remains is the revert string
    }
}

contract SmartVaultManager is SmartVaultRegistry, ISmartVaultManager {
    using SafeERC20 for ERC20;
    using ArrayMapping for mapping(uint256 => uint256);

    /* ========== STATE VARIABLES ========== */

    // @notice Guard manager
    IGuardManager internal immutable _guardManager;

    // @notice Action manager
    IActionManager internal immutable _actionManager;

    /// @notice Strategy registry
    IStrategyRegistry private immutable _strategyRegistry;

    /// @notice Price Feed Manager
    IUsdPriceFeedManager private immutable _priceFeedManager;

    /// @notice Risk manager
    IRiskManager private immutable _riskManager;

    /// @notice Vault deposits logic
    ISmartVaultDeposits private immutable _vaultDepositsManager;

    IAssetGroupRegistry private immutable _assetGroupRegistry;

    /// @notice TODO
    IMasterWallet private immutable _masterWallet;

    mapping(address => uint256) internal _assetGroups;

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
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) _vaultDeposits;

    /// @notice TODO smart vault => flush index => vault shares withdrawn
    mapping(address => mapping(uint256 => uint256)) _withdrawnVaultShares;

    /// @notice TODO smart vault => flush index => strategy shares withdrawn
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) _withdrawnStrategyShares;

    /// @notice TODO smart vault => flush index => assets withdrawn
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) _withdrawnAssets;

    constructor(
        IStrategyRegistry strategyRegistry_,
        IRiskManager riskManager_,
        ISmartVaultDeposits vaultDepositsManager_,
        IUsdPriceFeedManager priceFeedManager_,
        IAssetGroupRegistry assetGroupRegistry_,
        IMasterWallet masterWallet_,
        IActionManager actionManager_,
        IGuardManager guardManager_
    ) {
        _strategyRegistry = strategyRegistry_;
        _riskManager = riskManager_;
        _vaultDepositsManager = vaultDepositsManager_;
        _priceFeedManager = priceFeedManager_;
        _assetGroupRegistry = assetGroupRegistry_;
        _masterWallet = masterWallet_;
        _actionManager = actionManager_;
        _guardManager = guardManager_;
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
    function getLatestFlushIndex(address smartVault) external view returns (uint256) {
        return _flushIndexes[smartVault];
    }

    /**
     * @notice Smart vault deposits for given flush index.
     */
    function smartVaultDeposits(address smartVault, uint256 flushIdx) external view returns (uint256[] memory) {
        uint256 assetGroupLength = _assetGroupRegistry.assetGroupLength(_assetGroups[smartVault]);
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
    function getVaultTotalUsdValue(address smartVault) external view returns (uint256) {
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
    function getDepositRatio(address smartVault) external view validSmartVault(smartVault) returns (uint256[] memory) {
        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_assetGroups[smartVault]);
        DepositRatioQueryBag memory bag = DepositRatioQueryBag(
            smartVault,
            tokens,
            strategies_,
            _smartVaultAllocations[smartVault].toArray(strategies_.length),
            _getExchangeRates(tokens),
            _getStrategyRatios(strategies_),
            _priceFeedManager.usdDecimals()
        );

        return _vaultDepositsManager.getDepositRatio(bag);
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
        validSmartVault(smartVault)
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
    ) external validSmartVault(smartVault) returns (uint256[] memory) {
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
        validSmartVault(smartVault)
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
    ) external validSmartVault(smartVault) returns (uint256) {
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
        validSmartVault(smartVault)
        returns (uint256)
    {
        return _depositAssets(smartVault, msg.sender, receiver, assets);
    }

    function claimWithdrawal(address smartVaultAddress, uint256 withdrawalNftId, address receiver)
        external
        validSmartVault(smartVaultAddress)
        returns (uint256[] memory, uint256)
    {
        ISmartVault smartVault = ISmartVault(smartVaultAddress);
        WithdrawalMetadata memory data = smartVault.getWithdrawalMetadata(withdrawalNftId);
        smartVault.burnNFT(msg.sender, withdrawalNftId, RequestType.Withdrawal);

        uint256 assetGroupID = _assetGroups[smartVaultAddress];
        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupID);
        uint256[] memory withdrawnAssets =
            _calculateWithdrawal(smartVaultAddress, withdrawalNftId, data, assetGroup.length);

        _runActions(smartVaultAddress, msg.sender, receiver, withdrawnAssets, assetGroup, RequestType.Withdrawal);

        for (uint256 i = 0; i < assetGroup.length; i++) {
            // TODO-Q: should this be done by an action, since there might be a swap?
            _masterWallet.transfer(IERC20(assetGroup[i]), receiver, withdrawnAssets[i]);
        }

        return (withdrawnAssets, assetGroupID);
    }

    /* ========== REGISTRY ========== */

    /**
     * @notice TODO
     */
    function setStrategies(address smartVault, address[] memory strategies_) external validSmartVault(smartVault) {
        if (strategies_.length == 0) revert EmptyStrategyArray();

        for (uint256 i = 0; i < strategies_.length; i++) {
            address strategy = strategies_[i];
            if (!_strategyRegistry.isStrategy(strategy)) {
                revert InvalidStrategy(strategy);
            }
        }

        _smartVaultStrategies[smartVault] = strategies_;
    }

    /**
     * @notice TODO
     */
    function setAllocations(address smartVault, uint256[] memory allocations_) external validSmartVault(smartVault) {
        _smartVaultAllocations[smartVault].setValues(allocations_);
    }

    /**
     * @notice TODO
     */
    function setRiskProvider(address smartVault, address riskProvider_) external validRiskProvider(riskProvider_) {
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
    function flushSmartVault(address smartVault, SwapInfo[] calldata swapInfo) external validSmartVault(smartVault) {
        uint256 flushIdx = _flushIndexes[smartVault];
        address[] memory strategies_ = _smartVaultStrategies[smartVault];

        uint256 withdrawals = _withdrawnVaultShares[smartVault][flushIdx];

        uint256[] memory flushDhwIndexes;

        if (_vaultDeposits[smartVault][flushIdx][0] > 0) {
            // handle deposits
            address[] memory tokens = _assetGroupRegistry.listAssetGroup(_assetGroups[smartVault]);

            DepositRatioQueryBag memory bag = DepositRatioQueryBag(
                smartVault,
                tokens,
                strategies_,
                _smartVaultAllocations[smartVault].toArray(strategies_.length),
                _getExchangeRates(tokens),
                _getStrategyRatios(strategies_),
                _priceFeedManager.usdDecimals()
            );

            uint256[] memory deposits = _vaultDeposits[smartVault][flushIdx].toArray(tokens.length);
            uint256[][] memory distribution = _vaultDepositsManager.distributeVaultDeposits(bag, deposits, swapInfo);
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

        while (_flushIndexesToSync[smartVault] < _flushIndexes[smartVault]) {
            _syncWithdrawals(smartVault, _flushIndexesToSync[smartVault]);

            _flushIndexesToSync[smartVault]++;
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
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_assetGroups[smartVault]);
        _runGuards(smartVault, owner, receiver, assets, tokens, RequestType.Deposit);
        _runActions(smartVault, owner, receiver, assets, tokens, RequestType.Deposit);

        for (uint256 i = 0; i < assets.length; i++) {
            ERC20(tokens[i]).safeTransferFrom(owner, address(_masterWallet), assets[i]);
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
        _runGuards(smartVaultAddress, msg.sender, receiver, assets, tokens, RequestType.Withdrawal);

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

    function _getStrategyRatios(address[] memory strategies_) internal view returns (uint256[][] memory) {
        uint256[][] memory ratios = new uint256[][](strategies_.length);
        for (uint256 i = 0; i < strategies_.length; i++) {
            ratios[i] = IStrategy(strategies_[i]).assetRatio();
        }

        return ratios;
    }

    function _getExchangeRates(address[] memory tokens) internal view returns (uint256[] memory) {
        uint256[] memory exchangeRates = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            exchangeRates[i] = _priceFeedManager.assetToUsd(tokens[i], 10 ** ERC20(tokens[i]).decimals());
        }

        return exchangeRates;
    }

    function _syncWithdrawals(address smartVault, uint256 flushIndex) private {
        uint256 withdrawnShares = _withdrawnVaultShares[smartVault][flushIndex];

        if (withdrawnShares == 0) {
            return;
        }

        address[] memory strategies_ = _smartVaultStrategies[smartVault];
        uint256[] memory withdrawnAssets_ = _strategyRegistry.claimWithdrawals(
            strategies_,
            _dhwIndexes[smartVault][flushIndex].toArray(strategies_.length),
            _withdrawnStrategyShares[smartVault][flushIndex].toArray(strategies_.length)
        );

        _withdrawnAssets[smartVault][flushIndex].setValues(withdrawnAssets_);
    }

    function _runGuards(
        address smartVault,
        address executor,
        address receiver,
        uint256[] memory assets,
        address[] memory assetGroup,
        RequestType requestType
    ) internal view {
        RequestContext memory context = RequestContext(receiver, executor, requestType, assets, assetGroup);
        _guardManager.runGuards(smartVault, context);
    }

    function _runActions(
        address smartVault,
        address executor,
        address recipient,
        uint256[] memory assets,
        address[] memory assetGroup,
        RequestType requestType
    ) internal {
        ActionContext memory context = ActionContext(recipient, executor, requestType, assetGroup, assets);
        _actionManager.runActions(smartVault, context);
    }

    /* ========== MODIFIERS ========== */

    modifier validRiskProvider(address address_) {
        if (!_riskManager.isRiskProvider(address_)) revert InvalidRiskProvider({address_: address_});
        _;
    }
}
