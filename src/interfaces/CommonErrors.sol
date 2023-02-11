// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/**
 * @notice Used when an array has invalid length.
 */
error InvalidArrayLength();

/**
 * @notice Used when group of smart vaults or strategies do not have same asset group.
 */
error NotSameAssetGroup();

/**
 * @notice Used when fetched exchange rate is out of slippage range.
 */
error ExchangeRateOutOfSlippages();
