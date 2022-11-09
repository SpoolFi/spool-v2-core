// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "./interfaces/IAssetGroupRegistry.sol";
import "./interfaces/IMasterWallet.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IStrategyRegistry.sol";

abstract contract Strategy is ERC20Upgradeable, IStrategy {
    /* ========== STATE VARIABLES ========== */

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
        IAssetGroupRegistry assetGroupRegistry_
    ) {
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

    function redeemFast(uint256 shares, address receiver, uint256[][] calldata slippages, SwapData[] calldata swapData)
        external
        returns (uint256[] memory returnedAssets)
    {
        revert("0");
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

    function _sharesPerAssets() internal view virtual returns (uint256) {
        return 0;
    }

    /* ========== MODIFIERS ========== */
}
