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
import "../access/SpoolAccessControllable.sol";

abstract contract Strategy is ERC20Upgradeable, SpoolAccessControllable, IStrategy {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    uint256 internal constant INITIAL_SHARE_MULTIPLIER = 1000;

    IStrategyRegistry internal immutable _strategyRegistry;

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
        IStrategyRegistry strategyRegistry_,
        IAssetGroupRegistry assetGroupRegistry_,
        ISpoolAccessControl accessControl_
    ) SpoolAccessControllable(accessControl_) {
        _strategyName = strategyName_;
        _strategyRegistry = strategyRegistry_;
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

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function doHardWork(
        SwapInfo[] calldata swapInfo,
        uint256 withdrawnShares,
        address masterWallet,
        uint256[] calldata exchangeRates,
        IUsdPriceFeedManager priceFeedManager
    ) external returns (DhwInfo memory) {
        address[] memory tokens = _assetGroupRegistry.listAssetGroup(_assetGroupId);

        // usdWorth[0]: usd worth before deposit / withdrawal
        // usdWorth[1]: usd worth after deposit / withdrawal
        uint256[] memory usdWorth = new uint256[](2);

        // Compound and get USD value.
        compound();
        usdWorth[0] = getUsdWorth(exchangeRates, priceFeedManager);

        // assetsToDeposit[0..token.length-1]: amount of asset i to deposit
        // assetsToDeposit[token.length]: is there anything to deposit
        uint256[] memory assetsToDeposit = new uint256[](tokens.length + 1);
        unchecked {
            for (uint256 i; i < tokens.length; ++i) {
                assetsToDeposit[i] = IERC20(tokens[i]).balanceOf(address(this));

                if (assetsToDeposit[i] > 0) {
                    ++assetsToDeposit[tokens.length];
                }
            }
        }

        // shares[0]: matched shares
        // shares[1]: deposit share equivalent
        // shares[2]: minted shares
        uint256[] memory shares = new uint256[](3);

        // Calculate deposit share equivalent.
        if (assetsToDeposit[tokens.length] > 0) {
            uint256 valueToDeposit = priceFeedManager.assetToUsdCustomPriceBulk(tokens, assetsToDeposit, exchangeRates);

            unchecked {
                if (usdWorth[0] > 0) {
                    shares[1] = totalSupply() * valueToDeposit / usdWorth[0];
                } else {
                    shares[1] = INITIAL_SHARE_MULTIPLIER * valueToDeposit;
                }
            }

            // Match withdrawals and deposits by taking smaller value as matched shares.
            if (shares[1] < withdrawnShares) {
                shares[0] = shares[1];
            } else {
                shares[0] = withdrawnShares;
            }
        }

        uint256[] memory withdrawnAssets = new uint256[](tokens.length);
        bool withdrawn;
        if (shares[1] > withdrawnShares) {
            // Deposit is needed.

            // - match if needed
            if (shares[0] > 0) {
                unchecked {
                    for (uint256 i; i < tokens.length; ++i) {
                        withdrawnAssets[i] = assetsToDeposit[i] * shares[0] / shares[1];
                        assetsToDeposit[i] -= withdrawnAssets[i];
                    }
                }
                withdrawn = true;
            }

            // - swap assets
            // NOTE: how do we know the current amounts of tokens??
            swapAssets(tokens, swapInfo);

            // - deposit assets into the protocol
            depositToProtocol(tokens, assetsToDeposit);
            usdWorth[1] = getUsdWorth(exchangeRates, priceFeedManager);

            // - mint SSTs
            uint256 usdWorthDeposited = usdWorth[1] - usdWorth[0];
            unchecked {
                if (usdWorth[0] > 0) {
                    shares[2] = usdWorthDeposited * totalSupply() / usdWorth[0];
                } else {
                    shares[2] = usdWorthDeposited * INITIAL_SHARE_MULTIPLIER;
                }
            }
            _mint(address(this), shares[2]);

            shares[2] += shares[0];
        } else if (withdrawnShares > shares[1]) {
            // Withdrawal is needed.

            // - match if needed
            if (shares[0] > 0) {
                unchecked {
                    withdrawnShares -= shares[0];
                    shares[2] = shares[0];
                }
            }

            // - redeem shares from protocol
            redeemFromProtocol(tokens, withdrawnShares);
            _burn(address(this), withdrawnShares);
            withdrawn = true;

            // - figure out how much was withdrawn
            usdWorth[1] = getUsdWorth(exchangeRates, priceFeedManager);
            unchecked {
                for (uint256 i; i < tokens.length; ++i) {
                    withdrawnAssets[i] = IERC20(tokens[i]).balanceOf(address(this));
                }
            }
        } else {
            // Neither withdrawal nor deposit is needed.

            // - match if needed
            if (shares[0] > 0) {
                shares[2] = withdrawnShares;
                unchecked {
                    for (uint256 i; i < tokens.length; ++i) {
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
                for (uint256 i; i < tokens.length; ++i) {
                    IERC20(tokens[i]).safeTransfer(masterWallet, withdrawnAssets[i]);
                }
            }
        }

        return DhwInfo({sharesMinted: shares[2], assetsWithdrawn: withdrawnAssets});
    }

    // add access control
    function redeemFast(
        uint256 shares,
        address masterWallet,
        address[] memory assetGroup,
        uint256[] memory exchangeRates,
        IUsdPriceFeedManager priceFeedManager
    ) external returns (uint256[] memory) {
        // redeem shares from protocol
        redeemFromProtocol(assetGroup, shares);
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

    // add access control
    function depositFast(
        address[] calldata assetGroup,
        uint256[] calldata exchangeRates,
        IUsdPriceFeedManager priceFeedManager
    ) external returns (uint256) {
        // get amount of assets available to deposit
        uint256[] memory assetsToDeposit = new uint256[](assetGroup.length);
        for (uint256 i = 0; i < assetGroup.length; ++i) {
            assetsToDeposit[i] = IERC20(assetGroup[i]).balanceOf(address(this));
        }

        // deposit assets
        uint256 usdWorth0 = getUsdWorth(exchangeRates, priceFeedManager);
        depositToProtocol(assetGroup, assetsToDeposit);
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

    function compound( /* TODO: ADD PARAMS */ ) internal virtual;

    function swapAssets(address[] memory tokens, SwapInfo[] calldata swapInfo) internal virtual;

    function depositToProtocol(address[] memory tokens, uint256[] memory amounts) internal virtual;

    function getUsdWorth(uint256[] memory exchangeRates, IUsdPriceFeedManager priceFeedManager)
        internal
        virtual
        returns (uint256);

    function redeemFromProtocol(address[] memory tokens, uint256 ssts) internal virtual;

    /* ========== MODIFIERS ========== */
}
