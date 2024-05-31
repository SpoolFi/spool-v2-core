// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./GearboxV3Strategy.sol";

address constant EXTRACTION_ADDRESS = 0x341DC9A5Ec66EEb5cA8988184D35893227BF2B6c;

/**
 * @notice Used when trying to extract airdropped tokens that are not allowed.
 */
error NotAirdropToken();

// This is the same contract as GearboxV3Strategy.sol, but with ability to
// extract airdropped tokens.
contract GearboxV3AirdropStrategy is GearboxV3Strategy {
    using SafeERC20 for IERC20;

    /**
     * @notice Emitted when a token airdrop status is updated.
     * @param token Address of the token.
     * @param isAirdropToken Boolean indicating whether the token is an airdrop token.
     */
    event AirdropTokenUpdated(address indexed token, bool isAirdropToken);

    /**
     * @dev Mapping of whether a token is an airdrop token.
     */
    mapping(address => bool) private _isAirdropToken;

    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, ISwapper swapper_)
        GearboxV3Strategy(assetGroupRegistry_, accessControl_, swapper_)
    {}

    /**
     * @notice Extracts airdropped REZ tokens.
     * @dev Requirements:
     * - caller must have role ROLE_EMERGENCY_WITHDRAWAL_EXECUTOR
     * - token must be an airdrop token
     * @param token Address of the token to extract.
     */
    function extractAirdrop(address token) external onlyRole(ROLE_EMERGENCY_WITHDRAWAL_EXECUTOR, msg.sender) {
        if (!_isAirdropToken[token]) {
            revert NotAirdropToken();
        }

        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(EXTRACTION_ADDRESS, balance);
    }

    /**
     * @notice Sets whether a token is an airdrop token.
     * @dev Requirements:
     * - caller must have role ROLE_SPOOL_ADMIN
     * @param token Address of the token to set.
     * @param isAirdropToken_ Boolean indicating whether the token is an airdrop token.
     */
    function setAirdropToken(address token, bool isAirdropToken_) external onlyRole(ROLE_SPOOL_ADMIN, msg.sender) {
        _isAirdropToken[token] = isAirdropToken_;
        emit AirdropTokenUpdated(token, isAirdropToken_);
    }
}
