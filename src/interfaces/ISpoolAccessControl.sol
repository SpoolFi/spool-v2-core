// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "@openzeppelin-upgradeable/access/IAccessControlUpgradeable.sol";

error MissingRole(bytes32 role, address account);

interface ISpoolAccessControl is IAccessControlUpgradeable {
    function hasSmartVaultRole(address smartVault, bytes32 role, address account) external view returns (bool);

    function grantSmartVaultRole(address smartVault, bytes32 role, address account) external;

    function revokeSmartVaultRole(address smartVault, bytes32 role, address account) external;

    function renounceSmartVaultRole(address smartVault, bytes32 role) external;

    function checkIsAdminOrVaultAdmin(address smartVault, address account) external;
}
