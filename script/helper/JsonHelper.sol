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
        string memory proxyJson = key;
        proxyJson.serialize("implementation", implementation);
        proxyJson = proxyJson.serialize("proxy", proxy);

        string memory content = json.serialize(key, proxyJson);

        content.write(path);
    }

    function addVariantStrategyImplementation(string memory strategyKey, address implementation) public {
        string memory variantStrategyJson = strategyKey;
        variantStrategyJson = variantStrategyJson.serialize("implementation", implementation);

        string memory strategiesJson = "strategies";
        strategiesJson = strategiesJson.serialize(strategyKey, variantStrategyJson);

        string memory content = json.serialize("strategies", strategiesJson);
        content.write(path);
    }

    function addVariantStrategyVariant(string memory strategyKey, string memory variantName, address variantAddress)
        public
    {
        string memory variantStrategyJson = strategyKey;
        variantStrategyJson = variantStrategyJson.serialize(variantName, variantAddress);

        string memory strategiesJson = "strategies";
        strategiesJson = strategiesJson.serialize(strategyKey, variantStrategyJson);

        string memory content = json.serialize("strategies", strategiesJson);
        content.write(path);
    }

    function test_mock() external pure {}
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

    function getInt256(string memory key) public view returns (int256) {
        return json.readInt(key);
    }

    function test_mock() external pure {}
}
