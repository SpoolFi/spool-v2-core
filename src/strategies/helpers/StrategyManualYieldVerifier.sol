// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../../access/SpoolAccessControllable.sol";

/// @notice Used when manual yield is more than allowed.
error TooBigManualYield(int256 manualYield);

/// @notice Used when manual yield is less than allowed.
error TooSmallManualYield(int256 manualYield);

abstract contract StrategyManualYieldVerifier is SpoolAccessControllable {
    /// @notice
    int128 public positiveLimit;
    int128 public negativeLimit;

    /**
     * @notice Sets positive yield limit.
     * @param positiveLimit_ new positive yield limit.
     */
    function setPositiveLimit(int128 positiveLimit_) external onlyRole(ROLE_SPOOL_ADMIN, msg.sender) {
        _setPositiveLimit(positiveLimit_);
    }

    /**
     * @notice Sets negative yield limit.
     * @param negativeLimit_ new negative yield limit.
     */
    function setNegativeLimit(int128 negativeLimit_) external onlyRole(ROLE_SPOOL_ADMIN, msg.sender) {
        _setNegativeLimit(negativeLimit_);
    }

    function _setPositiveLimit(int128 positiveLimit_) internal {
        if (positiveLimit_ < 0) revert InvalidConfiguration();
        positiveLimit = positiveLimit_;
    }

    function _setNegativeLimit(int128 negativeLimit_) internal {
        if (negativeLimit_ > 0) revert InvalidConfiguration();
        negativeLimit = negativeLimit_;
    }

    /**
     * @notice Verify manual yield is inside set parameters.
     * @param manualYield Manual yiedl value to verify.
     */
    function _verifyManualYieldPercentage(int256 manualYield) internal view virtual {
        if (manualYield > 0) {
            if (manualYield > positiveLimit) {
                revert TooBigManualYield(manualYield);
            }
        } else if (manualYield < 0) {
            if (manualYield < negativeLimit) {
                revert TooSmallManualYield(manualYield);
            }
        }
    }
}
