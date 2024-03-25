// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import "../../external/interfaces/strategies/arbitrum/gamma-camelot/IAlgebraPool.sol";
import "../../external/interfaces/strategies/arbitrum/gamma-camelot/IHypervisor.sol";
import "../../external/interfaces/strategies/arbitrum/gamma-camelot/INFTPool.sol";
import "../../external/interfaces/strategies/arbitrum/gamma-camelot/INitroPool.sol";
import "../../external/interfaces/strategies/arbitrum/gamma-camelot/IUniProxy.sol";
import "../../external/interfaces/strategies/arbitrum/gamma-camelot/IXGrail.sol";
import "../../interfaces/ISwapper.sol";
import "../../libraries/PackedRange.sol";
import "../../strategies/Strategy.sol";

error GammaCamelotDepositCheckFailed();
error GammaCamelotRedeemalCheckFailed();
error GammaCamelotDepositSlippagesFailed();
error GammaCamelotRedeemalSlippagesFailed();
error GammaCamelotCompoundSlippagesFailed();

// Two assets: WETH/USDC
// Three rewards: ARB, GRAIL, xGRAIL
// slippages:
//
// - mode selection: slippages[0]
//
// - DHW with deposit: slippages[0] == 0
//   - beforeDepositCheck: slippages[1..2]
//   - beforeRedeemalCheck: slippages[3]
//   - compound: slippages[4]
//   - _depositToProtocol: slippages[5]
//
// - DHW with withdrawal: slippages[0] == 1
//   - beforeDepositCheck: slippages[1..2]
//   - beforeRedeemalCheck: slippages[3]
//   - compound: slippages[4]
//   - _redeemFromProtocol: slippages[5..6]
//
// - reallocate: slippages[0] == 2
//   - beforeDepositCheck: depositSlippages[1..2]
//   - _depositToProtocol: depositSlippages[3]
//   - beforeRedeemalCheck: withdrawalSlippages[1]
//   - _redeemFromProtocol: withdrawalSlippages[2..3]
//
// - redeemFast or emergencyWithdraw: slippages[0] == 3
//   - _redeemFromProtocol: slippages[1..2]
//   - _emergencyWithdrawImpl: slippages[1..2]
contract GammaCamelotStrategy is Strategy, IERC721Receiver {
    using SafeERC20 for IERC20;

    ISwapper public immutable swapper;
    IUniProxy public gammaUniProxy;
    IHypervisor public pool;
    INFTPool public nftPool; // for $GRAIL rewards
    INitroPool public nitroPool; // for $ARB rewards
    IXGrail public xGRAIL; // governance token (for $GRAIL rewards)

    address[] public rewardTokens;

    // Pool data
    // ID of the position. set to uint256.max when
    // - no position is opened (initially)
    // - we fully remove value from the current NFT, so new one needs to be created.
    uint256 public nftId;

    constructor(IAssetGroupRegistry assetGroupRegistry_, ISpoolAccessControl accessControl_, ISwapper swapper_)
        Strategy(assetGroupRegistry_, accessControl_, NULL_ASSET_GROUP_ID)
    {
        if (address(swapper_) == address(0)) revert ConfigurationAddressZero();

        swapper = swapper_;
    }

    function initialize(string memory strategyName_, uint256 assetGroupId_, IHypervisor pool_, INitroPool nitroPool_)
        external
        initializer
    {
        __Strategy_init(strategyName_, assetGroupId_);

        // local variables
        address[] memory assetGroup = _assetGroupRegistry.listAssetGroup(assetGroupId_);

        IAlgebraPool underlyingPool = IAlgebraPool(pool_.pool());
        address token0 = underlyingPool.token0();
        address token1 = underlyingPool.token1();

        // checks
        if (assetGroup.length != 2 || !(assetGroup[0] == token0) || !(assetGroup[1] == token1)) {
            revert InvalidAssetGroup(assetGroupId());
        }

        // assign contracts
        gammaUniProxy = IUniProxy(pool_.whitelistedAddress());
        pool = pool_;
        nftPool = INFTPool(nitroPool_.nftPool());
        nitroPool = nitroPool_;

        // assign reward and governance tokens
        (, address rewardToken0, address _xGRAIL,,,,,) = nftPool.getPoolInfo();
        address rewardToken1 = nitroPool_.rewardsToken1();

        rewardTokens.push(rewardToken0); // GRAIL
        rewardTokens.push(rewardToken1); // ARB
        xGRAIL = IXGrail(_xGRAIL);

        nftId = type(uint256).max;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onNFTAddToPosition(address, uint256, uint256) external pure returns (bool) {
        return true;
    }

    function onNFTWithdraw(address, uint256, uint256) external pure returns (bool) {
        return true;
    }

    function onNFTHarvest(address, address, uint256, uint256, uint256) external pure returns (bool) {
        return true;
    }

    function assetRatio() external view override returns (uint256[] memory _assetRatio) {
        _assetRatio = new uint256[](2);
        (_assetRatio[0], _assetRatio[1]) = pool.getTotalAmounts();
    }

    function getUnderlyingAssetAmounts() external view returns (uint256[] memory amounts) {
        amounts = _getTokenWorth();
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public override {
        if (_isViewExecution()) {
            uint256[] memory beforeDepositCheckSlippageAmounts = new uint256[](2);
            beforeDepositCheckSlippageAmounts[0] = amounts[0];
            beforeDepositCheckSlippageAmounts[1] = amounts[1];

            emit BeforeDepositCheckSlippages(beforeDepositCheckSlippageAmounts);
            return;
        }

        if (slippages[0] > 2) {
            revert GammaCamelotDepositCheckFailed();
        }

        if (
            (!PackedRange.isWithinRange(slippages[1], amounts[0]))
                || (!PackedRange.isWithinRange(slippages[2], amounts[1]))
        ) {
            revert GammaCamelotDepositCheckFailed();
        }
    }

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public override {
        if (_isViewExecution()) {
            emit BeforeRedeemalCheckSlippages(ssts);
            return;
        }

        uint256 slippage;
        if (slippages[0] < 2) {
            slippage = slippages[3];
        } else if (slippages[0] == 2) {
            slippage = slippages[1];
        } else {
            revert GammaCamelotRedeemalCheckFailed();
        }

        if (!PackedRange.isWithinRange(slippage, ssts)) {
            revert GammaCamelotRedeemalCheckFailed();
        }
    }

    function getPoolBalance() public view returns (uint256) {
        return _getPoolBalance();
    }

    function _depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata slippages)
        internal
        override
    {
        uint256 slippageOffset;
        if (slippages[0] == 0) {
            slippageOffset = 5;
        } else if (slippages[0] == 2) {
            slippageOffset = 3;
        } else {
            revert GammaCamelotDepositSlippagesFailed();
        }

        uint256 shares = _depositToProtocolInternal(tokens, amounts, slippages[slippageOffset]);
        if (_isViewExecution()) {
            emit Slippages(true, shares, "");
        }
    }

    function _redeemFromProtocol(address[] calldata, uint256 ssts, uint256[] calldata slippages) internal override {
        uint256 slippageOffset;
        if (slippages[0] == 1) {
            slippageOffset = 5;
        } else if (slippages[0] == 2) {
            slippageOffset = 2;
        } else if (slippages[0] == 3) {
            slippageOffset = 1;
        } else if (slippages[0] == 0 && _isViewExecution()) {
            slippageOffset = 5;
        } else {
            revert GammaCamelotRedeemalSlippagesFailed();
        }

        uint256 tokenWithdrawAmount = (_getPoolBalance() * ssts) / totalSupply();
        _redeemFromProtocolInternal(tokenWithdrawAmount, slippages, slippageOffset);
    }

    function _emergencyWithdrawImpl(uint256[] calldata slippages, address recipient) internal override {
        uint256 slippageOffset;
        if (slippages[0] == 3) {
            slippageOffset = 1;
        } else {
            revert GammaCamelotRedeemalSlippagesFailed();
        }
        _redeemFromProtocolInternal(_getPoolBalance(), slippages, slippageOffset);

        uint256[] memory amounts = new uint256[](2);
        address[] memory tokens = assets();
        amounts[0] = IERC20(tokens[0]).balanceOf(address(this));
        amounts[1] = IERC20(tokens[1]).balanceOf(address(this));
        _transferToRecipient(tokens, amounts, recipient);
    }

    function _compound(address[] calldata tokens, SwapInfo[] calldata compoundSwapInfo, uint256[] calldata slippages)
        internal
        override
        returns (int256 compoundYield)
    {
        uint256 slippageOffset;
        if (slippages[0] < 2) {
            slippageOffset = 4;
        } else {
            revert GammaCamelotCompoundSlippagesFailed();
        }

        if (nftId == type(uint256).max || compoundSwapInfo.length == 0) {
            return compoundYield;
        }

        _getProtocolRewardsInternal();

        uint256[] memory swapped = swapper.swap(rewardTokens, compoundSwapInfo, tokens, address(this));

        uint256 sharesBefore = _getPoolBalance();
        uint256 shares = _depositToProtocolInternal(tokens, swapped, slippages[slippageOffset]);
        if (_isViewExecution()) {
            emit Slippages(true, shares, "");
        }

        compoundYield = int256(YIELD_FULL_PERCENT * (_getPoolBalance() - sharesBefore) / sharesBefore);
    }

    function _getYieldPercentage(int256) internal override returns (int256) {}

    function _swapAssets(address[] memory tokens, uint256[] memory amountsIn, SwapInfo[] calldata swapInfo)
        internal
        override
    {
        _transferToRecipient(tokens, amountsIn, address(swapper));
        swapper.swap(tokens, swapInfo, tokens, address(this));
    }

    function _getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        view
        override
        returns (uint256)
    {
        return priceFeedManager.assetToUsdCustomPriceBulk(assets(), _getTokenWorth(), exchangeRates);
    }

    function _depositToProtocolInternal(address[] memory tokens, uint256[] memory amounts, uint256 slippage)
        internal
        returns (uint256 shares)
    {
        if (amounts[0] == 0 && amounts[1] == 0) {
            return 0;
        }
        _resetAndApprove(IERC20(tokens[0]), address(pool), amounts[0]);
        _resetAndApprove(IERC20(tokens[1]), address(pool), amounts[1]);
        uint256[4] memory minAmounts;
        (shares) = gammaUniProxy.deposit(amounts[0], amounts[1], address(this), address(pool), minAmounts);

        if (shares < slippage) {
            revert GammaCamelotDepositSlippagesFailed();
        }

        _resetAndApprove(IERC20(address(pool)), address(nftPool), shares);
        // initial deposit
        if (nftId == type(uint256).max) {
            nftPool.createPosition(shares, 0);
            nftId = nftPool.lastTokenId();
            // onERC721Received executed on transfer, which gives allowance to this contract to use the NFT.
            nftPool.safeTransferFrom(address(this), address(nitroPool), nftId);
        } else {
            // subsequent deposits (don't need to withdraw from nitroPool. not the same for withdrawFromPosition)
            nftPool.addToPosition(nftId, shares);
        }
    }

    function _redeemFromProtocolInternal(uint256 shares, uint256[] calldata slippages, uint256 slippageOffset)
        internal
    {
        // must withdraw NFT from nitro pool to withdraw from position
        nitroPool.withdraw(nftId);
        nftPool.withdrawFromPosition(nftId, shares);
        uint256[] memory amounts = new uint256[](2);
        uint256[4] memory minAmounts;
        (amounts[0], amounts[1]) = pool.withdraw(shares, address(this), address(this), minAmounts);

        if (amounts[0] < slippages[slippageOffset] || amounts[1] < slippages[slippageOffset + 1]) {
            revert GammaCamelotRedeemalCheckFailed();
        }

        // NFT destroyed (ie. withdrew all shares from the position)
        if (!nftPool.exists(nftId)) {
            nftId = type(uint256).max;
        } else {
            // exists, send back to nitro pool for $ARB reward accumulation
            nftPool.safeTransferFrom(address(this), address(nitroPool), nftId);
        }

        if (_isViewExecution()) {
            emit Slippages(false, 0, abi.encode(amounts));
        }
    }

    function _getProtocolRewardsInternal() internal virtual override returns (address[] memory, uint256[] memory) {
        _getRewards();
        uint256[] memory balances = new uint256[](rewardTokens.length);

        unchecked {
            for (uint256 i; i < rewardTokens.length; ++i) {
                uint256 balance = IERC20(rewardTokens[i]).balanceOf(address(this));
                if (balance > 0) {
                    IERC20(rewardTokens[i]).safeTransfer(address(swapper), balance);

                    balances[i] = balance;
                }
            }
        }

        return (rewardTokens, balances);
    }

    function _getPoolBalance() private view returns (uint256 amount) {
        // will just return 0 if the nft does not exist.
        (amount,,,,,,,) = nftPool.getStakingPosition(nftId);
    }

    function _getRewards() private {
        // harvest $ARB rewards
        nitroPool.harvest();
        // must withdraw NFT from Nitro pool to harvest position
        nitroPool.withdraw(nftId);
        nftPool.harvestPosition(nftId);
        nftPool.safeTransferFrom(address(this), address(nitroPool), nftId);
        _handleXGrailRedemption();
    }

    function _handleXGrailRedemption() private {
        // redeem any finalized entries first.
        uint256 redeemsLength = xGRAIL.getUserRedeemsLength(address(this));
        for (uint256 i = 0; i < redeemsLength;) {
            (,, uint256 endTime,,) = xGRAIL.getUserRedeem(address(this), i);
            if (block.timestamp >= endTime) {
                xGRAIL.finalizeRedeem(i);
                redeemsLength -= 1;
            } else {
                i++;
            }
        }

        // add new entry.
        uint256 xGRAILBalance = IERC20(address(xGRAIL)).balanceOf(address(this));
        if (xGRAILBalance > 0) {
            uint256 minRedeemDuration = xGRAIL.minRedeemDuration();
            xGRAIL.redeem(xGRAILBalance, minRedeemDuration);
        }
    }

    function _getTokenWorth() private view returns (uint256[] memory amounts) {
        amounts = new uint256[](2);

        (uint256 amount0, uint256 amount1) = pool.getTotalAmounts();
        uint256 poolSupply = pool.totalSupply();
        uint256 poolBalance = _getPoolBalance();

        amounts[0] = (amount0 * poolBalance) / poolSupply;
        amounts[1] = (amount1 * poolBalance) / poolSupply;
    }

    function _transferToRecipient(address[] memory tokens, uint256[] memory amounts, address recipient) private {
        if (amounts[0] > 0) IERC20(tokens[0]).safeTransfer(recipient, amounts[0]);
        if (amounts[1] > 0) IERC20(tokens[1]).safeTransfer(recipient, amounts[1]);
    }
}
