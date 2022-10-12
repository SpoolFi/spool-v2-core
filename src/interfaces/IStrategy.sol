pragma solidity ^0.8.16;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "./IVault.sol";

/**
 * @notice Strict holding information how to swap the asset
 * @member slippage minumum output amount
 * @member path swap path, first byte represents an action (e.g. Uniswap V2 custom swap), rest is swap specific path
 */
struct SwapData {
    uint256 slippage; // min amount out
    bytes path; // 1st byte is action, then path
}

interface IStrategy is IVault {
    /* ========== EVENTS ========== */

    event Slippage(address strategy, IERC20 underlying, bool isDeposit, uint256 amountIn, uint256 amountOut);

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @return name Name of the strategy
     */
    function strategyName() external view returns (string memory name);

    /**
     * @return value Total value of strategy in USD.
     */
    function totalUsdValue() external view returns (uint256 value);

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Fast withdraw
     * @param assets TODO
     * @param tokens TODO
     * @param receiver TODO
     * @param slippages TODO
     * @param swapData TODO
     * @return returnedAssets Withdrawn amount withdrawn
     */
    function withdrawFast(
        uint256[] calldata assets,
        address[] calldata tokens,
        address receiver,
        uint256[][] calldata slippages,
        SwapData[] calldata swapData
    ) external returns (uint256[] memory returnedAssets);

    /**
     * @notice TODO
     * @param assets TODO
     * @param receiver TODO
     * @param slippages TODO
     * @return receipt TODO
     */
    function depositFast(uint256[] calldata assets, address receiver, uint256[][] calldata slippages)
        external
        returns (uint256 receipt);
}
