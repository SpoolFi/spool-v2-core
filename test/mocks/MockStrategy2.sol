// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/console.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/utils/math/Math.sol";
import "../../src/strategies/Strategy.sol";

contract MockStrategy2 is Strategy {
    using SafeERC20 for IERC20;

    MockProtocol2 public immutable protocol;

    uint256 _lastSharePrice;

    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, uint256 assetGroupId_)
        Strategy(assetGroupRegistry_, accessControl_, assetGroupId_)
    {
        address[] memory tokens = assetGroupRegistry_.listAssetGroup(assetGroupId_);

        protocol = new MockProtocol2(tokens[0]);
    }

    function initialize(string memory strategyName_) external initializer {
        __Strategy_init(strategyName_, NULL_ASSET_GROUP_ID);

        _lastSharePrice = protocol.sharePrice();
    }

    function assetRatio() external pure override returns (uint256[] memory ratio) {
        ratio = new uint256[](1);
        ratio[0] = 1;
    }

    function beforeDepositCheck(uint256[] memory, uint256[] calldata) public pure override {}

    function beforeRedeemalCheck(uint256, uint256[] calldata) public pure override {}

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata)
        internal
        override
    {
        _depositInner(IERC20(tokens[0]), amounts[0]);
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata) internal override {
        _withdrawInner(ssts);
    }

    function _emergencyWithdrawImpl(uint256[] calldata, address recipient) internal override {
        uint256 assetsWithdrawn = _withdrawInner(totalSupply());

        address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId());

        IERC20(tokens[0]).safeTransfer(recipient, assetsWithdrawn);
    }

    function _compound(address[] calldata tokens, SwapInfo[] calldata, uint256[] calldata)
        internal
        override
        returns (int256 compoundYield)
    {
        uint256 rewards = protocol.claimRewards();

        if (rewards > 0) {
            uint256 sharesBefore = protocol.shares(address(this));

            uint256 sharesMinted = _depositInner(IERC20(tokens[0]), rewards);

            compoundYield = int256(YIELD_FULL_PERCENT * sharesMinted / sharesBefore);
        }
    }

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        uint256 currentSharePrice = protocol.sharePrice();

        baseYieldPercentage = _calculateYieldPercentage(_lastSharePrice, currentSharePrice);

        _lastSharePrice = currentSharePrice;
    }

    function _swapAssets(address[] memory, uint256[] memory, SwapInfo[] calldata) internal pure override {}

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256 usdWorth)
    {
        uint256 protocolShares = protocol.shares(address(this));

        if (protocolShares > 0) {
            uint256 assetWorth = protocol.totalUnderlying() * protocol.shares(address(this)) / protocol.totalShares();
            address[] memory tokens = _assetGroupRegistry.listAssetGroup(assetGroupId());

            usdWorth = priceFeedManager.assetToUsdCustomPrice(tokens[0], assetWorth, exchangeRates[0]);
        }
    }

    function _depositInner(IERC20 token, uint256 amount) private returns (uint256) {
        _resetAndApprove(token, address(protocol), amount);

        return (protocol.invest(amount));
    }

    function _withdrawInner(uint256 ssts) private returns (uint256) {
        uint256 protocolShares = protocol.shares(address(this)) * ssts / totalSupply();

        return (protocol.divest(protocolShares));
    }
}

contract MockProtocol2 {
    using SafeERC20 for IERC20;

    uint256 constant PROTOCOL_INITIAL_SHARE_MULTIPLIER = 10_000;
    uint256 constant PRICE_MULTIPLIER = 10 ** 18;

    address immutable underlying;

    uint256 public totalUnderlying;
    uint256 public totalShares;
    mapping(address => uint256) public shares;
    mapping(address => uint256) public rewards;

    constructor(address underlying_) {
        underlying = underlying_;
    }

    function invest(uint256 amountUnderlying) external returns (uint256 amountShares) {
        if (totalShares == 0) {
            amountShares = PROTOCOL_INITIAL_SHARE_MULTIPLIER * amountUnderlying;
        } else {
            amountShares = totalShares * amountUnderlying / totalUnderlying;
        }

        totalUnderlying += amountUnderlying;
        totalShares += amountShares;
        shares[msg.sender] += amountShares;

        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amountUnderlying);
    }

    function divest(uint256 amountShares) external returns (uint256 amountUnderlying) {
        amountUnderlying = totalUnderlying * amountShares / totalShares;

        totalUnderlying -= amountUnderlying;
        totalShares -= amountShares;
        shares[msg.sender] -= amountShares;

        IERC20(underlying).safeTransfer(msg.sender, amountUnderlying);
    }

    function donate(uint256 amountUnderlying) external {
        totalUnderlying += amountUnderlying;

        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amountUnderlying);
    }

    function reward(uint256 amountUnderlying, address user) external {
        rewards[user] += amountUnderlying;

        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amountUnderlying);
    }

    function claimRewards() external returns (uint256 amountUnderlying) {
        amountUnderlying = rewards[msg.sender];

        rewards[msg.sender] = 0;

        IERC20(underlying).safeTransfer(msg.sender, amountUnderlying);
    }

    function sharePrice() external view returns (uint256 price) {
        if (totalShares == 0) {
            price = PRICE_MULTIPLIER / PROTOCOL_INITIAL_SHARE_MULTIPLIER;
        } else {
            price = PRICE_MULTIPLIER * totalUnderlying / totalShares;
        }
    }
}
