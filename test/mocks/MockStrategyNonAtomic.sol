// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../src/interfaces/Constants.sol";
import "../../src/strategies/StrategyNonAtomic.sol";

contract MockStrategyNonAtomic is StrategyNonAtomic {
    using SafeERC20 for IERC20;

    MockProtocolNonAtomic public immutable protocol;

    uint256 public _lastSharePrice;

    constructor(
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_,
        uint256 assetGroupId_,
        uint256 atomicityClassification_,
        uint256 feePct,
        bool deductShares
    ) StrategyNonAtomic(assetGroupRegistry_, accessControl_, assetGroupId_) {
        address[] memory tokens = assetGroupRegistry_.listAssetGroup(assetGroupId_);
        require(tokens.length == 1, "MockStrategyNonAtomic: invalid asset group");

        protocol = new MockProtocolNonAtomic(tokens[0], atomicityClassification_, feePct, deductShares);
    }

    function initialize(string memory strategyName_) external initializer {
        __Strategy_init(strategyName_, NULL_ASSET_GROUP_ID);

        _lastSharePrice = protocol.sharePrice();
    }

    function withdrawalFeeShares() external view returns (uint256) {
        return _withdrawalFeeShares;
    }

    function legacyFeeShares() external view returns (uint256) {
        return _legacyFeeShares;
    }

    function userDepositShares() external view returns (uint256) {
        return balanceOf(address(this)) - _withdrawalFeeShares - _legacyFeeShares;
    }

    function assetRatio() external pure override returns (uint256[] memory ratio) {
        ratio = new uint256[](1);
        ratio[0] = 1;
    }

    function getUnderlyingAssetAmounts() external view returns (uint256[] memory amounts) {
        amounts = new uint[](1);
        amounts[0] = protocol.totalUnderlying() * protocol.shares(address(this)) / protocol.totalShares();
    }

    function beforeDepositCheck(uint256[] memory, uint256[] calldata) public pure override {}

    function beforeRedeemalCheck(uint256, uint256[] calldata) public pure override {}

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

    function _getYieldPercentage(int256) internal override returns (int256 baseYieldPercentage) {
        uint256 currentSharePrice = protocol.sharePrice();

        baseYieldPercentage = _calculateYieldPercentage(_lastSharePrice, currentSharePrice);

        _lastSharePrice = currentSharePrice;
    }

    function _initializeDepositToProtocol(address[] calldata tokens, uint256[] memory assets, uint256[] calldata)
        internal
        override
        returns (bool finished)
    {
        _resetAndApprove(IERC20(tokens[0]), address(protocol), assets[0]);

        uint256 amountShares;
        (amountShares, finished) = protocol.invest(assets[0]);
    }

    function _initializeWithdrawalFromProtocol(address[] calldata, uint256 shares, uint256[] calldata)
        internal
        override
        returns (bool finished, bool sharesDeducted)
    {
        sharesDeducted = protocol.deductShares();

        uint256 protocolShares = protocol.shares(address(this)) * shares / totalSupply();

        uint256 amountUnderlying;
        (amountUnderlying, finished) = protocol.divest(protocolShares);
    }

    function _continueDepositToProtocol(address[] calldata, bytes calldata)
        internal
        override
        returns (bool finished, uint256 valueBefore, uint256 valueAfter)
    {
        valueBefore = protocol.shares(address(this));

        protocol.claimInvestment();

        valueAfter = protocol.shares(address(this));
        finished = true;
    }

    function _continueWithdrawalFromProtocol(address[] calldata, bytes calldata)
        internal
        override
        returns (bool finished)
    {
        protocol.claimDivestment();

        finished = true;
    }

    function _prepareCompoundImpl(address[] calldata, SwapInfo[] calldata)
        internal
        override
        returns (bool compoundNeeded, uint256[] memory assetsToCompound)
    {
        assetsToCompound = new uint256[](1);
        uint256 rewards = protocol.claimRewards();

        if (rewards > 0) {
            compoundNeeded = true;
            assetsToCompound[0] = rewards;
        }
    }

    function _swapAssets(address[] memory, uint256[] memory, SwapInfo[] calldata) internal override {}

    function _getProtocolRewardsInternal()
        internal
        view
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        tokens = new address[](1);
        amounts = new uint256[](1);

        tokens[0] = protocol.underlying();
        amounts[0] = protocol.rewards(address(this));
    }

    function _emergencyWithdrawImpl(uint256[] calldata, address recipient) internal override {
        (uint256 amountUnderlying, bool finished) = protocol.divest(protocol.shares(address(this)));
        if (!finished) {
            revert("MockStrategyNonAtomic: emergency withdraw not finished");
        }

        IERC20(protocol.underlying()).safeTransfer(recipient, amountUnderlying);
    }
}

