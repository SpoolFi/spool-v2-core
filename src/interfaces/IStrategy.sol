// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./ISwapper.sol";
import "./IUsdPriceFeedManager.sol";

/**
 * @notice Strict holding information how to swap the asset
 * @custom:member slippage minumum output amount
 * @custom:member path swap path, first byte represents an action (e.g. Uniswap V2 custom swap), rest is swap specific path
 */
struct SwapData {
    uint256 slippage; // min amount out
    bytes path; // 1st byte is action, then path
}

struct DhwInfo {
    uint256 sharesMinted;
    uint256[] assetsWithdrawn;
}

error IsGhostStrategy();

interface IStrategy is IERC20Upgradeable {
    /* ========== EVENTS ========== */

    event Slippage(address strategy, IERC20 underlying, bool isDeposit, uint256 amountIn, uint256 amountOut);

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Returns APY value of the strategy
     */
    function getAPY() external view returns (uint16);

    /**
     * @return name Name of the strategy
     */
    function strategyName() external view returns (string memory name);

    /**
     * @return value Total value of strategy in USD.
     */
    function totalUsdValue() external view returns (uint256 value);

    /**
     * @notice
     */
    function assetRatio() external view returns (uint256[] memory ratio);

    /**
     * @notice Gets asset group used by the strategy.
     * @return id ID of the asset group.
     */
    function assetGroupId() external view returns (uint256 id);

    /**
     * @dev Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
     *
     * - MUST be an ERC-20 token contract.
     * - MUST NOT revert.
     */
    function assets() external view returns (address[] memory assetTokenAddresses);

    /* ========== MUTATIVE FUNCTIONS ========== */

    function doHardWork(
        SwapInfo[] calldata swapInfo,
        uint256 withdrawnShares,
        address masterWallet,
        uint256[] calldata exchangeRates,
        IUsdPriceFeedManager priceFeedManager
    ) external returns (DhwInfo memory);

    function claimShares(address claimer, uint256 amount) external;

    function releaseShares(address smartVault, uint256 amount) external;

    /**
     * @notice Instantly redeems strategy shares for assets.
     * @param shares Amount of shares to redeem.
     * @param masterWallet Address of master wallet.
     * @param assetGroup Asset group.
     * @param exchangeRates Asset to USD exchange rates.
     * @param priceFeedManager Price feed manager contract.
     * @return assetsWithdrawn Amount of assets withdrawn.
     */
    function redeemFast(
        uint256 shares,
        address masterWallet,
        address[] memory assetGroup,
        uint256[] memory exchangeRates,
        IUsdPriceFeedManager priceFeedManager
    ) external returns (uint256[] memory assetsWithdrawn);

    function depositFast(
        address[] calldata assetGroup,
        uint256[] calldata exchangeRates,
        IUsdPriceFeedManager priceFeedManager
    ) external returns (uint256 sstsMinted);
}
