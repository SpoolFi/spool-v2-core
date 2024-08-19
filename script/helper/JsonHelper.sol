// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "forge-std/StdJson.sol";
import "forge-std/Vm.sol";

contract JsonWriter {
    using stdJson for string;

    VmSafe vmWriter;
    string jsonWriter = "JSON_ROOT";
    string path;

    constructor(VmSafe _vmWriter, string memory _path) {
        string memory content = _vmWriter.readFile(_path);
        if (bytes(content).length > 0) jsonWriter.serialize(content);
        vmWriter = _vmWriter;
        path = _path;
    }

    function add(string memory key, address value) public {
        string memory content = jsonWriter.serialize(key, value);
        content.write(path);
    }

    function add(string memory key, string memory value) public {
        string memory content = jsonWriter.serialize(key, value);
        content.write(path);
    }

    function add(string memory key, uint256 value) public {
        string memory content = jsonWriter.serialize(key, value);
        content.write(path);
    }

    function addProxy(string memory key, address implementation, address proxy) public {
        string memory proxyJson = key;
        proxyJson.serialize("implementation", implementation);
        proxyJson = proxyJson.serialize("proxy", proxy);

        string memory content = jsonWriter.serialize(key, proxyJson);

        content.write(path);
    }

    function addProxyStrategy(string memory strategyKey, address implementation, address proxy) public {
        string memory strategyJson = strategyKey;
        strategyJson.serialize("implementation", implementation);
        strategyJson = strategyJson.serialize("proxy", proxy);

        string memory strategiesJson = "strategies";
        strategiesJson = strategiesJson.serialize(strategyKey, strategyJson);

        string memory content = jsonWriter.serialize("strategies", strategiesJson);
        content.write(path);
    }

    function addVariantStrategyImplementation(string memory strategyKey, address implementation) public {
        string memory variantStrategyJson = strategyKey;
        variantStrategyJson = variantStrategyJson.serialize("implementation", implementation);

        string memory strategiesJson = "strategies";
        strategiesJson = strategiesJson.serialize(strategyKey, variantStrategyJson);

        string memory content = jsonWriter.serialize("strategies", strategiesJson);
        content.write(path);
    }

    function addVariantStrategyHelpersImplementation(string memory strategyHelpersKey, address implementation) public {
        string memory variantStrategyHelperJson = strategyHelpersKey;
        variantStrategyHelperJson = variantStrategyHelperJson.serialize("implementation", implementation);

        string memory strategyHelpersJson = "strategy-helpers";
        strategyHelpersJson = strategyHelpersJson.serialize(strategyHelpersKey, variantStrategyHelperJson);

        string memory content = jsonWriter.serialize("strategy-helpers", strategyHelpersJson);
        content.write(path);
    }

    function addVariantStrategyVariant(string memory strategyKey, string memory variantName, address variantAddress)
        public
    {
        string memory variantStrategyJson = strategyKey;
        variantStrategyJson = variantStrategyJson.serialize(variantName, variantAddress);

        string memory strategiesJson = "strategies";
        strategiesJson = strategiesJson.serialize(strategyKey, variantStrategyJson);

        string memory content = jsonWriter.serialize("strategies", strategiesJson);
        content.write(path);
    }

    function addVariantStrategyHelpersVariant(
        string memory strategyHelpersKey,
        string memory variantName,
        address variantAddress
    ) public {
        string memory variantStrategyHelperJson = strategyHelpersKey;
        variantStrategyHelperJson = variantStrategyHelperJson.serialize(variantName, variantAddress);

        string memory strategyHelpersJson = "strategy-helpers";
        strategyHelpersJson = strategyHelpersJson.serialize(strategyHelpersKey, variantStrategyHelperJson);

        string memory content = jsonWriter.serialize("strategy-helpers", strategyHelpersJson);
        content.write(path);
    }

    // needed to be able to append to inner keys in the json file in later updates.
    function reserializeKeyAddress(string memory rootKey) public {
        string memory json = vmWriter.readFile(path);

        string[] memory keys = vmWriter.parseJsonKeys(json, string.concat(".", rootKey));

        string memory rootKeyJson = rootKey;
        string memory contentSubKey;
        string memory contentRootKey;

        for (uint256 i = 0; i < keys.length; i++) {
            string memory key = keys[i];
            string[] memory subKeys = vmWriter.parseJsonKeys(json, string.concat(".", rootKey, ".", key));
            for (uint256 j = 0; j < subKeys.length; j++) {
                contentSubKey =
                    key.serialize(subKeys[j], json.readAddress(string.concat(".", rootKey, ".", key, ".", subKeys[j])));
            }
            contentRootKey = rootKeyJson.serialize(key, contentSubKey);
        }
        jsonWriter.serialize(rootKey, contentRootKey);
    }

    function test_JsonWriter_mock() external pure {}
}

contract JsonReader {
    using stdJson for string;

    VmSafe vmReader;
    string public jsonReader;

    constructor(VmSafe _vmReader, string memory path) {
        jsonReader = _vmReader.readFile(path);
        vmReader = _vmReader;
    }

    function getAddress(string memory key) public view returns (address) {
        return jsonReader.readAddress(key);
    }

    function getBool(string memory key) public view returns (bool) {
        return jsonReader.readBool(key);
    }

    function getUint256(string memory key) public view returns (uint256) {
        return jsonReader.readUint(key);
    }

    function getInt256(string memory key) public view returns (int256) {
        return jsonReader.readInt(key);
    }

    function getUint256Array(string memory key) public view returns (uint256[] memory) {
        return jsonReader.readUintArray(key);
    }

    function getAddressArray(string memory key) public view returns (address[] memory) {
        return jsonReader.readAddressArray(key);
    }

    function getString(string memory key) public view returns (string memory) {
        return jsonReader.readString(key);
    }

    function hasKey(string memory key) public view returns (bool) {
        return vmReader.keyExists(jsonReader, key);
    }

    function test_JsonReader_mock() external pure {}
}

contract JsonReadWriter is JsonReader, JsonWriter {
    constructor(VmSafe vm, string memory path) JsonReader(vm, path) JsonWriter(vm, path) {}
}
