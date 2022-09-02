pragma solidity ^0.8.16;

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

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Fast withdraw
     * @param shares Shares to fast withdraw
     * @param slippages Array of slippage parameters to apply when withdrawing
     * @param swapData Swap slippage and path array
     * @return Withdrawn amount withdrawn
     */
    function withdrawFast(
        uint256[] calldata assets,
        address[] tokens,
        address receiver,
        uint256[][] slippages,
        SwapData[] calldata swapData
    ) external override returns(uint256[] assets);

    /**
     * @notice TODO
     * @param assets
     * @param receiver
     * @param slippages
     * @return receipt
     */
    function depositFast(
        uint256[] calldata assets,
        address receiver,
        uint256[][] calldata slippages
    ) external returns (uint256 receipt);
}
