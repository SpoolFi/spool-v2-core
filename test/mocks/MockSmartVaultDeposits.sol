// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "../../src/libraries/SmartVaultManagerLib.sol";
import "../../src/interfaces/ISmartVaultManager.sol";

contract MockSmartVaultDeposits {
    constructor() {}

    function distributeVaultDeposits(
        DepositRatioQueryBag memory bag,
        uint256[] memory depositsIn,
        SwapInfo[] calldata swapInfo
    ) external returns (uint256[][] memory) {
        return SmartVaultDeposits.distributeVaultDeposits(bag, depositsIn, swapInfo);
    }
}
