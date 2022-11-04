/**
 * @notice Used when function that can only be called by SmartVaultManagerd is called by some other account.
 * @param caller Actual caller of the function.
 */
error NotClaimer(address caller);
