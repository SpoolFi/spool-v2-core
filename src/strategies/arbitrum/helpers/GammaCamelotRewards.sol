// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../../access/SpoolAccessControllable.sol";
import "../../../external/interfaces/strategies/arbitrum/gamma-camelot/IAlgebraPool.sol";
import "../../../external/interfaces/strategies/arbitrum/gamma-camelot/ICamelotPair.sol";
import "../../../external/interfaces/strategies/arbitrum/gamma-camelot/IDividendsV2.sol";
import "../../../external/interfaces/strategies/arbitrum/gamma-camelot/IHypervisor.sol";
import "../../../external/interfaces/strategies/arbitrum/gamma-camelot/INFTPool.sol";
import "../../../external/interfaces/strategies/arbitrum/gamma-camelot/INitroPool.sol";
import "../../../external/interfaces/strategies/arbitrum/gamma-camelot/IXGrail.sol";
import "../../../strategies/Strategy.sol";
import "../../interfaces/helpers/IGammaCamelotRewards.sol";

error UnauthorizedAccess();

// Description:
// Handler for GRAIL/xGRAIL tokens from the Gamma-Camelot Strategy.
//
// For Gamma-Camelot, we receive 2 reward tokens from the NFT Pool: GRAIL and xGRAIL.
// We harvest them to this address for processing (we exceed max contract size if we handle in the strategy itself).
// GRAIL is a liquid, salable token, so we just send this back to the strategy, and our usual compound procedure will
// swap these for the pool tokens, WETH and USDC.
//
// xGRAIL, on the other hand, is not immediately liquid. There are two things that we do with xGRAIL:
//  1. We "redeem" xGRAIL for GRAIL. This process vests xGRAIL for the minimum duration allowed (as of contract
//     deployment, 15 days).
//     Every xGRAIL redemption adds a new entry to the xGRAIL contract, which is finalized after the duration. We call
//     this a redeem "cycle". Finalization withdraws GRAIL at 0.5 times the xGRAIL amount, and burns the xGRAIL.
//  2. While the xGRAIL is vested, we are entitled to "dividends" from Camelot (simply, extra rewards). As of contract
//     deployment, these rewards are CMLT-LP, Hypervisor, and xGRAIL.
//         - CMLT-LP: This is a Uniswap pair for WETH/USDC. To get rewards, the contracts burns the LP, to get back
//           WETH/USDC. It then sends it back to the strategy, so that it can be re-invested following compounding.
//         - Hypervisor: these are the same as the hypervisor tokens used in the strategy (Camelot LP shares). We send
//           these back to the strategy, to be re-invested following compound.
//         - xGRAIL: we also get back xGRAIL itself from dividends. This is immediately used in the next redeem cycle.
//
// The tokens received via dividends, and the dividends contract itself, are subject to change. Every xGRAIL redeem
// cycle could use a different dividends contract, and a different set of reward tokens. The contract will always
// collect all rewards, but only if extraRewards is true will it add the new reward to the rewards list to be swapped in
// compounding.
//
// There is 1 external entry point, "handle()", which does all of the above, returns the base reward tokens (GRAIL, ARB)
// , and assuming extraRewards is true, any other new reward tokens due to be swapped. Note that as of contract
// deployment, there is no new tokens from dividends to be swapped: the tokens received (denoted above) are
// automatically handled.
//
// The strategy also receives 1 reward token from the Nitro Pool: ARB.
// ARB is harvested in the strategy address to itself directly. This contract returns the ARB address, however, for
// easier processing (whatever list the strategy gets back is the rewards list to process).
contract GammaCamelotRewards is IGammaCamelotRewards, Initializable, SpoolAccessControllable {
    using SafeERC20 for IERC20;

    /// @notice GammaCamelot strategy.
    IStrategy public strategy;

    /// @notice dividends rewards as of contract deployment.
    ICamelotPair public pair;
    IXGrail public xGRAIL;
    IHypervisor public pool;

    /// @notice pair tokens of the pool.
    address[] public pairTokens;

    /// @notice known, liquid reward tokens (ARB, GRAIL)
    address[] public baseRewardTokens;

    /// @notice unknown reward tokens added to dividends, to be handled via swap
    /// @notice Temporary storage - for simplifying calculations at runtime only.
    address[] public extraRewardTokens;

    /// @notice reward tokens received via dividends for which we handle explicitly (ie. no swap)
    mapping(address => bool) public handledRewardTokens;

    /// @notice if we should try to swap unknown reward tokens received via dividends
    bool public extraRewards;

    constructor(ISpoolAccessControl accessControl_) SpoolAccessControllable(accessControl_) {}

    function initialize(IHypervisor pool_, INitroPool nitroPool_, IStrategy strategy_, bool extraRewards_)
        external
        initializer
    {
        if (address(strategy_) == address(0)) revert ConfigurationAddressZero();

        strategy = strategy_;
        extraRewards = extraRewards_;

        // assign contracts
        INFTPool nftPool = INFTPool(nitroPool_.nftPool());

        // assign reward and governance tokens
        (, address rewardToken0, address _xGRAIL,,,,,) = nftPool.getPoolInfo();
        address rewardToken1 = nitroPool_.rewardsToken1();

        baseRewardTokens.push(rewardToken0); // GRAIL
        baseRewardTokens.push(rewardToken1); // ARB
        xGRAIL = IXGrail(_xGRAIL);

        IDividendsV2 dividends = IDividendsV2(xGRAIL.dividendsAddress());
        pair = ICamelotPair(dividends.distributedToken(0));

        handledRewardTokens[address(pair)] = true; // Camelot-LP (burn, receive WETH/USDC)
        handledRewardTokens[address(xGRAIL)] = true; // xGRAIL (redeem for GRAIL, and used for dividends)
        handledRewardTokens[address(pool_)] = true; // Hypervisor (to be re-deposited directly again)

        IAlgebraPool underlyingPool = IAlgebraPool(pool_.pool());
        pairTokens.push(underlyingPool.token0());
        pairTokens.push(underlyingPool.token1());

        pool = pool_;
    }

    function updateExtraRewards(bool extraRewards_) external onlyRole(ROLE_SPOOL_ADMIN, msg.sender) {
        extraRewards = extraRewards_;
    }

    function handle() external returns (address[] memory rewardTokens) {
        if (msg.sender != address(strategy)) revert UnauthorizedAccess();
        _handleXGrailRedemption();
        _handlePairBurn();

        rewardTokens = _handleRewardTokens();

        // send any reward tokens received back to strategy
        _transferToStrategy(rewardTokens);

        // send any pair tokens received via pair.burn back to strategy (handled automatically)
        _transferToStrategy(pairTokens);

        // send any hypervisor tokens received via dividend rewards back to strategy (handled automatically)
        _transferToStrategy(address(pool));
    }

    function _handleXGrailRedemption() private {
        _xGrailFinalize();
        _xGrailRedeem();
    }

    function _xGrailFinalize() private {
        uint256 redeemsLength = xGRAIL.getUserRedeemsLength(address(this));
        if (redeemsLength == 0) return;
        for (uint256 i = (redeemsLength - 1); i >= 0; --i) {
            (,, uint256 endTime, address dividendsAddress,) = xGRAIL.getUserRedeem(address(this), i);
            if (block.timestamp >= endTime) {
                _handleDividends(dividendsAddress);
                xGRAIL.finalizeRedeem(i);
            }
        }
    }

    function _xGrailRedeem() private {
        // add new entry.
        uint256 xGRAILBalance = IERC20(address(xGRAIL)).balanceOf(address(this));
        if (xGRAILBalance > 0) {
            uint256 minRedeemDuration = xGRAIL.minRedeemDuration();
            xGRAIL.redeem(xGRAILBalance, minRedeemDuration);
        }
    }

    function _handleDividends(address dividendsAddress) private {
        IDividendsV2 dividends = IDividendsV2(dividendsAddress);
        if (extraRewards) {
            uint256 tokensLength = dividends.distributedTokensLength();
            for (uint256 i = 0; i < tokensLength; ++i) {
                address token = dividends.distributedToken(i);
                // ignore if:
                // - known reward, already handled by the contract
                if (handledRewardTokens[token]) {
                    continue;
                }

                extraRewardTokens.push(token);
            }
        }

        dividends.harvestAllDividends();
    }

    function _handlePairBurn() private {
        uint256 pairBalance = pair.balanceOf(address(this));
        if (pairBalance > 0) {
            pair.transfer(address(pair), pairBalance);
            pair.burn(address(this));
        }
    }

    function _handleRewardTokens() private returns (address[] memory rewardTokens) {
        rewardTokens = new address[](baseRewardTokens.length + extraRewardTokens.length);
        for (uint256 i = 0; i < baseRewardTokens.length; ++i) {
            rewardTokens[i] = baseRewardTokens[i];
        }

        if (extraRewards) {
            for (uint256 i = 0; i < extraRewardTokens.length; ++i) {
                rewardTokens[baseRewardTokens.length + i] = extraRewardTokens[i];
            }

            // empty extraRewardTokens for the next run.
            delete extraRewardTokens;
        }
    }

    function _transferToStrategy(address[] memory tokens) private {
        for (uint256 i = 0; i < tokens.length; ++i) {
            _transferToStrategy(tokens[i]);
        }
    }

    function _transferToStrategy(address token_) private {
        IERC20 token = IERC20(token_);
        uint256 balance = token.balanceOf(address(this));
        if (balance > 0) token.safeTransfer(address(strategy), balance);
    }
}
