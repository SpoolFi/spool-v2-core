// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IVaultCore {
    function allocate() external;
    function assetDefaultStrategies(address) external view returns (address);
    function autoAllocateThreshold() external view returns (uint256);
    function burnForStrategy(uint256 _amount) external;
    function calculateRedeemOutputs(uint256 _amount) external view returns (uint256[] memory);
    function capitalPaused() external view returns (bool);
    function checkBalance(address _asset) external view returns (uint256);
    function claimGovernance() external;
    function getAllAssets() external view returns (address[] memory);
    function getAllStrategies() external view returns (address[] memory);
    function getAssetCount() external view returns (uint256);
    function getStrategyCount() external view returns (uint256);
    function governor() external view returns (address);
    function isGovernor() external view returns (bool);
    function isSupportedAsset(address _asset) external view returns (bool);
    function maxSupplyDiff() external view returns (uint256);
    function mint(address _asset, uint256 _amount, uint256 _minimumOusdAmount) external;
    function mintForStrategy(uint256 _amount) external;
    function netOusdMintForStrategyThreshold() external view returns (uint256);
    function netOusdMintedForStrategy() external view returns (int256);
    function ousdMetaStrategy() external view returns (address);
    function priceProvider() external view returns (address);
    function priceUnitMint(address asset) external view returns (uint256 price);
    function priceUnitRedeem(address asset) external view returns (uint256 price);
    function rebase() external;
    function rebasePaused() external view returns (bool);
    function rebaseThreshold() external view returns (uint256);
    function redeem(uint256 _amount, uint256 _minimumUnitAmount) external;
    function redeemAll(uint256 _minimumUnitAmount) external;
    function redeemFeeBps() external view returns (uint256);
    function setAdminImpl(address newImpl) external;
    function strategistAddr() external view returns (address);
    function totalValue() external view returns (uint256 value);
    function transferGovernance(address _newGovernor) external;
    function trusteeAddress() external view returns (address);
    function trusteeFeeBps() external view returns (uint256);
    function vaultBuffer() external view returns (uint256);
}
