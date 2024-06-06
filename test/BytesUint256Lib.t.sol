// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../src/libraries/BytesUint256Lib.sol";

contract BytesUint256LibTest is Test {
    /// @dev runs set too low in order to pass CI quicker. Can be adjusted locally
    /// forge-config: default.fuzz.runs = 100
    function testFuzz_encodeDecode(bytes memory data) public {
        uint256[] memory result = BytesUint256Lib.encode(data);
        bytes memory check = BytesUint256Lib.decode(result, data.length);
        assertEq0(data, check);
    }

    function test_encode() public {
        {
            bytes memory data = hex"983542f4286c19bfe8a6";
            uint256[] memory result = BytesUint256Lib.encode(data);
            assertEq(result.length, 1);
            assertEq(bytes32(result[0]), 0x983542f4286c19bfe8a600000000000000000000000000000000000000000000);
        }
        {
            bytes memory data =
                hex"d9500b057627638933c6e05a1b3707ebaa3c4e51dd79ee9cfa7a5d5b76cf69022f8e97a6e5b8176af3e8f1";
            uint256[] memory result = BytesUint256Lib.encode(data);
            assertEq(result.length, 2);
            // initial bytes are correctly split
            // d9500b057627638933c6e05a1b3707ebaa3c4e51dd79ee9cfa7a5d5b76cf6902___2f8e97a6e5b8176af3e8f1
            assertEq(bytes32(result[0]), 0xd9500b057627638933c6e05a1b3707ebaa3c4e51dd79ee9cfa7a5d5b76cf6902);
            assertEq(bytes32(result[1]), 0x2f8e97a6e5b8176af3e8f1000000000000000000000000000000000000000000);
        }
    }

    function test_encodeDecodePredefinedData() public {
        bytes[] memory cases = new bytes[](5);
        cases[0] = hex"983542f4286c19bfe8a6";
        cases[1] = hex"599a1767080d8ecff7f51a668d1632e82e25baa01d089be3f51c3cc184ed9106";
        cases[2] = hex"d9500b057627638933c6e05a1b3707ebaa3c4e51dd79ee9cfa7a5d5b76cf69022f8e97a6e5b8176af3e8f1";
        cases[3] =
            hex"964c7369ecde7e5ab374cb5ca6716c725627c7873fdb57a252d3cf8a74276fb36db6b238934fe09ea6df7900595f3106f4c56d08e01787e757a5aae734ea8b0b";
        cases[4] =
            hex"5b44a7619e9814b52fb6b98b091170f12e5092121ca253532880c5731c558ca44ff9ed815d23d8889dfb75d1f6d91b96ca007808f73571a34fe05f44330fdbba9fbb8f4cb3229e";
        for (uint256 i; i < cases.length; i++) {
            bytes memory data = cases[i];
            uint256[] memory result = BytesUint256Lib.encode(data);
            bytes memory check = BytesUint256Lib.decode(result, data.length);
            assertEq0(data, check);
        }
    }
}