contract MockProtocolNonAtomic {
    using SafeERC20 for IERC20;

    uint256 public constant PROTOCOL_INITIAL_SHARE_MULTIPLIER = 10_000;
    uint256 public constant PRICE_MULTIPLIER = 10 ** 18;

    address public immutable underlying;
    uint256 public immutable atomicityClassification;
    uint256 public immutable feePct;
    bool public immutable deductShares;

    uint256 public totalUnderlying;
    uint256 public totalShares;
    uint256 public fees;
    mapping(address => uint256) public shares;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public pendingInvestments;
    mapping(address => uint256) public pendingDivestments;

    constructor(address underlying_, uint256 atomicityClassification_, uint256 feePct_, bool deductShares_) {
        underlying = underlying_;
        atomicityClassification = atomicityClassification_;
        feePct = feePct_;
        deductShares = deductShares_;
    }

    // public

    function invest(uint256 amountUnderlying) external returns (uint256 amountShares, bool finished) {
        require(pendingInvestments[msg.sender] == 0, "MockProtocolNonAtomic: pending investment");

        if (atomicityClassification & NON_ATOMIC_DEPOSIT_STRATEGY > 0) {
            _investNonAtomic(amountUnderlying);
        } else {
            amountShares = _investAtomic(amountUnderlying);
            finished = true;
        }

        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amountUnderlying);
    }

    function divest(uint256 amountShares) external returns (uint256 amountUnderlying, bool finished) {
        require(pendingDivestments[msg.sender] == 0, "MockProtocolNonAtomic: pending divestment");

        if (atomicityClassification & NON_ATOMIC_WITHDRAWAL_STRATEGY > 0) {
            _divestNonAtomic(amountShares);
        } else {
            amountUnderlying = _divestAtomic(amountShares);
            finished = true;
        }
    }

    function claimInvestment() external returns (uint256 amountShares) {
        require(pendingInvestments[msg.sender] > 0, "MockProtocolNonAtomic: no pending investment");

        amountShares = _investInternal(pendingInvestments[msg.sender], msg.sender);

        pendingInvestments[msg.sender] = 0;
    }

    function claimDivestment() external returns (uint256 amountUnderlying) {
        require(pendingDivestments[msg.sender] > 0, "MockProtocolNonAtomic: no pending divestment");

        amountUnderlying = _divestInternal(pendingDivestments[msg.sender], msg.sender);

        if (!deductShares) {
            shares[msg.sender] -= pendingDivestments[msg.sender];
        }

        pendingDivestments[msg.sender] = 0;
    }

    function donate(uint256 amountUnderlying) external {
        totalUnderlying += amountUnderlying;

        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amountUnderlying);
    }

    function take(uint256 amountUnderlying) external {
        require(totalUnderlying >= amountUnderlying, "MockProtocolNonAtomic: insufficient underlying");

        totalUnderlying -= amountUnderlying;

        IERC20(underlying).safeTransfer(msg.sender, amountUnderlying);
    }

    function reward(uint256 amountUnderlying, address user) external {
        rewards[user] += amountUnderlying;

        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amountUnderlying);
    }

    function claimRewards() external returns (uint256 amountUnderlying) {
        amountUnderlying = rewards[msg.sender];

        if (amountUnderlying > 0) {
            rewards[msg.sender] = 0;
            IERC20(underlying).safeTransfer(msg.sender, amountUnderlying);
        }
    }

    function sharePrice() external view returns (uint256 price) {
        if (totalShares == 0) {
            price = PRICE_MULTIPLIER / PROTOCOL_INITIAL_SHARE_MULTIPLIER;
        } else {
            price = PRICE_MULTIPLIER * totalUnderlying / totalShares;
        }
    }

    function test_mock() external pure {}

    // private

    function _investAtomic(uint256 amountUnderlying) private returns (uint256 amountShares) {
        amountShares = _investInternal(amountUnderlying, msg.sender);
    }

    function _investNonAtomic(uint256 amountUnderlying) private {
        pendingInvestments[msg.sender] = amountUnderlying;
    }

    function _investInternal(uint256 amountUnderlying, address beneficiary) private returns (uint256 amountShares) {
        uint256 feeAmount = amountUnderlying * feePct / FULL_PERCENT;
        uint256 investmentAmount = amountUnderlying - feeAmount;

        if (totalShares == 0) {
            amountShares = PROTOCOL_INITIAL_SHARE_MULTIPLIER * investmentAmount;
        } else {
            amountShares = totalShares * investmentAmount / totalUnderlying;
        }

        totalUnderlying += investmentAmount;
        fees += feeAmount;
        totalShares += amountShares;
        shares[beneficiary] += amountShares;
    }

    function _divestAtomic(uint256 amountShares) private returns (uint256 amountUnderlying) {
        amountUnderlying = _divestInternal(amountShares, msg.sender);
        shares[msg.sender] -= amountShares;
    }

    function _divestNonAtomic(uint256 amountShares) private {
        pendingDivestments[msg.sender] = amountShares;

        if (deductShares) {
            shares[msg.sender] -= amountShares;
        }
    }

    function _divestInternal(uint256 amountShares, address beneficiary) private returns (uint256 divestmentAmount) {
        uint256 amountUnderlying = totalUnderlying * amountShares / totalShares;

        uint256 feeAmount = amountUnderlying * feePct / FULL_PERCENT;
        divestmentAmount = amountUnderlying - feeAmount;

        totalUnderlying -= amountUnderlying;
        fees += feeAmount;
        totalShares -= amountShares;

        IERC20(underlying).safeTransfer(beneficiary, divestmentAmount);
    }
}
