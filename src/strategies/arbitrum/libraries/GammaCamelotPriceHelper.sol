// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "../../../external/interfaces/strategies/arbitrum/gamma-camelot/IUniProxy.sol";
import "../../../external/interfaces/strategies/arbitrum/gamma-camelot/IClearingV2.sol";

library GammaCamelotPriceHelper {
    function getPrice(IUniProxy gammaUniProxy, address pool) external view returns (uint256 price) {
        IClearingV2 clearance = IClearingV2(gammaUniProxy.clearance());
        IClearingV2.Position memory p = clearance.positions(pool);

        price = clearance.checkPriceChange(
            pool,
            (p.twapOverride ? p.twapInterval : clearance.twapInterval()),
            (p.twapOverride ? p.priceThreshold : clearance.priceThreshold())
        );
    }
}
