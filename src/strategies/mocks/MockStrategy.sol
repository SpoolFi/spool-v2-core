// Mock strategy for testnet. WILL NOT BE USED IN PRODUCTION.
// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../Strategy.sol";

interface IERC20Mintable is IERC20 {
    function mint(address, uint256) external;
}

struct UserInfo {
    uint256 amount;
    uint256 rewardDebt;
}

struct PoolInfo {
    IERC20 token;
    uint256 vestedSupply;
    uint256 lastRewardTime;
    uint256 accRewardPerShare;
}

contract MockStrategy is Strategy {
    using SafeERC20 for IERC20;

    uint256 public rewardTokenPerSecond;
    uint256 public startTime;
    PoolInfo public poolInfo;
    mapping(address => UserInfo) public userInfo;

    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_)
        Strategy(assetGroupRegistry_, accessControl_, NULL_ASSET_GROUP_ID)
    {}

    function initialize(string memory strategyName_, uint256 assetGroupId_, uint256 _rewardTokenPerSecond)
        external
        initializer
    {
        __Strategy_init(strategyName_, assetGroupId_);

        rewardTokenPerSecond = _rewardTokenPerSecond;
        startTime = block.timestamp;

        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupId_);
        poolInfo = PoolInfo({
            token: IERC20(assetGroup[0]),
            vestedSupply: 0,
            lastRewardTime: block.timestamp,
            accRewardPerShare: 0
        });
    }

    function assetRatio() external pure override returns (uint256[] memory) {
        uint256[] memory _assetRatio = new uint256[](1);
        _assetRatio[0] = 1;
        return _assetRatio;
    }

    function getUnderlyingAssetAmounts() external view returns (uint256[] memory amounts) {
        uint256 balance = userInfo[address(this)].amount;

        amounts = new uint[](1);
        amounts[0] = balance;
    }

    function _swapAssets(address[] memory, uint256[] memory, SwapInfo[] calldata) internal override {}

    function _compound(address[] calldata, SwapInfo[] calldata, uint256[] calldata)
        internal
        override
        returns (int256 compoundYield)
    {
        // claims rewards
        (, uint256[] memory rewards) = _getProtocolRewardsInternal();

        // NOTE: as reward token is same as the deposit token, deposit the claimed amount
        uint256 balanceBefore = userInfo[address(this)].amount;

        deposit(rewards[0]);

        if (balanceBefore > 0) {
            compoundYield = int256(rewards[0] * YIELD_FULL_PERCENT / balanceBefore);
        }
    }

    function _getYieldPercentage(int256) internal pure override returns (int256) {
        return 0;
    }

    function _depositToProtocol(address[] calldata, uint256[] memory amounts, uint256[] calldata) internal override {
        if (amounts[0] > 0) {
            deposit(amounts[0]);
        }
    }

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256)
    {
        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupId());
        uint256 balance = userInfo[address(this)].amount;

        uint256 usdWorth = priceFeedManager.assetToUsdCustomPrice(assetGroup[0], balance, exchangeRates[0]);

        return usdWorth;
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata) internal override {
        if (ssts == 0) {
            return;
        }

        uint256 balance = userInfo[address(this)].amount;

        uint256 toWithdraw = balance * ssts / totalSupply();

        withdraw(toWithdraw);
    }

    function _getAssetBalance() private view returns (uint256) {
        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupId());

        return IERC20(assetGroup[0]).balanceOf(address(this));
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public view override {}

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public view override {}

    function _emergencyWithdrawImpl(uint256[] calldata, address recipient) internal override {
        uint256 balance = userInfo[address(this)].amount;

        withdraw(balance);

        IERC20(poolInfo.token).safeTransfer(recipient, balance);
    }

    function _getProtocolRewardsInternal()
        internal
        virtual
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        uint256 assetBalanceBefore = _getAssetBalance();

        // claims rewards
        deposit(0);
        // rewards generated
        uint256 assetBalanceDiff = _getAssetBalance() - assetBalanceBefore;

        tokens = new address[](1);
        tokens[0] = address(poolInfo.token);

        amounts = new uint256[](1);
        amounts[0] = assetBalanceDiff;
    }

    function updateRewardTokenPerSecond(uint256 _rewardTokenPerSecond)
        external
        onlyRole(ROLE_SPOOL_ADMIN, msg.sender)
    {
        rewardTokenPerSecond = _rewardTokenPerSecond;
    }

    function updatePool() public {
        PoolInfo storage pool = poolInfo;
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 vestedSupply = pool.vestedSupply;
        if (vestedSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = block.timestamp - pool.lastRewardTime;
        uint256 reward = multiplier * rewardTokenPerSecond;

        pool.accRewardPerShare += reward * 1e12 / vestedSupply;
        pool.lastRewardTime = block.timestamp;
    }

    function deposit(uint256 _amount) private {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[address(this)];
        updatePool();
        if (user.amount > 0) {
            uint256 pending = user.amount * pool.accRewardPerShare / 1e12 - user.rewardDebt;
            safeRewardMint(pending);
        }
        user.amount += _amount;
        user.rewardDebt = user.amount * pool.accRewardPerShare / 1e12;
        pool.vestedSupply += _amount;
    }

    function withdraw(uint256 _amount) private {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[address(this)];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool();
        uint256 pending = user.amount * pool.accRewardPerShare / 1e12 - user.rewardDebt;
        safeRewardMint(pending);
        user.amount -= _amount;
        pool.vestedSupply -= _amount;
        user.rewardDebt = user.amount * pool.accRewardPerShare / 1e12;
    }

    function safeRewardMint(uint256 _amount) private {
        if (address(poolInfo.token) != _assetGroupRegistry.listAssetGroup(1)[0]) { // WETH
            IERC20Mintable(address(poolInfo.token)).mint(address(this), _amount);
        }
    }
}
