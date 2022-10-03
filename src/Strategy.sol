// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import "./interfaces/IStrategy.sol";

contract Strategy is IStrategy, ERC1155, Ownable {
    /* ========== STATE VARIABLES ========== */

    // @notice Name of the strategy
    string public immutable strategyName;

    constructor(string memory strategyName_) {
        strategyName = strategyName_;
    }

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
    ) external returns (uint256[] memory returnedAssets) {
        revert("0");
    }

    /**
     * @notice TODO
     * @param assets TODO
     * @param receiver TODO
     * @param slippages TODO
     * @return receipt TODO
     */
    function depositFast(uint256[] calldata assets, address receiver, uint256[][] calldata slippages)
        external
        returns (uint256 receipt)
    {
        revert("0");
    }
}
