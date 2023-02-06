// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

uint256 constant SECONDS_IN_YEAR = 31_556_926;

uint256 constant FULL_PERCENT = 100_00;

uint256 constant MANAGEMENT_FEE_MAX = 5_00;

uint256 constant DEPOSIT_FEE_MAX = 5_00;

uint8 constant MAX_RISK_SCORE = 10_0;

uint8 constant MIN_RISK_SCORE = 1;

int8 constant MAX_RISK_TOLERANCE = 10;

int8 constant MIN_RISK_TOLERANCE = -10;

/*
 * @notice If set as risk provider, system will return fixed risk score values
 */
address constant STATIC_RISK_PROVIDER = address(0xaaa);

/*
 * @notice Fixed values to use if risk provider is set to STATIC_RISK_PROVIDER
 */
uint8 constant STATIC_RISK_SCORE = 1;

/// @dev Maximal value of deposit NFT ID.
uint256 constant MAXIMAL_DEPOSIT_ID = 2 ** 255 - 1;

/// @dev Maximal value of withdrawal NFT ID.
uint256 constant MAXIMAL_WITHDRAWAL_ID = 2 ** 256 - 1;

/// @dev How many shares will be minted with a NFT
uint256 constant NFT_MINTED_SHARES = 10 ** 6;
