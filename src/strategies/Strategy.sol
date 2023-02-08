// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/utils/math/Math.sol";
import "../interfaces/IAssetGroupRegistry.sol";
import "../interfaces/IMasterWallet.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/CommonErrors.sol";
import "../access/SpoolAccessControllable.sol";
import "../access/SpoolAccessControl.sol";

abstract contract Strategy is ERC20Upgradeable, SpoolAccessControllable, IStrategy {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    uint256 internal constant INITIAL_SHARE_MULTIPLIER = 1000;

    IAssetGroupRegistry internal immutable _assetGroupRegistry;

    // @notice Name of the strategy
    string private _strategyName;

    /**
     * @notice ID of the asset group used by the strategy.
     */
    uint256 internal _assetGroupId;

    // @notice Total value (in USD) of assets managed by the strategy.
    // @dev Should be updated in DHW with deposits, withdrawals and yields.
    uint256 public totalUsdValue = 0;

    constructor(
        string memory strategyName_,
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_
    ) SpoolAccessControllable(accessControl_) {
        _strategyName = strategyName_;
        _assetGroupRegistry = assetGroupRegistry_;
    }

    function __Strategy_init(uint256 assetGroupId_) internal onlyInitializing {
        _assetGroupId = assetGroupId_;

        __ERC20_init("Strategy Share Token", "SST");
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function getAPY() external view virtual returns (uint16);

    function assetGroupId() external view returns (uint256) {
        return _assetGroupId;
    }

    function assets() external view returns (address[] memory) {
        return _assetGroupRegistry.listAssetGroup(_assetGroupId);
    }

    function assetRatio() external view virtual returns (uint256[] memory);

    function strategyName() external view returns (string memory) {
        return _strategyName;
    }

    function beforeDepositCheck(uint256[] memory amounts, uint256[] calldata slippages) public view virtual;

    function beforeRedeemalCheck(uint256 ssts, uint256[] calldata slippages) public view virtual;

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function doHardWork(StrategyDhwParameterBag calldata dhwParams) external returns (DhwInfo memory dhwInfo) {
        _checkRole(ROLE_STRATEGY_REGISTRY, msg.sender);

        // assetsToDeposit[0..token.length-1]: amount of asset i to deposit
        // assetsToDeposit[token.length]: is there anything to deposit
        uint256[] memory assetsToDeposit = new uint256[](dhwParams.assetGroup.length + 1);
        unchecked {
            for (uint256 i; i < dhwParams.assetGroup.length; ++i) {
                assetsToDeposit[i] = IERC20(dhwParams.assetGroup[i]).balanceOf(address(this));

                if (assetsToDeposit[i] > 0) {
                    ++assetsToDeposit[dhwParams.assetGroup.length];
                }
            }
        }

        beforeDepositCheck(assetsToDeposit, dhwParams.slippages);
        beforeRedeemalCheck(dhwParams.withdrawnShares, dhwParams.slippages);

        // usdWorth[0]: usd worth before deposit / withdrawal
        // usdWorth[1]: usd worth after deposit / withdrawal
        uint256[] memory usdWorth = new uint256[](2);

        // Compound and get USD value.
        dhwInfo.yieldPercentage = _getYieldPercentage(0);
        dhwInfo.yieldPercentage += compound(dhwParams.compoundSwapInfo, dhwParams.slippages);
        usdWorth[0] = getUsdWorth(dhwParams.exchangeRates, dhwParams.priceFeedManager);

        uint256 matchedShares;
        uint256 depositShareEquivalent;
        uint256 mintedShares;
        uint256 withdrawnShares = dhwParams.withdrawnShares;

        // Calculate deposit share equivalent.
        if (assetsToDeposit[dhwParams.assetGroup.length] > 0) {
            uint256 valueToDeposit = dhwParams.priceFeedManager.assetToUsdCustomPriceBulk(
                dhwParams.assetGroup, assetsToDeposit, dhwParams.exchangeRates
            );

            unchecked {
                if (usdWorth[0] > 0) {
                    depositShareEquivalent = totalSupply() * valueToDeposit / usdWorth[0];
                } else {
                    depositShareEquivalent = INITIAL_SHARE_MULTIPLIER * valueToDeposit;
                }
            }

            // Match withdrawals and deposits by taking smaller value as matched shares.
            if (depositShareEquivalent < withdrawnShares) {
                matchedShares = depositShareEquivalent;
            } else {
                matchedShares = withdrawnShares;
            }
        }

        uint256[] memory withdrawnAssets = new uint256[](dhwParams.assetGroup.length);
        bool withdrawn;
        if (depositShareEquivalent > withdrawnShares) {
            // Deposit is needed.

            // - match if needed
            if (matchedShares > 0) {
                unchecked {
                    for (uint256 i; i < dhwParams.assetGroup.length; ++i) {
                        withdrawnAssets[i] = assetsToDeposit[i] * matchedShares / depositShareEquivalent;
                        assetsToDeposit[i] -= withdrawnAssets[i];
                    }
                }
                withdrawn = true;
            }

            // - swap assets
            swapAssets(dhwParams.assetGroup, assetsToDeposit, dhwParams.swapInfo);
            for (uint256 i; i < dhwParams.assetGroup.length; ++i) {
                assetsToDeposit[i] = IERC20(dhwParams.assetGroup[i]).balanceOf(address(this)) - withdrawnAssets[i];
            }

            // - deposit assets into the protocol
            depositToProtocol(dhwParams.assetGroup, assetsToDeposit, dhwParams.slippages);
            usdWorth[1] = getUsdWorth(dhwParams.exchangeRates, dhwParams.priceFeedManager);

            // - mint SSTs
            uint256 usdWorthDeposited = usdWorth[1] - usdWorth[0];
            unchecked {
                if (usdWorth[0] > 0) {
                    mintedShares = usdWorthDeposited * totalSupply() / usdWorth[0];
                } else {
                    mintedShares = usdWorthDeposited * INITIAL_SHARE_MULTIPLIER;
                }
            }
            _mint(address(this), mintedShares);

            mintedShares += matchedShares;
        } else if (withdrawnShares > depositShareEquivalent) {
            // Withdrawal is needed.

            // - match if needed
            if (matchedShares > 0) {
                unchecked {
                    withdrawnShares -= matchedShares;
                    mintedShares = matchedShares;
                }
            }

            // - redeem shares from protocol
            redeemFromProtocol(dhwParams.assetGroup, withdrawnShares, dhwParams.slippages);
            _burn(address(this), withdrawnShares);
            withdrawn = true;

            // - figure out how much was withdrawn
            usdWorth[1] = getUsdWorth(dhwParams.exchangeRates, dhwParams.priceFeedManager);
            unchecked {
                for (uint256 i; i < dhwParams.assetGroup.length; ++i) {
                    withdrawnAssets[i] = IERC20(dhwParams.assetGroup[i]).balanceOf(address(this));
                }
            }
        } else {
            // Neither withdrawal nor deposit is needed.

            // - match if needed
            if (matchedShares > 0) {
                mintedShares = withdrawnShares;
                unchecked {
                    for (uint256 i; i < dhwParams.assetGroup.length; ++i) {
                        withdrawnAssets[i] = assetsToDeposit[i];
                    }
                }
                withdrawn = true;
            }

            usdWorth[1] = usdWorth[0];
        }

        totalUsdValue = usdWorth[1];

        // Transfer withdrawn assets to master wallet if needed.
        if (withdrawn) {
            unchecked {
                for (uint256 i; i < dhwParams.assetGroup.length; ++i) {
                    IERC20(dhwParams.assetGroup[i]).safeTransfer(dhwParams.masterWallet, withdrawnAssets[i]);
                }
            }
        }

        dhwInfo.sharesMinted = mintedShares;
        dhwInfo.assetsWithdrawn = withdrawnAssets;
        dhwInfo.valueAtDhw = usdWorth[1]; // TODO
    }

    // TODO: add access control
    function redeemFast(
        uint256 shares,
        address masterWallet,
        address[] calldata assetGroup,
        uint256[] calldata exchangeRates,
        IUsdPriceFeedManager priceFeedManager,
        uint256[] calldata slippages
    ) external returns (uint256[] memory) {
        // redeem shares from protocol
        redeemFromProtocol(assetGroup, shares, slippages);
        _burn(address(this), shares);

        totalUsdValue = getUsdWorth(exchangeRates, priceFeedManager);

        // transfer assets to master wallet
        uint256[] memory assetsWithdrawn = new uint256[](assetGroup.length);
        for (uint256 i = 0; i < assetGroup.length; i++) {
            assetsWithdrawn[i] = IERC20(assetGroup[i]).balanceOf(address(this));
            IERC20(assetGroup[i]).safeTransfer(masterWallet, assetsWithdrawn[i]);
        }

        return assetsWithdrawn;
    }

    // TODO: add access control
    function depositFast(
        address[] calldata assetGroup,
        uint256[] calldata exchangeRates,
        IUsdPriceFeedManager priceFeedManager,
        uint256[] calldata slippages,
        SwapInfo[] calldata swapInfo
    ) external returns (uint256) {
        // get amount of assets available to deposit
        uint256[] memory assetsToDeposit = new uint256[](assetGroup.length);
        for (uint256 i = 0; i < assetGroup.length; ++i) {
            assetsToDeposit[i] = IERC20(assetGroup[i]).balanceOf(address(this));
        }

        // swap assets
        swapAssets(assetGroup, assetsToDeposit, swapInfo);
        for (uint256 i = 0; i < assetGroup.length; ++i) {
            assetsToDeposit[i] = IERC20(assetGroup[i]).balanceOf(address(this));
        }

        // deposit assets
        uint256 usdWorth0 = getUsdWorth(exchangeRates, priceFeedManager);
        depositToProtocol(assetGroup, assetsToDeposit, slippages);
        uint256 usdWorth1 = getUsdWorth(exchangeRates, priceFeedManager);

        // mint SSTs
        uint256 usdWorthDeposited = usdWorth1 - usdWorth0;
        uint256 sstsToMint;
        if (usdWorth0 > 0) {
            sstsToMint = usdWorthDeposited * totalSupply() / usdWorth0;
        } else {
            sstsToMint = usdWorthDeposited * INITIAL_SHARE_MULTIPLIER;
        }
        _mint(address(this), sstsToMint);

        totalUsdValue = usdWorth1;

        return sstsToMint;
    }

    function claimShares(address claimer, uint256 amount) external onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender) {
        _transfer(address(this), claimer, amount);
    }

    function releaseShares(address smartVault, uint256 amount)
        external
        onlyRole(ROLE_SMART_VAULT_MANAGER, msg.sender)
    {
        _transfer(smartVault, address(this), amount);
    }

    /* ========== PRIVATE/INTERNAL FUNCTIONS ========== */

    function compound(SwapInfo[] calldata compoundSwapInfo, uint256[] calldata slippages) internal virtual returns (int256 compoundYield);

    function _getYieldPercentage(int256 manualYield) internal virtual returns (int256);

    /**
     * @dev Swaps assets.
     * @param tokens Addresses of tokens to swap.
     * @param toSwap Available amounts to swap.
     * @param swapInfo Information on how to swap.
     */
    function swapAssets(address[] memory tokens, uint256[] memory toSwap, SwapInfo[] calldata swapInfo)
        internal
        virtual;

    /**
     * @dev Deposits assets into the underlying protocol.
     * @param tokens Addresses of asset tokens.
     * @param amounts Amounts to deposit.
     * @param slippages Slippages to guard depositing.
     */
    function depositToProtocol(address[] calldata tokens, uint256[] memory amounts, uint256[] calldata slippages)
        internal
        virtual;

    /**
     * @dev Redeems shares from the undelying protocol.
     * @param tokens Addresses of asset tokens.
     * @param ssts Amount of strategy tokens to redeem.
     * @param slippages Slippages to guard redeemal.
     */
    function redeemFromProtocol(address[] calldata tokens, uint256 ssts, uint256[] calldata slippages)
        internal
        virtual;

    function getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        virtual
        returns (uint256);

    /* ========== MODIFIERS ========== */
}
