// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IStrategyRegistry.sol";

contract Strategy is ERC20Upgradeable, IStrategy {
    /* ========== STATE VARIABLES ========== */

    IStrategyRegistry internal immutable _strategyRegistry;

    // @notice Name of the strategy
    string private _strategyName;

    // @notice Asset group addresses
    address[] internal _assetGroup;

    // @notice Total value (in USD) of assets managed by the strategy.
    // @dev Should be updated in DHW with deposits, withdrawals and yields.
    uint256 public totalUsdValue = 0;

    constructor(string memory strategyName_, IStrategyRegistry StrategyRegistry_) {
        _strategyName = strategyName_;
        _strategyRegistry = StrategyRegistry_;
    }

    function initialize(address[] memory assetGroup_) external initializer {
        __ERC20_init("Strategy Share Token", "SST");
        _assetGroup = assetGroup_;
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function asset() external view returns (address[] memory assetTokenAddresses) {
        return _assetGroup;
    }

    function totalAssets() external view returns (uint256[] memory totalManagedAssets) {
        revert("0");
    }

    function previewDeposit(uint256[] calldata assets) external view returns (uint256 shares) {
        revert("0");
    }

    function maxMint(address receiver) external view returns (uint256 maxShares) {
        revert("0");
    }

    function previewMint(uint256 shares) external view returns (uint256[] memory assets) {
        revert("0");
    }

    function previewWithdraw(uint256[] calldata assets) external view returns (uint256 shares) {
        revert("0");
    }

    function maxRedeem(address owner) external view returns (uint256 maxShares) {
        revert("0");
    }

    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        revert("0");
    }

    function strategyName() external view returns (string memory) {
        return _strategyName;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function withdrawFast(
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

    function convertToShares(uint256[] calldata assets) external view returns (uint256 shares) {
        revert("0");
    }

    function convertToAssets(uint256 shares) external view returns (uint256[] memory assets) {
        revert("0");
    }

    function maxDeposit(address receiver) external view returns (uint256[] memory maxAssets) {
        revert("0");
    }

    function deposit(uint256[] calldata assets, address receiver) external returns (uint256 receipt) {
        revert("0");
    }

    function mint(uint256 shares, address receiver) external returns (uint256[] memory assets) {
        revert("0");
    }

    function withdraw(uint256[] calldata assets, address[] calldata tokens, address receiver, address owner)
        external
        returns (uint256 receipt)
    {
        revert("0");
    }

    function maxWithdraw(address owner) external view returns (uint256[] memory maxAssets) {
        revert("0");
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 receipt) {
        revert("0");
    }

    /* ========== PRIVATE/INTERNAL FUNCTIONS ========== */

    function _sharesPerAssets() internal view virtual returns (uint256) {
        return 0;
    }

    /* ========== MODIFIERS ========== */
}
