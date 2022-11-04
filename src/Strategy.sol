// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IStrategyRegistry.sol";
import "./interfaces/IMasterWallet.sol";

abstract contract Strategy is ERC20Upgradeable, IStrategy {
    /* ========== STATE VARIABLES ========== */

    IStrategyRegistry internal immutable _strategyRegistry;

    // @notice Name of the strategy
    string private _strategyName;

    // @notice Asset group addresses
    address[] internal _assetGroup;

    // @notice Total value (in USD) of assets managed by the strategy.
    // @dev Should be updated in DHW with deposits, withdrawals and yields.
    uint256 public totalUsdValue = 0;

    constructor(string memory strategyName_, IStrategyRegistry strategyRegistry_) {
        _strategyName = strategyName_;
        _strategyRegistry = strategyRegistry_;
    }

    function initialize(address[] memory assetGroup_) public virtual initializer {
        __ERC20_init("Strategy Share Token", "SST");
        _assetGroup = assetGroup_;
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function assets() external view returns (address[] memory assetTokenAddresses) {
        return _assetGroup;
    }

    function assetRatio() external view virtual returns (uint256[] memory);

    function totalAssets() external view returns (uint256[] memory totalManagedAssets) {
        revert("0");
    }

    function strategyName() external view returns (string memory) {
        return _strategyName;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function redeemFast(
        uint256[] calldata assets,
        address[] calldata tokens,
        address receiver,
        uint256[][] calldata slippages,
        SwapData[] calldata swapData
    ) external returns (uint256[] memory returnedAssets) {
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
