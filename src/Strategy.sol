// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "./interfaces/IAssetGroupRegistry.sol";
import "./interfaces/IMasterWallet.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IStrategyRegistry.sol";
import "./access/SpoolAccessControl.sol";

abstract contract Strategy is ERC20Upgradeable, SpoolAccessControllable, IStrategy {
    /* ========== STATE VARIABLES ========== */

    uint256 internal constant INITIAL_SHARE_MULTIPLIER = 1000000000000000000000000000000;  // 10 ** 30

    IStrategyRegistry internal immutable _strategyRegistry;

    IAssetGroupRegistry internal immutable _assetGroupRegistry;

    // @notice Name of the strategy
    string private _strategyName;

    /**
     * @notice ID of the asset group used by the strategy.
     */
    uint256 internal _assetGroupId;

    // @notice Total value (in USD) of assets managed by the strategy.
    // @dev Should be updated in DHW with deposits, withdrawals and yields.
    uint256 public totalUsdValue = 0;

    constructor(
        string memory strategyName_,
        IStrategyRegistry strategyRegistry_,
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_
    ) SpoolAccessControllable(accessControl_) {
        _strategyName = strategyName_;
        _strategyRegistry = strategyRegistry_;
        _assetGroupRegistry = assetGroupRegistry_;
    }

    function initialize(uint256 assetGroupId_) public virtual initializer {
        _assetGroupId = assetGroupId_;

        __ERC20_init("Strategy Share Token", "SST");
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function assetGroupId() external view returns (uint256) {
        return _assetGroupId;
    }

    function assets() external view returns (address[] memory) {
        return _assetGroupRegistry.listAssetGroup(_assetGroupId);
    }

    function assetRatio() external view virtual returns (uint256[] memory);

    function totalAssets() external view returns (uint256[] memory totalManagedAssets) {
        revert("0");
    }

    function strategyName() external view returns (string memory) {
        return _strategyName;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function doHardWork(
        SwapInfo[] calldata swapInfo,
        uint256 withdrawnShares,
        address masterWallet,
        uint256[] calldata exchangeRates,
        IUsdPriceFeedManager priceFeedManager
    ) external returns (DhwInfo memory) {
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_assetGroupId);

        // deposits
        // - swap assets to correct ratio
        swapAssets(tokens, swapInfo);

        // - get amount of assets available to deposit
        uint256[] memory assetsToDeposit = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            assetsToDeposit[i] = IERC20(tokens[i]).balanceOf(address(this));
        }

        // - deposit assets
        uint256 usdWorth0 = getUsdWorth(exchangeRates, priceFeedManager);
        depositToProtocol(tokens, assetsToDeposit);
        uint256 usdWorth1 = getUsdWorth(exchangeRates, priceFeedManager);

        // - mint SSTs
        uint256 usdWorthDeposited = usdWorth1 - usdWorth0;
        uint256 sstsToMint;
        if (usdWorth0 > 0) {
            sstsToMint = usdWorthDeposited * totalSupply() / usdWorth0;
        } else {
            sstsToMint = usdWorthDeposited * INITIAL_SHARE_MULTIPLIER;
        }
        _mint(address(this), sstsToMint);

        // withdrawal
        // - redeem shares from protocol
        redeemFromProtocol(tokens, withdrawnShares);
        _burn(address(this), withdrawnShares);
        uint256 usdWorth2 = getUsdWorth(exchangeRates, priceFeedManager);

        totalUsdValue = usdWorth2;

        // - transfer assets to master wallet
        uint256[] memory withdrawnAssets = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            withdrawnAssets[i] = IERC20(tokens[i]).balanceOf(address(this));
            IERC20(tokens[i]).transfer(masterWallet, withdrawnAssets[i]);
        }

        return DhwInfo({usdRouted: usdWorthDeposited, sharesMinted: sstsToMint, assetsWithdrawn: withdrawnAssets});
    }

    function redeemFast(uint256 shares, address receiver, uint256[][] calldata slippages, SwapData[] calldata swapData)
        external
        returns (uint256[] memory returnedAssets)
    {
        revert("0");
    }

    function claimShares(address claimer, uint256 amount) external onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender) {
        _transfer(address(this), claimer, amount);
    }

    function depositFast(uint256[] calldata assets, address receiver, uint256[][] calldata slippages)
        external
        returns (uint256 receipt)
    {
        revert("0");
    }

    function convertToAssets(uint256 shares) external view returns (uint256[] memory assets) {
        revert("0");
    }

    function deposit(uint256[] calldata assets, address receiver) external returns (uint256 receipt) {
        revert("0");
    }

    function redeem(uint256 shares, address receiver, address owner) external virtual returns (uint256[] memory) {
        revert("0");
    }

    /* ========== PRIVATE/INTERNAL FUNCTIONS ========== */

    function swapAssets(address[] memory tokens, SwapInfo[] calldata swapInfo) internal virtual;

    function depositToProtocol(address[] memory tokens, uint256[] memory amounts) internal virtual;

    function getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        virtual
        returns (uint256);

    function redeemFromProtocol(address[] memory tokens, uint256 ssts) internal virtual;

    /* ========== MODIFIERS ========== */
}
