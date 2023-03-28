// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "forge-std/StdJson.sol";
import "forge-std/Vm.sol";

contract JsonWriter {
    using stdJson for string;

    string json = "JSON_ROOT";
    string path;

    constructor(string memory _path) {
        path = _path;
    }

    function add(string memory key, address value) public {
        string memory content = json.serialize(key, value);
        content.write(path);
    }

    function add(string memory key, string memory value) public {
        string memory content = json.serialize(key, value);
        content.write(path);
    }

    function add(string memory key, uint256 value) public {
        string memory content = json.serialize(key, value);
        content.write(path);
    }

    function addProxy(string memory key, address implementation, address proxy) public {
        string memory proxyJson;
        proxyJson.serialize("implementation", implementation);
        proxyJson = proxyJson.serialize("proxy", proxy);

        string memory content = json.serialize(key, proxyJson);

        content.write(path);
    }
}

contract JsonReader {
    using stdJson for string;

    string json;

    constructor(VmSafe vm, string memory path) {
        json = vm.readFile(path);
    }

    function getAddress(string memory key) public view returns (address) {
        return json.readAddress(key);
    }

    function getUint256(string memory key) public view returns (uint256) {
        return json.readUint(key);
    }
}
