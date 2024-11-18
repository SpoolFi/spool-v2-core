// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

library StringUtils {
    function contains(string memory where, string memory what) external pure returns (bool found) {
        bytes memory whereBytes = bytes(where);
        bytes memory whatBytes = bytes(what);

        if (whereBytes.length < whatBytes.length) return false;

        for (uint256 i = 0; i <= whereBytes.length - whatBytes.length; i++) {
            bool flag = true;
            for (uint256 j = 0; j < whatBytes.length; j++) {
                if (whereBytes[i + j] != whatBytes[j]) {
                    flag = false;
                    break;
                }
            }
            if (flag) {
                found = true;
                break;
            }
        }
    }
}
